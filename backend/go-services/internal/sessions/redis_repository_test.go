package sessions

import (
	"context"
	"testing"
	"time"

	mr "github.com/alicebob/miniredis/v2"
	"github.com/redis/go-redis/v9"
	"github.com/stretchr/testify/require"
)

func TestRedisRepository_CreateGetDelete(t *testing.T) {
	m, err := mr.Run()
	require.NoError(t, err)
	defer m.Close()

	client := redis.NewClient(&redis.Options{Addr: m.Addr()})
	repo := NewRedisRepository(client, "test:session:")

	ctx := context.Background()
	s := &Session{
		RefreshToken: "r1",
		Sub:          "sub-1",
		CreatedAt:    time.Now().UTC(),
		ExpiresAt:    time.Now().UTC().Add(5 * time.Second),
	}

	require.NoError(t, repo.Create(ctx, s))

	got, err := repo.GetByRefresh(ctx, "r1")
	require.NoError(t, err)
	require.NotNil(t, got)
	require.Equal(t, s.Sub, got.Sub)

	// test deletion
	require.NoError(t, repo.DeleteByRefresh(ctx, "r1"))
	got2, err := repo.GetByRefresh(ctx, "r1")
	require.NoError(t, err)
	require.Nil(t, got2)
}

func TestRedisRepository_TTLExpiry(t *testing.T) {
	m, err := mr.Run()
	require.NoError(t, err)
	defer m.Close()

	client := redis.NewClient(&redis.Options{Addr: m.Addr()})
	repo := NewRedisRepository(client, "test:session:")

	ctx := context.Background()
	s := &Session{
		RefreshToken: "r2",
		Sub:          "sub-2",
		CreatedAt:    time.Now().UTC(),
		ExpiresAt:    time.Now().UTC().Add(1 * time.Second),
	}

	require.NoError(t, repo.Create(ctx, s))

	// visible immediately
	got, err := repo.GetByRefresh(ctx, "r2")
	require.NoError(t, err)
	require.NotNil(t, got)

	// advance miniredis clock past TTL
	m.FastForward(2 * time.Second)

	got2, err := repo.GetByRefresh(ctx, "r2")
	require.NoError(t, err)
	require.Nil(t, got2)
}
