package sessions

import (
	"context"
	"testing"
	"time"

	mr "github.com/alicebob/miniredis/v2"
	"github.com/redis/go-redis/v9"
	"github.com/stretchr/testify/require"
)

func TestBlacklistAccessToken_IsAccessTokenBlacklisted(t *testing.T) {
	m, err := mr.Run()
	require.NoError(t, err)
	defer m.Close()

	client := redis.NewClient(&redis.Options{Addr: m.Addr()})
	SetBlacklistClient(client)

	ctx := context.Background()
	token := "access-token-1"
	// blacklist for 2 seconds
	require.NoError(t, BlacklistAccessToken(ctx, token, 2*time.Second))

	ok, err := IsAccessTokenBlacklisted(ctx, token)
	require.NoError(t, err)
	require.True(t, ok)

	// advance past TTL
	m.FastForward(3 * time.Second)

	ok2, err := IsAccessTokenBlacklisted(ctx, token)
	require.NoError(t, err)
	require.False(t, ok2)
}

// Ensure blacklist functions are no-ops when no Redis client configured
func TestBlacklist_NoClient_Noop(t *testing.T) {
	// ensure no client set
	SetBlacklistClient(nil)
	ctx := context.Background()
	token := "no-client-token"
	require.NoError(t, BlacklistAccessToken(ctx, token, 1*time.Second))
	ok, err := IsAccessTokenBlacklisted(ctx, token)
	require.NoError(t, err)
	require.False(t, ok)
}
