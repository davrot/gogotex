package oidc

import (
	"context"
	"fmt"

	"github.com/coreos/go-oidc/v3/oidc"
	"github.com/gogotex/gogotex/backend/go-services/pkg/middleware"
)

// IDToken is a minimal interface for token payloads that allows extracting claims
// It is satisfied by *oidc.IDToken and by test fakes.
type IDToken interface {
	Claims(v interface{}) error
}

// Verifier wraps the OIDC provider and token verifier
type Verifier struct {
	ctx      context.Context
	provider *oidc.Provider
	verifier *oidc.IDTokenVerifier
}

// NewVerifier creates a new OIDC verifier for the given issuer and client ID
func NewVerifier(ctx context.Context, issuer, clientID string) (*Verifier, error) {
	provider, err := oidc.NewProvider(ctx, issuer)
	if err != nil {
		return nil, fmt.Errorf("failed to discover OIDC provider: %w", err)
	}
	verifier := provider.Verifier(&oidc.Config{ClientID: clientID})
	return &Verifier{ctx: ctx, provider: provider, verifier: verifier}, nil
}

// Verify verifies the provided raw ID token using the provided context and returns a middleware.Token
func (v *Verifier) Verify(ctx context.Context, raw string) (middleware.Token, error) {
	idToken, err := v.verifier.Verify(ctx, raw)
	if err != nil {
		return nil, err
	}
	return idToken, nil
}
