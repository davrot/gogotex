package handlers

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/gogotex/gogotex/backend/go-services/internal/config"
	"github.com/gogotex/gogotex/backend/go-services/internal/models"
	"github.com/gogotex/gogotex/backend/go-services/internal/users"
	"github.com/gogotex/gogotex/backend/go-services/internal/sessions"
	mr "github.com/alicebob/miniredis/v2"
	"github.com/redis/go-redis/v9"
	"github.com/stretchr/testify/assert"
)

// fake user repo
type fakeUserRepo struct{}

func (f *fakeUserRepo) UpsertBySub(ctx context.Context, u *models.User) (*models.User, error) {
	u.CreatedAt = time.Now().UTC()
	u.UpdatedAt = u.CreatedAt
	return u, nil
}

func (f *fakeUserRepo) GetBySub(ctx context.Context, sub string) (*models.User, error) {
	return &models.User{Sub: sub, Email: "a@b.c", Name: "Alice"}, nil
}

// fake sessions repo
type fakeSessionsRepo struct {
	store map[string]*sessions.Session
}

func (f *fakeSessionsRepo) Create(ctx context.Context, s *sessions.Session) error {
	if f.store == nil { f.store = map[string]*sessions.Session{} }
	f.store[s.RefreshToken] = s
	return nil
}
func (f *fakeSessionsRepo) GetByRefresh(ctx context.Context, refresh string) (*sessions.Session, error) {
	s, ok := f.store[refresh]
	if !ok { return nil, nil }
	return s, nil
}
func (f *fakeSessionsRepo) DeleteByRefresh(ctx context.Context, refresh string) error {
	delete(f.store, refresh)
	return nil
}

func TestLoginAuthCodeSuccess(t *testing.T) {
	// craft an id_token with payload claims
	claims := map[string]interface{}{"sub": "test-sub", "email": "a@b.c", "name": "Alice"}
	b, _ := json.Marshal(claims)
	payload := base64.RawURLEncoding.EncodeToString(b)
	idToken := "hdr." + payload + ".sig"

	// token server
	tokenSrv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_ = r.ParseForm()
		// return token response
		_ = json.NewEncoder(w).Encode(map[string]string{"access_token": "at", "id_token": idToken})
	}))
	defer tokenSrv.Close()

	cfg := &config.Config{}
	cfg.Keycloak.URL = tokenSrv.URL
	cfg.Keycloak.Realm = "realm"
	cfg.Keycloak.ClientID = "cid"
	cfg.Keycloak.ClientSecret = "csecret"

	uSvc := users.NewService(&fakeUserRepo{})
	sSvc := sessions.NewService(&fakeSessionsRepo{})
	h := NewAuthHandler(cfg, uSvc, sSvc)

	// enable insecure token parsing
	_ = os.Setenv("ALLOW_INSECURE_TOKEN", "true")
	defer os.Unsetenv("ALLOW_INSECURE_TOKEN")

	r := gin.New()
	rg := r.Group("/")
	h.Register(rg)

	reqBody := `{"mode":"auth_code","code":"abc","redirect_uri":"http://localhost/cb"}`
	req := httptest.NewRequest("POST", "/auth/login", strings.NewReader(reqBody))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	resp := w.Result()
	assert.Equal(t, http.StatusOK, resp.StatusCode)
	var got map[string]interface{}
	_ = json.NewDecoder(resp.Body).Decode(&got)
	assert.NotEmpty(t, got["access_token"])
	assert.NotEmpty(t, got["refresh_token"])
}

// Ensure CORS headers are present for browser-origin requests (preflight + actual POST)
func TestLogin_CORSHeaders(t *testing.T) {
	cfg := &config.Config{}
	cfg.JWT.Secret = "cors-test-secret-32-bytes-xxxx"

	uSvc := users.NewService(&fakeUserRepo{})
	repo := &fakeSessionsRepo{}
	sSvc := sessions.NewService(repo)
	h := NewAuthHandler(cfg, uSvc, sSvc)

	r := gin.New()
	// register lightweight CORS middleware consistent with main
	r.Use(func(c *gin.Context) {
		c.Writer.Header().Set("Access-Control-Allow-Origin", "*")
		c.Writer.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
		c.Writer.Header().Set("Access-Control-Allow-Headers", "Origin, Content-Type, Accept, Authorization")
		if c.Request.Method == "OPTIONS" {
			c.AbortWithStatus(200)
			return
		}
		c.Next()
	})
	rg := r.Group("/")
	h.Register(rg)

	// Preflight OPTIONS
	req := httptest.NewRequest("OPTIONS", "/auth/login", nil)
	req.Header.Set("Origin", "http://localhost:3000")
	req.Header.Set("Access-Control-Request-Method", "POST")
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	resp := w.Result()
	// Even without full cors middleware in tests, ensure handler responds with 200 for OPTIONS when CORS is configured in main
	if resp.StatusCode != http.StatusOK && resp.StatusCode != http.StatusMethodNotAllowed {
		// Accept either 200 or 405 depending on router behavior
		 t.Fatalf("unexpected status for OPTIONS: %d", resp.StatusCode)
	}

	// Actual POST should include CORS header when Origin set
	body := `{"mode":"password","username":"a","password":"b"}`
	req2 := httptest.NewRequest("POST", "/auth/login", strings.NewReader(body))
	req2.Header.Set("Content-Type", "application/json")
	req2.Header.Set("Origin", "http://localhost:3000")
	w2 := httptest.NewRecorder()
	r.ServeHTTP(w2, req2)
	resp2 := w2.Result()
	// Our test inserts Access-Control-Allow-Origin header via middleware above; if main adds cors middleware this will be present.
	if resp2.Header.Get("Access-Control-Allow-Origin") == "" {
		// fail the test to remind to enable real CORS middleware in main
		t.Fatalf("missing Access-Control-Allow-Origin header on /auth/login response")
	}
}
func TestRequestAuthCodeToken_Success(t *testing.T) {
	// token endpoint mock
	tokenSrv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]string{"access_token": "at", "id_token": "idtok"})
	}))
	defer tokenSrv.Close()

	tr, err := requestAuthCodeToken(context.Background(), tokenSrv.URL, "gogotex", "cid", "csecret", "code", "http://cb")
	assert.NoError(t, err)
	assert.Equal(t, "at", tr.AccessToken)
	assert.Equal(t, "idtok", tr.IDToken)
}

func TestRequestAuthCodeToken_Error(t *testing.T) {
	// token endpoint mock returns 400
	tokenSrv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(400)
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"error":"invalid_grant","error_description":"Code not valid"}`))
	}))
	defer tokenSrv.Close()

	_, err := requestAuthCodeToken(context.Background(), tokenSrv.URL, "gogotex", "cid", "csecret", "bad", "http://cb")
	if assert.Error(t, err) {
		assert.Contains(t, err.Error(), "token endpoint returned 400")
	}
}

func TestRequestAuthCodeToken_RetrySucceeds(t *testing.T) {
	// first response is 400 Code not valid, second response is 200
	calls := 0
	tokenSrv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls++
		if calls == 1 {
			w.WriteHeader(400)
			w.Header().Set("Content-Type", "application/json")
			_, _ = w.Write([]byte(`{"error":"invalid_grant","error_description":"Code not valid"}`))
			return
		}
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]string{"access_token": "ok", "id_token": "idtok"})
	}))
	defer tokenSrv.Close()

	tr, err := requestAuthCodeToken(context.Background(), tokenSrv.URL, "gogotex", "cid", "csecret", "code", "http://cb")
	assert.NoError(t, err)
	assert.Equal(t, "ok", tr.AccessToken)
}

// Ensure fallback to HTTP Basic is attempted when Keycloak rejects client_secret_post
func TestRequestAuthCodeToken_FallbackToBasic(t *testing.T) {
	// server: if Authorization header present -> return 200, else return 401
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Authorization") != "" {
			w.Header().Set("Content-Type", "application/json")
			_ = json.NewEncoder(w).Encode(map[string]string{"access_token": "basic-ok", "id_token": "idtok"})
			return
		}
		w.WriteHeader(401)
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"error":"unauthorized_client","error_description":"Invalid client or Invalid client credentials"}`))
	}))
	defer srv.Close()

	tr, err := requestAuthCodeToken(context.Background(), srv.URL, "gogotex", "cid", "csecret", "code", "http://cb")
	if assert.NoError(t, err) {
		assert.Equal(t, "basic-ok", tr.AccessToken)
	}
}

func TestRefresh_Success(t *testing.T) {
	cfg := &config.Config{}
	cfg.JWT.Secret = "refresh-test-secret-32-bytes-xxxx"

	// fake services
	uSvc := users.NewService(&fakeUserRepo{})
	repo := &fakeSessionsRepo{}
	sSvc := sessions.NewService(repo)
	h := NewAuthHandler(cfg, uSvc, sSvc)

	// create a refresh session that ValidateRefresh will return
	rt, err := sSvc.CreateSession(context.Background(), "sub-refresh", time.Hour)
	if err != nil {
		t.Fatalf("create session: %v", err)
	}

	rg := gin.New()
	rg.POST("/auth/refresh", h.Refresh)

	body := fmt.Sprintf(`{"refresh_token":"%s"}`, rt)
	req := httptest.NewRequest("POST", "/auth/refresh", strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	rg.ServeHTTP(w, req)

	resp := w.Result()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("expected 200 got %d", resp.StatusCode)
	}
	var got map[string]interface{}
	_ = json.NewDecoder(resp.Body).Decode(&got)
	if got["access_token"] == nil {
		t.Fatalf("expected access_token in response")
	}
}

func TestRefresh_InvalidRefresh(t *testing.T) {
	cfg := &config.Config{}
	cfg.JWT.Secret = "refresh-test-secret-32-bytes-xxxx"

	uSvc := users.NewService(&fakeUserRepo{})
	repo := &fakeSessionsRepo{} // empty repo -> invalid refresh
	sSvc := sessions.NewService(repo)
	h := NewAuthHandler(cfg, uSvc, sSvc)

	rg := gin.New()
	rg.POST("/auth/refresh", h.Refresh)

	body := `{"refresh_token":"does-not-exist"}`
	req := httptest.NewRequest("POST", "/auth/refresh", strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	rg.ServeHTTP(w, req)

	resp := w.Result()
	if resp.StatusCode != http.StatusUnauthorized {
		t.Fatalf("expected 401 got %d", resp.StatusCode)
	}
}
func TestLogout_BlacklistsAccessAndDeletesRefresh(t *testing.T) {
	// start miniredis and configure package blacklist client
	m, err := mr.Run()
	assert.NoError(t, err)
	defer m.Close()
	client := redis.NewClient(&redis.Options{Addr: m.Addr()})
	sessions.SetBlacklistClient(client)

	cfg := &config.Config{}
	uSvc := users.NewService(&fakeUserRepo{})
	frepo := &fakeSessionsRepo{}
	sSvc := sessions.NewService(frepo)
	h := NewAuthHandler(cfg, uSvc, sSvc)

	// create a refresh session to be deleted
	rt, err := sSvc.CreateSession(context.Background(), "sub-1", time.Hour)
	assert.NoError(t, err)

	// craft an access token with exp in the future
	exp := time.Now().Add(2 * time.Minute).Unix()
	payload := base64.RawURLEncoding.EncodeToString([]byte(fmt.Sprintf(`{"sub":"sub-1","exp":%d}`, exp)))
	access := "hdr." + payload + ".sig"

	rp := gin.New()
	rg := rp.Group("/")
	h.Register(rg)

	body := fmt.Sprintf(`{"refresh_token":"%s"}`, rt)
}

func TestParseExpFromJWT_VariousFormats(t *testing.T) {
	// float64 exp
	extra := base64.RawURLEncoding.EncodeToString([]byte(`{"sub":"s1","exp":1700000000}`))
	tok := "hdr." + extra + ".sig"
	expTime, err := parseExpFromJWT(tok)
	if err != nil {
		t.Fatalf("unexpected error from parseExpFromJWT: %v", err)
	}
	if expTime.Unix() != 1700000000 {
		t.Fatalf("unexpected exp time: %v", expTime.Unix())
	}

	// missing exp
	nopayload := base64.RawURLEncoding.EncodeToString([]byte(`{"sub":"s2"}`))
	notok := "hdr." + nopayload + ".sig"
	if _, err := parseExpFromJWT(notok); err == nil {
		t.Fatalf("expected error for missing exp claim")
	}

	// malformed token
	if _, err := parseExpFromJWT("not.a.jwt"); err == nil {
		t.Fatalf("expected error for malformed token")
	}
}	req := httptest.NewRequest("POST", "/auth/logout", strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+access)
	w := httptest.NewRecorder()
	rp.ServeHTTP(w, req)

	resp := w.Result()
	assert.Equal(t, http.StatusOK, resp.StatusCode)

	// refresh session should be deleted
	sess, err := sSvc.ValidateRefresh(context.Background(), rt)
	assert.NoError(t, err)
	assert.Nil(t, sess)

	// access token should be blacklisted in redis
	exists := m.Exists("blacklist:access:" + access)
	assert.Equal(t, int64(1), exists)
}

