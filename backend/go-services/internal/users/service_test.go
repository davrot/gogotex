package users

import (
	"context"
	"testing"
	"time"

	"github.com/gogotex/gogotex/backend/go-services/internal/models"
)

type fakeRepo struct {
	lastUpsert *models.User
	upsertErr  error
}

func (f *fakeRepo) UpsertBySub(ctx context.Context, u *models.User) (*models.User, error) {
	f.lastUpsert = u
	// simulate repository behavior: ensure timestamps are set
	now := time.Now().UTC()
	if f.lastUpsert.CreatedAt.IsZero() {
		f.lastUpsert.CreatedAt = now
	}
	f.lastUpsert.UpdatedAt = now
	// return a copy with an ID set
	ret := *f.lastUpsert
	ret.ID = "abcd1234"
	return &ret, f.upsertErr
}

func (f *fakeRepo) GetBySub(ctx context.Context, sub string) (*models.User, error) {
	return nil, nil
}

func TestUpsertFromClaims(t *testing.T) {
	repo := &fakeRepo{}
	svc := NewService(repo)
	ctx := context.Background()
	claims := map[string]interface{}{
		"sub":   "sub-123",
		"email": "x@example.com",
		"name":  "X User",
	}

	u, err := svc.UpsertFromClaims(ctx, claims)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if u == nil {
		t.Fatal("expected user, got nil")
	}
	if u.Sub != "sub-123" {
		t.Fatalf("unexpected sub: %s", u.Sub)
	}
	if u.Email != "x@example.com" {
		t.Fatalf("unexpected email: %s", u.Email)
	}
	if u.Name != "X User" {
		t.Fatalf("unexpected name: %s", u.Name)
	}
	if repo.lastUpsert == nil {
		t.Fatal("expected repository UpsertBySub to be called")
	}
	// expect timestamps to be set
	if repo.lastUpsert.CreatedAt.IsZero() || repo.lastUpsert.UpdatedAt.IsZero() {
		t.Fatalf("expected timestamps to be set: created=%v updated=%v", repo.lastUpsert.CreatedAt, repo.lastUpsert.UpdatedAt)
	}
	// CreatedAt should be <= UpdatedAt
	if repo.lastUpsert.CreatedAt.After(repo.lastUpsert.UpdatedAt) {
		t.Fatalf("createdAt after updatedAt: %v > %v", repo.lastUpsert.CreatedAt, repo.lastUpsert.UpdatedAt)
	}

	// Ensure ID returned is preserved
	if u.ID == "" {
		t.Fatalf("expected returned user to have an ID set by repo")
	}

	// Test missing sub => returns nil
	u2, err := svc.UpsertFromClaims(ctx, map[string]interface{}{"email": "y@e.com"})
	if err != nil {
		t.Fatalf("unexpected error on missing sub: %v", err)
	}
	if u2 != nil {
		t.Fatalf("expected nil when sub missing, got: %v", u2)
	}
}
