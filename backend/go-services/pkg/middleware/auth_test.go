package middleware

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	mr "github.com/alicebob/miniredis/v2"
	"github.com/gin-gonic/gin"
	"github.com/gogotex/gogotex/backend/go-services/internal/sessions"
	"github.com/redis/go-redis/v9"
	"github.com/stretchr/testify/require"
)

// fakeToken implements Token
type fakeToken struct {
	data map[string]interface{}
}

func (t *fakeToken) Claims(v interface{}) error {
	if mm, ok := v.(*map[string]interface{}); ok {
		*mm = t.data
		return nil
	}
	return fmt.Errorf("unsupported claims type")
}

// fakeVerifier implements Verifier
type fakeVerifier struct{}

func (f *fakeVerifier) Verify(ctx context.Context, raw string) (Token, error) {
	if raw == "goodtoken" {
		return &fakeToken{data: map[string]interface{}{"sub": "user1", "email": "test@example.com"}}, nil
	}
	return nil, fmt.Errorf("invalid token")
}

func TestAuthMiddleware_NoHeader(t *testing.T) {
	g := gin.New()
	req := httptest.NewRequest(http.MethodGet, "/", nil)
	rw := httptest.NewRecorder()

	g.GET("/", AuthMiddleware(&fakeVerifier{}), func(c *gin.Context) {
		c.Status(http.StatusOK)
	})
	g.ServeHTTP(rw, req)

	require.Equal(t, http.StatusUnauthorized, rw.Code)
}

func TestAuthMiddleware_InvalidHeader(t *testing.T) {
	g := gin.New()
	req := httptest.NewRequest(http.MethodGet, "/", nil)
	req.Header.Set("Authorization", "BadHeader")
	rw := httptest.NewRecorder()

	g.GET("/", AuthMiddleware(&fakeVerifier{}), func(c *gin.Context) {
		c.Status(http.StatusOK)
	})
	g.ServeHTTP(rw, req)

	require.Equal(t, http.StatusUnauthorized, rw.Code)
}

func TestAuthMiddleware_ValidToken(t *testing.T) {
	g := gin.New()
	req := httptest.NewRequest(http.MethodGet, "/", nil)
	req.Header.Set("Authorization", "Bearer goodtoken")
	rw := httptest.NewRecorder()

	g.GET("/", AuthMiddleware(&fakeVerifier{}), func(c *gin.Context) {
		claims, ok := c.Get("claims")
		require.True(t, ok)
		resp, _ := json.Marshal(gin.H{"claims": claims})
		c.Writer.Write(resp)
	})
	g.ServeHTTP(rw, req)

	require.Equal(t, http.StatusOK, rw.Code)
	var got map[string]interface{}
	require.NoError(t, json.Unmarshal(rw.Body.Bytes(), &got))
	require.Contains(t, got, "claims")
}

func TestAuthMiddleware_RejectsBlacklistedToken(t *testing.T) {
	m, err := mr.Run()
	require.NoError(t, err)
	defer m.Close()
	client := redis.NewClient(&redis.Options{Addr: m.Addr()})
	sessions.SetBlacklistClient(client)

	// add token to blacklist
	token := "black-token"
	require.NoError(t, sessions.BlacklistAccessToken(context.Background(), token, 5*time.Second))

	g := gin.New()
	req := httptest.NewRequest(http.MethodGet, "/", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	rw := httptest.NewRecorder()

	g.GET("/", AuthMiddleware(&fakeVerifier{}), func(c *gin.Context) { c.Status(http.StatusOK) })
	g.ServeHTTP(rw, req)

	require.Equal(t, http.StatusUnauthorized, rw.Code)
}
