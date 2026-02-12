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
	req := httptest.NewRequest("POST", "/auth/logout", strings.NewReader(body))
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

