package config

import (
	"os"
	"testing"
)

func TestLoadConfig(t *testing.T) {
	os.Setenv("MONGODB_URI", "mongodb://localhost:27017/testdb")
	os.Setenv("MONGODB_DATABASE", "gogotex_test")
	os.Setenv("REDIS_HOST", "localhost")
	os.Setenv("REDIS_PORT", "6379")
	os.Setenv("JWT_SECRET", "testsecret123456789012345678901234")
	// rate limit envs
	os.Setenv("RATE_LIMIT_ENABLED", "true")
	os.Setenv("RATE_LIMIT_RPS", "7")
	os.Setenv("RATE_LIMIT_BURST", "12")

	cfg, err := LoadConfig()
	if err != nil {
		t.Fatalf("LoadConfig failed: %v", err)
	}

	if cfg.MongoDB.URI == "" || cfg.Redis.Host == "" {
		t.Fatalf("unexpected empty config values: %+v", cfg)
	}
	if !cfg.RateLimit.Enabled || cfg.RateLimit.RPS != 7 || cfg.RateLimit.Burst != 12 {
		t.Fatalf("rate limit not loaded correctly: %+v", cfg.RateLimit)
	}
}
