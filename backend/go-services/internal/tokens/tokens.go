package tokens

import (
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/gogotex/gogotex/backend/go-services/internal/models"
	"github.com/gogotex/gogotex/backend/go-services/internal/config"
)

// GenerateAccessToken creates a signed JWT access token for the user
func GenerateAccessToken(cfg *config.Config, u *models.User, ttl time.Duration) (string, error) {
	claims := jwt.MapClaims{
		"sub": u.Sub,
		"name": u.Name,
		"email": u.Email,
		"iat": time.Now().Unix(),
		"exp": time.Now().Add(ttl).Unix(),
	}
	jt := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return jt.SignedString([]byte(cfg.JWT.Secret))
}
