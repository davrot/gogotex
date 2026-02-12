package sessions

import (
	"context"
	"encoding/json"
	"time"

	"github.com/redis/go-redis/v9"
)

// RedisRepository implements Repository using Redis as the backing store.
// Sessions are stored as JSON under key: "session:<refreshToken>" with TTL = expiresAt - now
type RedisRepository struct {
	client *redis.Client
	prefix string
}

// NewRedisRepository creates a Redis-based session repository. Prefix may be empty.
func NewRedisRepository(client *redis.Client, prefix string) *RedisRepository {
	if prefix == "" {
		prefix = "session:"
	}
	return &RedisRepository{client: client, prefix: prefix}
}

func (r *RedisRepository) key(refresh string) string {
	return r.prefix + refresh
}

func (r *RedisRepository) Create(ctx context.Context, s *Session) error {
	b, err := json.Marshal(s)
	if err != nil {
		return err
	}
	exp := time.Until(s.ExpiresAt)
	if exp <= 0 {
		// ensure a minimal TTL so Redis won't store expired sessions
		exp = time.Second
	}
	return r.client.Set(ctx, r.key(s.RefreshToken), b, exp).Err()
}

func (r *RedisRepository) GetByRefresh(ctx context.Context, refresh string) (*Session, error) {
	b, err := r.client.Get(ctx, r.key(refresh)).Bytes()
	if err != nil {
		if err == redis.Nil {
			return nil, nil
		}
		return nil, err
	}
	var s Session
	if err := json.Unmarshal(b, &s); err != nil {
		return nil, err
	}
	// If session expired from perspective of stored value, treat as missing
	if time.Now().UTC().After(s.ExpiresAt) {
		_ = r.client.Del(ctx, r.key(refresh)).Err()
		return nil, nil
	}
	return &s, nil
}

func (r *RedisRepository) DeleteByRefresh(ctx context.Context, refresh string) error {
	return r.client.Del(ctx, r.key(refresh)).Err()
}
