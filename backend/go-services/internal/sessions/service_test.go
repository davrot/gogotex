package sessions

import (
	"context"
	"testing"
	"time"
)

// fake repo for testing
type fakeRepo struct {
	store map[string]*Session
}

func (f *fakeRepo) Create(ctx context.Context, s *Session) error {
	if f.store == nil {
		f.store = map[string]*Session{}
	}
	f.store[s.RefreshToken] = s
	return nil
}
func (f *fakeRepo) GetByRefresh(ctx context.Context, refresh string) (*Session, error) {
	if f.store == nil {
		return nil, nil
	}
	s, ok := f.store[refresh]
	if !ok {
		return nil, nil
	}
	return s, nil
}
func (f *fakeRepo) DeleteByRefresh(ctx context.Context, refresh string) error {
	if f.store == nil {
		return nil
	}
	delete(f.store, refresh)
	return nil
}

func TestCreateAndValidateSession(t *testing.T) {
	repo := &fakeRepo{}
	svc := NewService(repo)
	ctx := context.Background()
	r, err := svc.CreateSession(ctx, "sub-1", time.Hour)
	if err != nil {
		t.Fatalf("create failed: %v", err)
	}
	if r == "" {
		t.Fatalf("expected refresh token")
	}
	// validate
	sess, err := svc.ValidateRefresh(ctx, r)
	if err != nil {
		t.Fatalf("validate error: %v", err)
	}
	if sess == nil || sess.Sub != "sub-1" {
		t.Fatalf("unexpected session: %v", sess)
	}
	// delete
	if err := svc.DeleteRefresh(ctx, r); err != nil {
		t.Fatalf("delete failed: %v", err)
	}
	sess2, _ := svc.ValidateRefresh(ctx, r)
	if sess2 != nil {
		t.Fatalf("expected session removed")
	}
}

func TestValidateRefresh_Expired(t *testing.T) {
	repo := &fakeRepo{}
	svc := NewService(repo)
	ctx := context.Background()
	// create a session with past expiry
	s := &Session{RefreshToken: "r-exp", Sub: "s1", ExpiresAt: time.Now().Add(-1 * time.Hour)}
	repo.store = map[string]*Session{"r-exp": s}

	res, err := svc.ValidateRefresh(ctx, "r-exp")
	if err != nil {
		t.Fatalf("ValidateRefresh error: %v", err)
	}
	if res != nil {
		t.Fatalf("expected expired session to be nil")
	}
	// ensure repo no longer contains it
	if _, ok := repo.store["r-exp"]; ok {
		t.Fatalf("expected expired session to be deleted by ValidateRefresh")
	}
}