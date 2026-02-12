package config

import (
	"log"
	"os"
	"time"

	"github.com/joho/godotenv"
	"github.com/spf13/viper"
)

// Config holds application configuration
type Config struct {
	Server    ServerConfig
	MongoDB   MongoDBConfig
	Redis     RedisConfig
	Keycloak  KeycloakConfig
	JWT       JWTConfig
	RateLimit RateLimitConfig
}

type ServerConfig struct {
	Port         string
	Host         string
	Environment  string
	ReadTimeout  time.Duration
	WriteTimeout time.Duration
}

type MongoDBConfig struct {
	URI      string
	Database string
	Timeout  time.Duration
}

type RedisConfig struct {
	Host     string
	Port     string
	Password string
	DB       int
}

type KeycloakConfig struct {
	URL          string
	Realm        string
	ClientID     string
	ClientSecret string
}

type JWTConfig struct {
	Secret          string
	AccessTokenTTL  time.Duration
	RefreshTokenTTL time.Duration
}

// RateLimitConfig controls the global in-memory rate limiter used by the auth service.
// - RPS: allowed requests per second
// - Burst: maximum burst tokens
// - Enabled: whether middleware is enabled
type RateLimitConfig struct {
	Enabled       bool
	RPS           float64
	Burst         int
	UseRedis      bool
	WindowSeconds int // window size in seconds for Redis fixed-window counter
}

// LoadConfig loads configuration from environment variables and .env file
func LoadConfig() (*Config, error) {
	_ = godotenv.Load("gogotex-support-services/.env")

	viper.AutomaticEnv()

	viper.SetDefault("SERVER_PORT", "5001")
	viper.SetDefault("SERVER_HOST", "0.0.0.0")
	viper.SetDefault("SERVER_ENVIRONMENT", "development")
	viper.SetDefault("MONGODB_TIMEOUT", 10)
	viper.SetDefault("JWT_ACCESS_TOKEN_TTL", 15)
	viper.SetDefault("JWT_REFRESH_TOKEN_TTL", 10080)

	// Rate limiting defaults
	viper.SetDefault("RATE_LIMIT_ENABLED", true)
	viper.SetDefault("RATE_LIMIT_RPS", 10)
	viper.SetDefault("RATE_LIMIT_BURST", 40)
	// Redis-backed rate limiter defaults
	viper.SetDefault("RATE_LIMIT_USE_REDIS", false)
	viper.SetDefault("RATE_LIMIT_WINDOW_SECONDS", 1)

	cfg := &Config{
		Server: ServerConfig{
			Port:        viper.GetString("SERVER_PORT"),
			Host:        viper.GetString("SERVER_HOST"),
			Environment: viper.GetString("SERVER_ENVIRONMENT"),
			ReadTimeout: 30 * time.Second,
			WriteTimeout: 30 * time.Second,
		},
		MongoDB: MongoDBConfig{
			URI:      getEnvOrPanic("MONGODB_URI"),
			Database: viper.GetString("MONGODB_DATABASE"),
			Timeout:  time.Duration(viper.GetInt("MONGODB_TIMEOUT")) * time.Second,
		},
		Redis: RedisConfig{
			Host:     viper.GetString("REDIS_HOST"),
			Port:     viper.GetString("REDIS_PORT"),
			Password: os.Getenv("REDIS_PASSWORD"),
			DB:       0,
		},
		Keycloak: KeycloakConfig{
			URL:          viper.GetString("KEYCLOAK_URL"),
			Realm:        viper.GetString("KEYCLOAK_REALM"),
			ClientID:     viper.GetString("KEYCLOAK_CLIENT_ID"),
			ClientSecret: viper.GetString("KEYCLOAK_CLIENT_SECRET"),
		},
		JWT: JWTConfig{
			Secret:          os.Getenv("JWT_SECRET"),
			AccessTokenTTL:  time.Duration(viper.GetInt("JWT_ACCESS_TOKEN_TTL")) * time.Minute,
			RefreshTokenTTL: time.Duration(viper.GetInt("JWT_REFRESH_TOKEN_TTL")) * time.Minute,
		},
		RateLimit: RateLimitConfig{
			Enabled:       viper.GetBool("RATE_LIMIT_ENABLED"),
			RPS:           float64(viper.GetFloat64("RATE_LIMIT_RPS")),
			Burst:         viper.GetInt("RATE_LIMIT_BURST"),
			UseRedis:      viper.GetBool("RATE_LIMIT_USE_REDIS"),
			WindowSeconds: viper.GetInt("RATE_LIMIT_WINDOW_SECONDS"),
		},
	}

	// Basic validation
	if cfg.JWT.Secret == "" {
		log.Println("WARNING: JWT_SECRET is not set; set a secure value in production")
	}

	return cfg, nil
}

func getEnvOrPanic(key string) string {
	v := os.Getenv(key)
	if v == "" {
		log.Fatalf("environment variable %s is required", key)
	}
	return v
}
