package oidc

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"strings"

	"github.com/gogotex/gogotex/backend/go-services/pkg/middleware"
)

// insecureToken is a minimal token that exposes claims parsed from a JWT payload.
type insecureToken struct {
	claims map[string]interface{}
}

func (t *insecureToken) Claims(v interface{}) error {
	b, err := json.Marshal(t.claims)
	if err != nil {
		return err
	}
	return json.Unmarshal(b, v)
}

// InsecureVerifier implements a verifier that does NOT validate signatures.
// Only intended for local/integration tests under explicit opt-in via env var.
type InsecureVerifier struct{}

func NewInsecureVerifier() *InsecureVerifier { return &InsecureVerifier{} }

func (v *InsecureVerifier) Verify(ctx context.Context, raw string) (middleware.Token, error) {
	parts := strings.Split(raw, ".")
	if len(parts) < 2 {
		return nil, errors.New("invalid token format")
	}
	payload := parts[1]
	// pad base64
	if m := len(payload) % 4; m != 0 {
		payload += strings.Repeat("=", 4-m)
	}
	data, err := base64.URLEncoding.DecodeString(payload)
	if err != nil {
		return nil, err
	}
	var claims map[string]interface{}
	if err := json.Unmarshal(data, &claims); err != nil {
		return nil, err
	}
	return &insecureToken{claims: claims}, nil
}
