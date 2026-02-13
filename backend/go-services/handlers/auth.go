package handlers

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"github.com/gogotex/gogotex/backend/go-services/pkg/logger"
	"os"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/gogotex/gogotex/backend/go-services/internal/config"
	"github.com/gogotex/gogotex/backend/go-services/internal/oidc"
	"github.com/gogotex/gogotex/backend/go-services/internal/sessions"
	"github.com/gogotex/gogotex/backend/go-services/internal/tokens"
	"github.com/gogotex/gogotex/backend/go-services/internal/users"
)

// LoginRequest used for password-mode login (dev/testing)
type LoginRequest struct {
	Mode        string `json:"mode" binding:"required"` // "password" | "auth_code"
	Username    string `json:"username"`
	Password    string `json:"password"`
	Code        string `json:"code"`         // authorization code
	RedirectURI string `json:"redirect_uri"` // redirect uri used in auth code flow
}

// AuthHandler holds dependencies
type AuthHandler struct {
	cfg        *config.Config
	usersSvc   *users.Service
	sessionsSvc *sessions.Service
}

func NewAuthHandler(cfg *config.Config, u *users.Service, s *sessions.Service) *AuthHandler {
	return &AuthHandler{cfg: cfg, usersSvc: u, sessionsSvc: s}
}

// Register routes under /auth
func (h *AuthHandler) Register(rg *gin.RouterGroup) {
	a := rg.Group("/auth")
	a.POST("/login", h.Login)
	a.POST("/refresh", h.Refresh)
	a.POST("/logout", h.Logout)
}

// Login implements a minimal login: password grant (dev/testing) and authorization-code exchange
func (h *AuthHandler) Login(c *gin.Context) {
	var req LoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	if req.Mode != "password" && req.Mode != "auth_code" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "unsupported mode"})
		return
	}
	host := h.cfg.Keycloak.URL
	realm := h.cfg.Keycloak.Realm
	if host == "" || realm == "" {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Keycloak not configured"})
		return
	}

	var tokenResp *tokenResponse
	var err error
	if req.Mode == "password" {
		// password grant
		tokenResp, err = requestPasswordToken(c.Request.Context(), host, realm, h.cfg.Keycloak.ClientID, h.cfg.Keycloak.ClientSecret, req.Username, req.Password, h.cfg)
		if err != nil {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "authentication failed", "details": err.Error()})
			return
		}
	} else {
		// authorization code exchange
		if req.Code == "" || req.RedirectURI == "" {
			c.JSON(http.StatusBadRequest, gin.H{"error": "code and redirect_uri required for auth_code mode"})
			return
		}
		// log a safe, truncated diagnostic to help CI debugging (do not log full secrets)
		logger.Debugf("Login(auth_code): received code length=%d redirect_uri=%s", len(req.Code), req.RedirectURI)
		tokenResp, err = requestAuthCodeToken(c.Request.Context(), host, realm, h.cfg.Keycloak.ClientID, h.cfg.Keycloak.ClientSecret, req.Code, req.RedirectURI)
		if err != nil {
			// log token exchange error with redirect URI for easier debugging in CI/integration runs
			logger.Errorf("auth-code token exchange error (redirect_uri=%q): %v", req.RedirectURI, err)
			c.JSON(http.StatusUnauthorized, gin.H{"error": "authentication failed", "details": err.Error(), "redirect_uri_used": req.RedirectURI})
			return
		}
	}
	// verify id_token and upsert user
	claims, err := verifyIDToken(c.Request.Context(), tokenResp.IDToken, h.cfg)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid id token", "details": err.Error()})
		return
	}
	u, err := h.usersSvc.UpsertFromClaims(c.Request.Context(), claims)
	if err != nil {
		logger.Errorf("user upsert error: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "user upsert failed", "details": err.Error()})
		return
	}
	if u == nil {
		logger.Errorf("user upsert returned nil user (claims missing 'sub')")
		c.JSON(http.StatusInternalServerError, gin.H{"error": "user upsert failed", "details": "no user returned from upsert"})
		return
	}
	// create refresh session
	rft, err := h.sessionsSvc.CreateSession(c.Request.Context(), u.Sub, 7*24*time.Hour)
	if err != nil {
		logger.Errorf("failed to create session: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create session", "details": err.Error()})
		return
	}
	// create access token
	access, err := tokens.GenerateAccessToken(h.cfg, u, 15*time.Minute)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create access token"})
		return
	}
	// Return camelCase response to match frontend `LoginResponse` shape
	c.JSON(http.StatusOK, gin.H{"accessToken": access, "refreshToken": rft, "user": u, "expiresIn": 900})
}

// Refresh accepts a refresh token and returns a new access token
func (h *AuthHandler) Refresh(c *gin.Context) {
	var req struct{ RefreshToken string `json:"refresh_token" binding:"required"` }
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	sess, err := h.sessionsSvc.ValidateRefresh(c.Request.Context(), req.RefreshToken)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "validation failed"})
		return
	}
	if sess == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid refresh token"})
		return
	}
	// load user
	u, err := h.usersSvc.GetBySub(c.Request.Context(), sess.Sub)
	if err != nil || u == nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "user lookup failed"})
		return
	}
	access, err := tokens.GenerateAccessToken(h.cfg, u, 15*time.Minute)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create access token"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"access_token": access, "expires_in": 900})
}

// Logout invalidates the refresh token and (optionally) blacklists the current access token
func (h *AuthHandler) Logout(c *gin.Context) {
	var req struct{ RefreshToken string `json:"refresh_token" binding:"required"` }
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	// If the client supplied an Authorization Bearer token, attempt to blacklist it
	auth := c.GetHeader("Authorization")
	if auth != "" {
		var at string
		if n, _ := fmt.Sscanf(auth, "Bearer %s", &at); n == 1 {
			if exp, err := parseExpFromJWT(at); err == nil {
				ttl := time.Until(exp)
				if ttl > 0 {
					if err := sessions.BlacklistAccessToken(c.Request.Context(), at, ttl); err != nil {
						c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to blacklist access token"})
						return
					}
				}
			}
		}
	}

	if err := h.sessionsSvc.DeleteRefresh(c.Request.Context(), req.RefreshToken); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to remove session"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "logged out"})
}

// parseExpFromJWT decodes the JWT payload and returns the `exp` claim as time.Time.
// This performs payload-only parsing (no signature verification) and is suitable
// for computing remaining TTLs for blacklisting purposes.
func parseExpFromJWT(tok string) (time.Time, error) {
	parts := strings.Split(tok, ".")
	if len(parts) < 2 {
		return time.Time{}, fmt.Errorf("invalid token")
	}
	payload := parts[1]
	b, err := base64.RawURLEncoding.DecodeString(payload)
	if err != nil {
		// try standard base64 (pad) as a fallback
		b, err = base64.StdEncoding.DecodeString(payload)
		if err != nil {
			return time.Time{}, err
		}
	}
	var claims map[string]interface{}
	if err := json.Unmarshal(b, &claims); err != nil {
		return time.Time{}, err
	}
	v, ok := claims["exp"]
	if !ok {
		return time.Time{}, fmt.Errorf("exp claim not present")
	}
	// exp may be float64 (json number) or json.Number; handle common cases
	switch vv := v.(type) {
	case float64:
		return time.Unix(int64(vv), 0), nil
	case int64:
		return time.Unix(vv, 0), nil
	case json.Number:
		i64, err := vv.Int64()
		if err != nil {
			f, err2 := vv.Float64()
			if err2 != nil {
				return time.Time{}, err
			}
			return time.Unix(int64(f), 0), nil
		}
		return time.Unix(i64, 0), nil
	default:
		return time.Time{}, fmt.Errorf("unsupported exp type %T", v)
	}
}

// The functions requestPasswordToken and verifyIDToken are lightweight helpers implemented in the same package file
// to keep the handler tidy. They use HTTP requests and the OIDC verifier.

// NOTE: to avoid cyclic imports we keep the implementation local and simple.

type tokenResponse struct {
	AccessToken string `json:"access_token"`
	IDToken     string `json:"id_token"`
}

func requestPasswordToken(ctx context.Context, host, realm, clientID, clientSecret, username, password string, cfg *config.Config) (*tokenResponse, error) {
	// direct HTTP POST
	tokenURL := host + "/realms/" + realm + "/protocol/openid-connect/token"
	// Use net/http
	form := urlValues(map[string]string{
		"grant_type": "password",
		"client_id":  clientID,
		"client_secret": clientSecret,
		"username": username,
		"password": password,
	})
	resp, err := http.Post(tokenURL, "application/x-www-form-urlencoded", form)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		b, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("token endpoint returned %d: %s", resp.StatusCode, string(b))
	}
	var tr tokenResponse
	if err := json.NewDecoder(resp.Body).Decode(&tr); err != nil {
		return nil, err
	}
	return &tr, nil
}

func requestAuthCodeToken(ctx context.Context, host, realm, clientID, clientSecret, code, redirectURI string) (*tokenResponse, error) {
	// token exchange for authorization code
	tokenURL := host + "/realms/" + realm + "/protocol/openid-connect/token"
	formValues := map[string]string{
		"grant_type":    "authorization_code",
		"client_id":     clientID,
		"client_secret": clientSecret,
		"code":          code,
		"redirect_uri":  redirectURI,
	}

	// Try the token exchange; if we get a transient 'Code not valid' we retry once (reduces flakiness in CI)
	logger.Infof("requestAuthCodeToken: tokenURL=%s client_id=%s client_secret_set=%t redirect_uri=%s", tokenURL, clientID, clientSecret != "", redirectURI)
	for attempt := 1; attempt <= 2; attempt++ {
		// Use HTTP Basic auth for client authentication (more robust across Keycloak configs)
		// Build raw form string (we keep the redacted version for logs)
		v := url.Values{}
		for k, vv := range formValues {
			v.Set(k, vv)
		}
		bodyStrRaw := v.Encode()
		redactedBody := bodyStrRaw
		if clientSecret != "" {
			redactedBody = strings.ReplaceAll(redactedBody, url.QueryEscape(clientSecret), "<redacted>")
		}
		// replace code with length-only for safety
		if cv, ok := formValues["code"]; ok {
			redactedBody = strings.ReplaceAll(redactedBody, url.QueryEscape(cv), fmt.Sprintf("<len=%d>", len(cv)))
		}

		form := strings.NewReader(bodyStrRaw)
		req, err := http.NewRequestWithContext(ctx, "POST", tokenURL, form)
		if err != nil {
			if attempt == 2 {
				return nil, err
			}
			time.Sleep(100 * time.Millisecond)
			continue
		}
		req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
		// Log headers (redact Authorization) and the redacted body so CI has full context
		hdrs := map[string]string{}
		for k, vv := range req.Header {
			hdrs[k] = strings.Join(vv, ",")
		}
		if a := req.Header.Get("Authorization"); a != "" {
			hdrs["Authorization"] = "<present>"
		}
		logger.Infof("requestAuthCodeToken: outgoing-request url=%s headers=%v body=%s", tokenURL, hdrs, redactedBody)
		logger.Infof("requestAuthCodeToken: outgoing-form-redacted=%s", redactedBody)

		// Primary attempt: use client_secret in form body (client_secret_post).
		resp, err := http.DefaultClient.Do(req)
		if err == nil && resp.StatusCode == http.StatusUnauthorized {
			// Read and log Keycloak response body/headers for diagnostics
			b, _ := io.ReadAll(resp.Body)
			_ = resp.Body.Close()
			bodyStr := string(b)
			logger.Warnf("requestAuthCodeToken: primary exchange returned 401; keycloak_resp_body=%s keycloak_resp_headers=%v", strings.TrimSpace(bodyStr), resp.Header)

			// Write a temporary debug file inside the container (redacted) for post-mortem
			_ = os.WriteFile("/tmp/requestAuthCodeToken.debug.txt", []byte(fmt.Sprintf("tokenURL=%s\nrequest_headers=%v\nrequest_body=%s\nkeycloak_resp_status=%d\nkeycloak_resp_body=%s\n", tokenURL, hdrs, redactedBody, resp.StatusCode, bodyStr)), 0600)

			logger.Warnf("requestAuthCodeToken: retrying with HTTP Basic auth (fallback)")

			// build a new request and try Basic auth
			form2 := strings.NewReader(bodyStrRaw)
			req2, err2 := http.NewRequestWithContext(ctx, "POST", tokenURL, form2)
			if err2 == nil {
				req2.Header.Set("Content-Type", "application/x-www-form-urlencoded")
				if clientSecret != "" {
					req2.SetBasicAuth(clientID, clientSecret)
					logger.Infof("requestAuthCodeToken: retry-request Authorization=<present> (Basic)")
				} else {
					logger.Infof("requestAuthCodeToken: retry-request Authorization=<missing-client-secret>")
				}
				resp, err = http.DefaultClient.Do(req2)
			}
		}
		if err != nil {
			if attempt == 2 {
				return nil, err
			}
			time.Sleep(100 * time.Millisecond)
			continue
		}
		defer resp.Body.Close()
		if resp.StatusCode != http.StatusOK {
			b, _ := io.ReadAll(resp.Body)
			bodyStr := string(b)
			// If Keycloak responded with Code not valid, allow one quick retry
			if resp.StatusCode == http.StatusBadRequest && strings.Contains(bodyStr, "Code not valid") && attempt == 1 {
				time.Sleep(150 * time.Millisecond)
				continue
			}
			return nil, fmt.Errorf("token endpoint returned %d: %s", resp.StatusCode, bodyStr)
		}
		var tr tokenResponse
		if err := json.NewDecoder(resp.Body).Decode(&tr); err != nil {
			return nil, err
		}
		return &tr, nil
	}
	return nil, fmt.Errorf("token exchange failed after retries")
}

func verifyIDToken(ctx context.Context, idToken string, cfg *config.Config) (map[string]interface{}, error) {
	// Use the OIDC verifier if available, otherwise fall back to insecure parsing when allowed
	// We perform a minimal parse: when ALLOW_INSECURE_TOKEN=true we just decode payload
	// Normalize issuer
	issuer := strings.TrimRight(cfg.Keycloak.URL, "/") + "/realms/" + cfg.Keycloak.Realm
	ver, err := oidc.NewVerifier(ctx, issuer, cfg.Keycloak.ClientID)
	if err != nil {
		if strings.ToLower(strings.TrimSpace(os.Getenv("ALLOW_INSECURE_TOKEN"))) == "true" {
			iv := oidc.NewInsecureVerifier()
			tkn, err := iv.Verify(ctx, idToken)
			if err != nil {
				return nil, err
			}
			var claims map[string]interface{}
			if err := tkn.Claims(&claims); err != nil {
				return nil, err
			}
			return claims, nil
		}
		return nil, err
	}
	idt, err := ver.Verify(ctx, idToken)
	if err != nil {
		return nil, err
	}
	var claims map[string]interface{}
	if err := idt.Claims(&claims); err != nil {
		return nil, err
	}
	return claims, nil
}

// small helpers below

// (helpers implemented inline below)

func urlValues(m map[string]string) io.Reader {
	v := url.Values{}
	for k, vv := range m {
		v.Set(k, vv)
	}
	return strings.NewReader(v.Encode())
}
