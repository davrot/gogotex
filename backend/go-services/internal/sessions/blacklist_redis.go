package sessions

import (
	"context"
	"time"

	"github.com/redis/go-redis/v9"
)

// package-level Redis client used for token blacklist (optional)
var blacklistClient *redis.Client

// SetBlacklistClient configures the Redis client used for blacklist operations.
// Safe to call with nil to disable blacklist features.
func SetBlacklistClient(c *redis.Client) {
	blacklistClient = c
}

// BlacklistAccessToken stores the given token in Redis blacklist with TTL.
// If no Redis client is configured, this is a no-op and returns nil.
func BlacklistAccessToken(ctx context.Context, token string, ttl time.Duration) error {
	if blacklistClient == nil {
		return nil
	}
	key := "blacklist:access:" + token
	return blacklistClient.Set(ctx, key, "1", ttl).Err()
}

// IsAccessTokenBlacklisted returns true when the token exists in the Redis blacklist.
// If no Redis client is configured, returns (false, nil).
func IsAccessTokenBlacklisted(ctx context.Context, token string) (bool, error) {
	if blacklistClient == nil {
		return false, nil
	}
	key := "blacklist:access:" + token
	exists, err := blacklistClient.Exists(ctx, key).Result()
	if err != nil {
		return false, err
	}
	return exists > 0, nil
}
