package middleware

import (
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	mr "github.com/alicebob/miniredis/v2"
	"github.com/gin-gonic/gin"
	"github.com/redis/go-redis/v9"
	"github.com/stretchr/testify/require"
)

func TestRedisRateLimitMiddleware_Basic(t *testing.T) {
	m, err := mr.Run()
	require.NoError(t, err)
	defer m.Close()

	client := redis.NewClient(&redis.Options{Addr: m.Addr()})

	r := gin.New()
	r.Use(RedisRateLimitMiddleware(client, 1, 0, 1*time.Second)) // 1 req/sec, no burst
	r.GET("/r", func(c *gin.Context) { c.JSON(200, gin.H{"ok": true}) })

	// first request allowed
	rq1 := httptest.NewRequest("GET", "/r", nil)
	w1 := httptest.NewRecorder()
	r.ServeHTTP(w1, rq1)
	require.Equal(t, http.StatusOK, w1.Code)

	// immediate second request -> blocked
	rq2 := httptest.NewRequest("GET", "/r", nil)
	w2 := httptest.NewRecorder()
	r.ServeHTTP(w2, rq2)
	require.Equal(t, http.StatusTooManyRequests, w2.Code)

	// advance miniredis clock past window and request should be allowed
	m.FastForward(2 * time.Second)
	rq3 := httptest.NewRequest("GET", "/r", nil)
	w3 := httptest.NewRecorder()
	r.ServeHTTP(w3, rq3)
	require.Equal(t, http.StatusOK, w3.Code)
}