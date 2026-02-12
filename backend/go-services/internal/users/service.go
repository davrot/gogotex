package users

import (
	"context"

	"github.com/gogotex/gogotex/backend/go-services/internal/models"
)

// Service encapsulates user-related business logic
type Service struct {
	repo UserRepository
}

func NewService(r UserRepository) *Service {
	return &Service{repo: r}
}

// UpsertFromClaims creates or updates a user using OIDC claims map
func (s *Service) UpsertFromClaims(ctx context.Context, claims map[string]interface{}) (*models.User, error) {
	sub, _ := claims["sub"].(string)
	email, _ := claims["email"].(string)
	name, _ := claims["name"].(string)
	if sub == "" {
		return nil, nil
	}
	u := &models.User{
		Sub:   sub,
		Email: email,
		Name:  name,
	}
	return s.repo.UpsertBySub(ctx, u)
}

func (s *Service) GetBySub(ctx context.Context, sub string) (*models.User, error) {
	return s.repo.GetBySub(ctx, sub)
}
