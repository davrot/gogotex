package main

import (
	"fmt"
	"context"
	"net/http"
	"time"
	"github.com/gogotex/gogotex/backend/go-services/pkg/logger"

	"github.com/gin-gonic/gin"
	"github.com/gogotex/gogotex/backend/go-services/internal/config"
	"github.com/gogotex/gogotex/backend/go-services/internal/oidc"
	"github.com/gogotex/gogotex/backend/go-services/pkg/metrics"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"strings"
	"os"
	"go.mongodb.org/mongo-driver/mongo"
	"github.com/gogotex/gogotex/backend/go-services/internal/database"
	"github.com/gogotex/gogotex/backend/go-services/internal/sessions"
	"github.com/gogotex/gogotex/backend/go-services/internal/users"
	"github.com/gogotex/gogotex/backend/go-services/handlers"
	"github.com/gogotex/gogotex/backend/go-services/pkg/middleware"
	"github.com/redis/go-redis/v9"

)

var startTime = time.Now()

func main() {
	// initialize logging (can be controlled with LOG_LEVEL env: debug|info|warn|error|fatal)
	logger.Init(os.Getenv("LOG_LEVEL"))
	// earliest always-visible marker
	fmt.Println("MAIN: after logger.Init")
	logger.Debugf("startup: LOG_LEVEL=%s", logger.LevelString())

	cfg, err := config.LoadConfig()
	if err != nil {
		logger.Fatalf("failed to load config: %v", err)
	}
	fmt.Println("MAIN: config loaded")
	logger.Infof("config loaded: keycloak=%v mongo=%v redis=%v", cfg.Keycloak.URL != "", cfg.MongoDB.URI != "", cfg.Redis.Host != "")

	r := gin.New()
logger.Infof("MAIN checkpoint: after gin.New()")

	// Lightweight CORS middleware for dev/test: set common headers and respond to OPTIONS.
	// (Keep this intentionally simple — production should use a stricter policy.)
	r.Use(func(c *gin.Context) {
		c.Writer.Header().Set("Access-Control-Allow-Origin", "*")
		c.Writer.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
		c.Writer.Header().Set("Access-Control-Allow-Headers", "Origin, Content-Type, Accept, Authorization")
		c.Writer.Header().Set("Access-Control-Expose-Headers", "Content-Length")
		if c.Request.Method == "OPTIONS" {
			c.AbortWithStatus(200)
			return
		}
		c.Next()
	})

	// shared runtime vars used by handlers/readiness
	var verifier middleware.Verifier
	var userSvc *users.Service
	var sessionsSvc *sessions.Service

// Global middlewares: logging + recovery
r.Use(gin.Logger(), gin.Recovery())

// Connect to Redis early so the rate-limiter can use it when configured
logger.Infof("MAIN checkpoint: before Redis check")
var importedRedis *redis.Client
logger.Infof("MAIN: declared importedRedis variable (nil)")
if cfg.Redis.Host != "" {
	logger.Infof("MAIN: entering Redis.Host block (host=%s)", cfg.Redis.Host)
	// create Redis client
	importedRedis = redis.NewClient(&redis.Options{Addr: cfg.Redis.Host + ":" + cfg.Redis.Port, Password: cfg.Redis.Password})

	// validate connection
	if err := importedRedis.Ping(context.Background()).Err(); err == nil {
		logger.Infof("MAIN: importedRedis ping succeeded")
		// expose Redis client for blacklist checks (session wiring happens later)
		sessions.SetBlacklistClient(importedRedis)
		logger.Infof("Connected to Redis (early) for optional features: %s:%s", cfg.Redis.Host, cfg.Redis.Port)
	} else {
		logger.Warnf("MAIN: importedRedis ping failed: %v", err)
		logger.Warnf("failed to connect to Redis early (%s:%s): %v", cfg.Redis.Host, cfg.Redis.Port, err)
	}
	// Optional global rate limiter (per-user when authenticated, otherwise per-IP)
	if cfg.RateLimit.Enabled {
		logger.Infof("MAIN: rate limiter enabled")
		// use Redis-backed limiter when configured and Redis client is available
	if cfg.RateLimit.UseRedis && importedRedis != nil {
		win := time.Duration(cfg.RateLimit.WindowSeconds) * time.Second
		r.Use(middleware.RedisRateLimitMiddleware(importedRedis, cfg.RateLimit.RPS, cfg.RateLimit.Burst, win))
	} else {
		r.Use(middleware.RateLimitMiddleware(cfg.RateLimit.RPS, cfg.RateLimit.Burst))
	}
}

// Basic health endpoint
logger.Infof("MAIN checkpoint: after Redis / rate limiter check")
fmt.Println("MAIN: after rate limiter / redis check")
r.GET("/health", func(c *gin.Context) {
	c.String(http.StatusOK, "healthy")
})

// readiness endpoint — return 200 only when critical dependencies are available
r.GET("/ready", func(c *gin.Context) {
	ready := true
	deps := map[string]bool{}

	// storage readiness: service is ready when a session store is configured.
	// (Redis-backed sessions are sufficient for storage; MongoDB provides user
	// service when available.)
	if sessionsSvc == nil {
		deps["storage"] = false
		ready = false
	} else {
		deps["storage"] = true
		// indicate whether user service is available (not required for storage)
		deps["users"] = (userSvc != nil)
	}

	// OIDC readiness: if Keycloak URL was configured we expect a verifier (or ALLOW_INSECURE_TOKEN)
	if cfg.Keycloak.URL != "" {
		if verifier == nil {
			deps["oidc"] = false
			ready = false
		} else {
			deps["oidc"] = true
		}
	} else {
		// not configured -> consider OK
		deps["oidc"] = true
	}

	// Redis readiness when used for rate-limiter or sessions
	if cfg.Redis.Host != "" && cfg.RateLimit.UseRedis {
		deps["redis"] = importedRedis != nil
		if !deps["redis"] {
			ready = false
		}
	} else {
		deps["redis"] = true
	}

	if !ready {
		c.JSON(http.StatusServiceUnavailable, gin.H{"status": "not_ready", "deps": deps, "uptime": fmt.Sprintf("%s", time.Since(startTime))})
		return
	}

	c.JSON(http.StatusOK, gin.H{"status": "ready", "deps": deps, "uptime": fmt.Sprintf("%s", time.Since(startTime))})
})

// Keycloak OIDC verifier and protected sample endpoint
ctx := context.Background()
if cfg.Keycloak.URL != "" && cfg.Keycloak.ClientID != "" && cfg.Keycloak.Realm != "" {
	issuer := strings.TrimRight(cfg.Keycloak.URL, "/") + "/realms/" + cfg.Keycloak.Realm
	ver, err := oidc.NewVerifier(ctx, issuer, cfg.Keycloak.ClientID)
	if err != nil {
			logger.Warnf("failed to initialize OIDC verifier: %v", err)
		} else {
			verifier = ver
		}
	} else if cfg.Keycloak.URL != "" && cfg.Keycloak.ClientID != "" {
		// Fallback: try URL as issuer (older deployments may expose realm path in URL)
		ver, err := oidc.NewVerifier(ctx, cfg.Keycloak.URL, cfg.Keycloak.ClientID)
		if err != nil {
			logger.Warnf("failed to initialize OIDC verifier (fallback): %v", err)
		} else {
			verifier = ver
		}
	}

// Optional insecure verifier for integration tests: parse token claims without signature verification
logger.Infof("MAIN checkpoint: before insecure OIDC verifier check")
if verifier == nil {
	val := strings.ToLower(strings.TrimSpace(os.Getenv("ALLOW_INSECURE_TOKEN")))
	logger.Debugf("ALLOW_INSECURE_TOKEN=%q", val)
	if val == "true" {
		logger.Warn("enabling insecure OIDC verifier (integration mode)")
	}
}
logger.Infof("MAIN checkpoint: after insecure OIDC verifier check")

// Connect to MongoDB and initialize user and session services

// Prefer Redis-based sessions when configured (fast, in-memory)
if importedRedis != nil {
	// sessions stored in Redis
	srepo := sessions.NewRedisRepository(importedRedis, "session:")
	sessionsSvc = sessions.NewService(srepo)
	logger.Infof("Using Redis for session storage (early connection)")
}

// MongoDB-backed services (users + sessions)
// Attempt Mongo connection when configured. If Redis provided sessionsSvc already,
// still create the user service from Mongo if available (fixes missing auth handlers
// when Redis is used for sessions).
if cfg.MongoDB.URI != "" {
	// Retry/backoff when connecting to MongoDB to tolerate startup races
	const maxAttempts = 5
	backoff := time.Second
	var client *mongo.Client
	var errConn error
	for attempt := 1; attempt <= maxAttempts; attempt++ {
		client, errConn = database.ConnectMongo(ctx, cfg.MongoDB.URI, cfg.MongoDB.Timeout)
		if errConn == nil {
			break
		}
		logger.Warnf("attempt %d/%d: failed to connect to MongoDB: %v", attempt, maxAttempts, errConn)
		if attempt < maxAttempts {
			time.Sleep(backoff)
			backoff *= 2
		}
	}
	if errConn != nil {
		logger.Warnf("could not connect to MongoDB after %d attempts: %v", maxAttempts, errConn)
	} else {
		defer func() { _ = client.Disconnect(ctx) }()
		usersCol := client.Database(cfg.MongoDB.Database).Collection("users")
		repo := users.NewMongoUserRepository(usersCol)
		userSvc = users.NewService(repo)

		// only create Mongo-backed session repo when a session service isn't already set
		if sessionsSvc == nil {
			sessionsCol := client.Database(cfg.MongoDB.Database).Collection("sessions")
			srepo := sessions.NewMongoRepository(sessionsCol)
			sessionsSvc = sessions.NewService(srepo)
		}
	}
}

// Register auth handlers if services are available
logger.Infof("MAIN checkpoint: before registering handlers")
if userSvc != nil && sessionsSvc != nil {
	h := handlers.NewAuthHandler(cfg, userSvc, sessionsSvc)
	h.Register(r.Group("/"))
} else {
	logger.Warnf("auth handlers not registered because user/sessions services are unavailable")
}// Register minimal Swagger UI + JSON for API documentation (Phase-02 requirement)
handlers.RegisterSwagger(r)// Minimal documents API (Phase‑03): support editor create/attach + simple draft PATCH
handlers.RegisterDocumentRoutes(r)logger.Infof("MAIN checkpoint: after registering handlers")
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

// Expose Prometheus metrics
metrics.RegisterCollectors(prometheus.DefaultRegisterer)
r.GET("/metrics", gin.WrapH(promhttp.Handler()))

addr := fmt.Sprintf("%s:%s", cfg.Server.Host, cfg.Server.Port)
// brief runtime configuration summary to help with debugging early exits
logger.Infof("Config summary: keycloak=%v mongo=%v redis=%v jwt_secret_set=%v", cfg.Keycloak.URL != "", cfg.MongoDB.URI != "", cfg.Redis.Host != "", cfg.JWT.Secret != "")
logger.Debugf("services: user=%v sessions=%v verifier=%v", userSvc != nil, sessionsSvc != nil, verifier != nil)
fmt.Println("MAIN: before Starting auth service on", addr)
	logger.Infof("Starting auth service on %s", addr)
// run server in goroutine and keep process alive — defensive: prevents
// the container from exiting silently if r.Run ever returns.
go func() {
	if err := r.Run(addr); err != nil {
		logger.Fatalf("server failed: %v", err)
	}
}()
logger.Infof("entering select{} to keep process alive")
select {}
}
}

