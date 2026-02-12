package sessions

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"time"
)

// Service wraps repository operations with business logic
type Service struct {
	repo Repository
}

func NewService(r Repository) *Service { return &Service{repo: r} }

// CreateSession stores a new refresh session and returns the refresh token
func (s *Service) CreateSession(ctx context.Context, sub string, ttl time.Duration) (string, error) {
	b := make([]byte, 32)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	r := hex.EncodeToString(b)
	sess := &Session{
		RefreshToken: r,
		Sub:          sub,
		ExpiresAt:    time.Now().UTC().Add(ttl),
	}
	if err := s.repo.Create(ctx, sess); err != nil {
		return "", err
	}
	return r, nil
}

// ValidateRefresh returns the session if refresh token is valid and not expired
func (s *Service) ValidateRefresh(ctx context.Context, refresh string) (*Session, error) {
	sess, err := s.repo.GetByRefresh(ctx, refresh)
	if err != nil {
		return nil, err
	}
	if sess == nil {
		return nil, nil
	}
	if time.Now().UTC().After(sess.ExpiresAt) {
		// cleanup expired session
		_ = s.repo.DeleteByRefresh(ctx, refresh)
		return nil, nil
	}
	return sess, nil
}

func (s *Service) DeleteRefresh(ctx context.Context, refresh string) error {
	return s.repo.DeleteByRefresh(ctx, refresh)
}
