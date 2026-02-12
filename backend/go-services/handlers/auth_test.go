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
