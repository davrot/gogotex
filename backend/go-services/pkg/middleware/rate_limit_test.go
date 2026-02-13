package middleware

import (
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/gogotex/gogotex/backend/go-services/pkg/metrics"
	"github.com/prometheus/client_golang/prometheus/testutil"
	"github.com/stretchr/testify/require"
)

func TestRateLimitMiddleware_AllowsUnderLimit(t *testing.T) {
	r := gin.New()
	r.Use(RateLimitMiddleware(10, 2)) // generous rate
	r.GET("/ok", func(c *gin.Context) { c.JSON(200, gin.H{"ok": true}) })

	req := httptest.NewRequest("GET", "/ok", nil)
	w := httptest.NewRecorder()

	// two quick requests should pass
	r.ServeHTTP(w, req)
	req2 := httptest.NewRequest("GET", "/ok", nil)
	w2 := httptest.NewRecorder()
	r.ServeHTTP(w2, req2)

	require.Equal(t, http.StatusOK, w.Code)
	require.Equal(t, http.StatusOK, w2.Code)

	// verify metrics incremented for memory limiter
	require.Equal(t, 2.0, testutil.ToFloat64(metrics.RateLimitAllowed.WithLabelValues("memory")))
}

func TestRateLimitMiddleware_BlocksWhenExceeded(t *testing.T) {
	r := gin.New()
	// very low rate to force rejections
	r.Use(RateLimitMiddleware(0.5, 1))
	r.GET("/limited", func(c *gin.Context) { c.JSON(200, gin.H{"ok": true}) })

	// first request -> allowed
	rq1 := httptest.NewRequest("GET", "/limited", nil)
	w1 := httptest.NewRecorder()
	r.ServeHTTP(w1, rq1)
	require.Equal(t, http.StatusOK, w1.Code)

	// immediate second request -> should be rate-limited
	rq2 := httptest.NewRequest("GET", "/limited", nil)
	w2 := httptest.NewRecorder()
	r.ServeHTTP(w2, rq2)
	require.Equal(t, http.StatusTooManyRequests, w2.Code)

	// wait for half a second (0.5s) to replenish one token and it should be allowed
	time.Sleep(600 * time.Millisecond)
	rq3 := httptest.NewRequest("GET", "/limited", nil)
	w3 := httptest.NewRecorder()
	r.ServeHTTP(w3, rq3)
	require.Equal(t, http.StatusOK, w3.Code)
}

func TestRateLimitMiddleware_UsesSubjectWhenPresent(t *testing.T) {
	r := gin.New()
	// middleware that injects claims before rate limiter
	r.Use(func(c *gin.Context) {
		c.Set("claims", map[string]interface{}{"sub": "user-123"})
		c.Next()
	})
	r.Use(RateLimitMiddleware(0.5, 1))
	r.GET("/u", func(c *gin.Context) { c.JSON(200, gin.H{"ok": true}) })

	// first request allowed
	rq1 := httptest.NewRequest("GET", "/u", nil)
	w1 := httptest.NewRecorder()
	r.ServeHTTP(w1, rq1)
	require.Equal(t, http.StatusOK, w1.Code)

	// immediate second request => rejected for same subject
	rq2 := httptest.NewRequest("GET", "/u", nil)
	w2 := httptest.NewRecorder()
	r.ServeHTTP(w2, rq2)
	require.Equal(t, http.StatusTooManyRequests, w2.Code)
}
