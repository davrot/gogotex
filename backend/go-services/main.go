package main

import (
	"fmt"
	"log"
	"context"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/gogotex/gogotex/backend/go-services/internal/config"
	"github.com/gogotex/gogotex/backend/go-services/internal/oidc"
	"strings"
	"os"
	"github.com/gogotex/gogotex/backend/go-services/internal/database"
	"github.com/gogotex/gogotex/backend/go-services/internal/sessions"
	"github.com/gogotex/gogotex/backend/go-services/internal/users"
	"github.com/gogotex/gogotex/backend/go-services/handlers"
	"github.com/gogotex/gogotex/backend/go-services/pkg/middleware"
	"github.com/redis/go-redis/v9"
)


func main() {
	cfg, err := config.LoadConfig()
	if err != nil {
		log.Fatalf("failed to load config: %v", err)
	}

	r := gin.New()
// Global middlewares: logging + recovery
r.Use(gin.Logger(), gin.Recovery())

// Optional global rate limiter (per-user when authenticated, otherwise per-IP)
if cfg.RateLimit.Enabled {
	r.Use(middleware.RateLimitMiddleware(cfg.RateLimit.RPS, cfg.RateLimit.Burst))
}
	// Basic health endpoint
	r.GET("/health", func(c *gin.Context) {
		c.String(http.StatusOK, "healthy")
	})

	// readiness endpoint
	r.GET("/ready", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "ready", "uptime": fmt.Sprintf("%s", time.Since(startTime))})
	})

	// Keycloak OIDC verifier and protected sample endpoint
	ctx := context.Background()
	var verifier middleware.Verifier
	if cfg.Keycloak.URL != "" && cfg.Keycloak.ClientID != "" && cfg.Keycloak.Realm != "" {
		issuer := strings.TrimRight(cfg.Keycloak.URL, "/") + "/realms/" + cfg.Keycloak.Realm
		ver, err := oidc.NewVerifier(ctx, issuer, cfg.Keycloak.ClientID)
		if err != nil {
			log.Printf("Warning: failed to initialize OIDC verifier: %v", err)
		} else {
			verifier = ver
		}
	} else if cfg.Keycloak.URL != "" && cfg.Keycloak.ClientID != "" {
		// Fallback: try URL as issuer (older deployments may expose realm path in URL)
		ver, err := oidc.NewVerifier(ctx, cfg.Keycloak.URL, cfg.Keycloak.ClientID)
		if err != nil {
			log.Printf("Warning: failed to initialize OIDC verifier (fallback): %v", err)
		} else {
			verifier = ver
		}
	}

	// Optional insecure verifier for integration tests: parse token claims without signature verification
	if verifier == nil {
		val := strings.ToLower(strings.TrimSpace(os.Getenv("ALLOW_INSECURE_TOKEN")))
		log.Printf("DEBUG: ALLOW_INSECURE_TOKEN=%q", val)
		if val == "true" {
			log.Printf("Warning: enabling insecure OIDC verifier (integration mode)")
			verifier = oidc.NewInsecureVerifier()
		}
	}

	// Connect to MongoDB and initialize user and session services
	var userSvc *users.Service
	var sessionsSvc *sessions.Service

	// Prefer Redis-based sessions when configured (fast, in-memory)
	if cfg.Redis.Host != "" {
		// create Redis client
		importedRedis := func() *redis.Client {
			opt := &redis.Options{Addr: cfg.Redis.Host + ":" + cfg.Redis.Port}
			if cfg.Redis.Password != "" {
				opt.Password = cfg.Redis.Password
			}
			return redis.NewClient(opt)
		}()

		// validate connection
		if err := importedRedis.Ping(ctx).Err(); err == nil {
			// sessions stored in Redis
			srepo := sessions.NewRedisRepository(importedRedis, "session:")
			sessionsSvc = sessions.NewService(srepo)
			// expose Redis client for blacklist checks
			sessions.SetBlacklistClient(importedRedis)
			log.Printf("Connected to Redis for session storage: %s:%s", cfg.Redis.Host, cfg.Redis.Port)
		} else {
			log.Printf("Warning: failed to connect to Redis (%s:%s): %v", cfg.Redis.Host, cfg.Redis.Port, err)
		}
	}

	// Fallback: MongoDB-backed services (users + sessions)
	if sessionsSvc == nil && cfg.MongoDB.URI != "" {
		client, err := database.ConnectMongo(ctx, cfg.MongoDB.URI, cfg.MongoDB.Timeout)
		if err != nil {
			log.Printf("Warning: failed to connect to MongoDB: %v", err)
		} else {
			defer func() {
				_ = client.Disconnect(ctx)
			}()
			usersCol := client.Database(cfg.MongoDB.Database).Collection("users")
			repo := users.NewMongoUserRepository(usersCol)
			userSvc = users.NewService(repo)

			sessionsCol := client.Database(cfg.MongoDB.Database).Collection("sessions")
			srepo := sessions.NewMongoRepository(sessionsCol)
			sessionsSvc = sessions.NewService(srepo)
		}
	}

	api := r.Group("/api/v1")
	if verifier != nil {
		api.GET("/me", middleware.AuthMiddleware(verifier), func(c *gin.Context) {
			claims, _ := c.Get("claims")
			if userSvc != nil {
				if cm, ok := claims.(map[string]interface{}); ok {
					u, err := userSvc.UpsertFromClaims(c.Request.Context(), cm)
					if err == nil && u != nil {
						c.JSON(http.StatusOK, gin.H{"user": u})
						return
					}
				}
			}
			// fallback: return claims
			c.JSON(http.StatusOK, gin.H{"claims": claims})
		})
	} else {
		api.GET("/me", func(c *gin.Context) {
			c.JSON(http.StatusOK, gin.H{"message": "OIDC not configured"})
		})
	}

	// Register auth handlers if sessions/service available
	if sessionsSvc != nil && userSvc != nil {
		authHandler := handlers.NewAuthHandler(cfg, userSvc, sessionsSvc)
		authHandler.Register(api)
	}

	addr := fmt.Sprintf("%s:%s", cfg.Server.Host, cfg.Server.Port)
	log.Printf("Starting auth service on %s", addr)
	if err := r.Run(addr); err != nil {
		log.Fatalf("server failed: %v", err)
	}
}

var startTime = time.Now()
