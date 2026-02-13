package tokens

import (
	"strings"
	"testing"
	"time"

	"github.com/gogotex/gogotex/backend/go-services/internal/config"
	"github.com/gogotex/gogotex/backend/go-services/internal/models"
	"github.com/golang-jwt/jwt/v5"
)

func TestGenerateAccessToken_ValidAndClaims(t *testing.T) {
	cfg := &config.Config{}
	cfg.JWT.Secret = "test-secret-32-bytes-should-be-long-enough"

	u := &models.User{Sub: "user-123", Name: "Test User", Email: "test@example.com"}
	tokenStr, err := GenerateAccessToken(cfg, u, 2*time.Minute)
	if err != nil {
		t.Fatalf("GenerateAccessToken error: %v", err)
	}

	// parse and validate
	parsed, err := jwt.Parse(tokenStr, func(token *jwt.Token) (interface{}, error) {
		return []byte(cfg.JWT.Secret), nil
	})
	if err != nil {
		t.Fatalf("failed to parse token: %v", err)
	}
	if !parsed.Valid {
		t.Fatalf("token should be valid")
	}
	claims, ok := parsed.Claims.(jwt.MapClaims)
	if !ok {
		t.Fatalf("claims type assertion failed")
	}
	if claims["sub"] != u.Sub {
		t.Fatalf("unexpected sub claim: got=%v want=%v", claims["sub"], u.Sub)
	}
}

func TestGenerateAccessToken_Expiry(t *testing.T) {
	cfg := &config.Config{}
	cfg.JWT.Secret = "another-secret-32-bytes-longgggg"
	u := &models.User{Sub: "u2", Name: "X", Email: "x@x"}
	tokenStr, err := GenerateAccessToken(cfg, u, 1*time.Second)
	if err != nil {
		t.Fatalf("GenerateAccessToken error: %v", err)
	}
	// wait for expiry
	time.Sleep(2 * time.Second)
	_, err = jwt.Parse(tokenStr, func(token *jwt.Token) (interface{}, error) { return []byte(cfg.JWT.Secret), nil })
	if err == nil {
		t.Fatalf("expected token parse to fail after expiry")
	}
}

func TestParseToken_WrongSecretFails(t *testing.T) {
	cfg := &config.Config{}
	cfg.JWT.Secret = "secret-one-32-bytes-xxxxxxxxxxxxxxxx"
	u := &models.User{Sub: "u3", Name: "Bob", Email: "bob@example.com"}
	tokenStr, err := GenerateAccessToken(cfg, u, 2*time.Minute)
	if err != nil {
		t.Fatalf("GenerateAccessToken error: %v", err)
	}
	// attempt to parse with a different secret
	_, err = jwt.Parse(tokenStr, func(token *jwt.Token) (interface{}, error) { return []byte("different-secret-xxxxxxxxxxxxxxxx"), nil })
	if err == nil {
		t.Fatalf("expected parse to fail with wrong secret")
	}
}

func TestParseToken_Malformed(t *testing.T) {
	// not a JWT
	_, err := jwt.Parse("not.a.jwt", func(token *jwt.Token) (interface{}, error) { return []byte("x"), nil })
	if err == nil {
		t.Fatalf("expected parse to fail for malformed token")
	}
}

// Rejected when alg=none (unsigned token)
func TestParseToken_AlgNoneRejected(t *testing.T) {
	// header {"alg":"none"}
	payload := `{"sub":"u-none","exp":9999999999}`
	headerEnc := jwt.EncodeSegment([]byte(`{"alg":"none"}`))
	payloadEnc := jwt.EncodeSegment([]byte(payload))
	tok := headerEnc + "." + payloadEnc + "."
	_, err := jwt.Parse(tok, func(token *jwt.Token) (interface{}, error) { return []byte("x"), nil })
	if err == nil {
		t.Fatalf("expected parse to reject alg=none token")
	}
}

// Tampering with payload must fail signature verification
func TestParseToken_TamperedPayload(t *testing.T) {
	cfg := &config.Config{}
	cfg.JWT.Secret = "tamper-test-secret-32-bytes-xxxxxxx"
	u := &models.User{Sub: "user-t", Name: "Tamper", Email: "t@example.com"}
	tokenStr, err := GenerateAccessToken(cfg, u, 5*time.Minute)
	if err != nil {
		t.Fatalf("GenerateAccessToken error: %v", err)
	}
	// tamper payload: replace sub value
	parts := strings.Split(tokenStr, ".")
	if len(parts) != 3 {
		t.Fatalf("unexpected token parts")
	}
	payloadBytes, _ := jwt.DecodeSegment(parts[1])
	payloadStr := string(payloadBytes)
	payloadStr = strings.Replace(payloadStr, "user-t", "attacker", 1)
	parts[1] = jwt.EncodeSegment([]byte(payloadStr))
	tampered := strings.Join(parts, ".")
	_, err = jwt.Parse(tampered, func(token *jwt.Token) (interface{}, error) { return []byte(cfg.JWT.Secret), nil })
	if err == nil {
		t.Fatalf("expected signature verification to fail for tampered token")
	}
}