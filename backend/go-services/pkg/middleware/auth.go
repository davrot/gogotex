package middleware

import (
	"context"
	"fmt"
	"net/http"

	"github.com/gin-gonic/gin"
	)

// Token is minimal interface for a verified token that can expose claims
type Token interface {
	Claims(v interface{}) error
}

// Verifier is the minimal interface the middleware depends on
type Verifier interface {
	Verify(ctx context.Context, raw string) (Token, error)
}

// AuthMiddleware returns a Gin middleware that verifies Bearer tokens using the provided verifier
func AuthMiddleware(ver Verifier) gin.HandlerFunc {
	return func(c *gin.Context) {
		auth := c.GetHeader("Authorization")
		if auth == "" {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "missing Authorization header"})
			return
		}
		// Expect 'Bearer <token>'
		var token string
		if n, _ := fmt.Sscanf(auth, "Bearer %s", &token); n != 1 {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "invalid Authorization header"})
			return
		}

		idToken, err := ver.Verify(c.Request.Context(), token)
		if err != nil {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "invalid token", "details": err.Error()})
			return
		}

		// Extract claims
		var claims map[string]interface{}
		if err := idToken.Claims(&claims); err != nil {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "failed to parse claims"})
			return
		}

		c.Set("claims", claims)
		c.Next()
	}
}
