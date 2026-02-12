package middleware

import (
	"fmt"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/redis/go-redis/v9"
	"github.com/gogotex/gogotex/backend/go-services/pkg/metrics"
)

// RedisRateLimitMiddleware provides a coarse fixed-window Redis-backed limiter.
// Keying: prefers `claims.sub` when present, otherwise uses client IP.
// Algorithm: INCR a per-window key and compare against allowed = floor(rps*windowSeconds)+burst.
// This is intentionally simple and deterministic (suitable for distributed deployments).
func RedisRateLimitMiddleware(client *redis.Client, rps float64, burst int, window time.Duration) gin.HandlerFunc {
	if client == nil {
		// fallback to in-memory if no client
		return RateLimitMiddleware(rps, burst)
	}
	windowSeconds := int(window.Seconds())
	if windowSeconds <= 0 {
		windowSeconds = 1
	}
	allowedPerWindow := int(rps*float64(windowSeconds)) + burst
	return func(c *gin.Context) {
		var key string
		if v, ok := c.Get("claims"); ok {
			if cm, ok2 := v.(map[string]interface{}); ok2 {
				if sub, ok3 := cm["sub"].(string); ok3 && sub != "" {
					key = "rl:sub:" + sub
				}
			}
		}
		if key == "" {
			ip := c.ClientIP()
			if ip == "" {
				ip = "unknown"
			}
			key = "rl:ip:" + ip
		}

		// window bucket suffix
		bucket := time.Now().Unix() / int64(windowSeconds)
		redisKey := fmt.Sprintf("%s:%d", key, bucket)

		cnt, err := client.Incr(c.Request.Context(), redisKey).Result()
		if err != nil {
			c.AbortWithStatusJSON(http.StatusInternalServerError, gin.H{"error": "Rate limit check failed"})
			return
		}
		if cnt == 1 {
			// set expiration for the bucket
			_ = client.Expire(c.Request.Context(), redisKey, time.Duration(windowSeconds+1)*time.Second).Err()
		}
		if int(cnt) > allowedPerWindow {
			c.Header("Retry-After", fmt.Sprintf("%d", windowSeconds))
			// metric: redis rejected
			metrics.RateLimitRejected.WithLabelValues("redis").Inc()
			c.AbortWithStatusJSON(http.StatusTooManyRequests, gin.H{"error": "Rate limit exceeded"})
			return
		}
		// metric: redis allowed
		metrics.RateLimitAllowed.WithLabelValues("redis").Inc()
		c.Next()
	}
}