package middleware

import (
	"net/http"
	"sync"

	"github.com/gin-gonic/gin"
	"github.com/gogotex/gogotex/backend/go-services/pkg/metrics"
	"golang.org/x/time/rate"
)

// per-key limiter store (simple in-memory token-bucket)
var limiterStore sync.Map // map[string]*rate.Limiter

// getLimiter returns (and lazily creates) a token-bucket limiter for the given key
func getLimiter(key string, rps float64, burst int) *rate.Limiter {
	v, ok := limiterStore.Load(key)
	if ok {
		return v.(*rate.Limiter)
	}
	lim := rate.NewLimiter(rate.Limit(rps), burst)
	limiterStore.Store(key, lim)
	return lim
}

// RateLimitMiddleware returns a Gin middleware enforcing a token-bucket per-key limit.
// Key selection: when request context contains a `claims` map with `sub`, that value is used
// (per-user NAT-friendly limiting). Otherwise the client IP from Gin is used.
// rps = allowed events per second, burst = maximum tokens in bucket.
func RateLimitMiddleware(rps float64, burst int) gin.HandlerFunc {
	return func(c *gin.Context) {
		// pick key: prefer authenticated subject when present
		var key string
		if v, ok := c.Get("claims"); ok {
			if cm, ok2 := v.(map[string]interface{}); ok2 {
				if sub, ok3 := cm["sub"].(string); ok3 && sub != "" {
					key = "sub:" + sub
				}
			}
		}
		if key == "" {
			ip := c.ClientIP()
			if ip == "" {
				ip = "unknown"
			}
			key = "ip:" + ip
		}

		lim := getLimiter(key, rps, burst)
		if !lim.Allow() {
			// set common rate limit headers (informational)
			c.Header("Retry-After", "1")
			// record metric and reject
			metrics.RateLimitRejected.WithLabelValues("memory").Inc()
			c.AbortWithStatusJSON(http.StatusTooManyRequests, gin.H{"error": "Rate limit exceeded"})
			return
		}
		// record allowed
		metrics.RateLimitAllowed.WithLabelValues("memory").Inc()
		c.Next()
	}
}
