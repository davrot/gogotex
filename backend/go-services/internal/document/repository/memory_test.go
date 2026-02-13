package repository

import (
	"testing"

	"github.com/gogotex/gogotex/backend/go-services/internal/document"
	"github.com/stretchr/testify/require"
)

func TestMemoryRepoCRUD(t *testing.T) {
	r := NewMemoryRepo()
	d := &document.Document{Name: "t.tex", Content: "hello"}
	id, err := r.Create(d)
	require.NoError(t, err)
	require.NotEmpty(t, id)

	got, err := r.Get(id)
	require.NoError(t, err)
	require.Equal(t, "hello", got.Content)

	list, err := r.List()
	require.NoError(t, err)
	require.GreaterOrEqual(t, len(list), 1)

	err = r.Update(id, "new", nil)
	require.NoError(t, err)
	got2, err := r.Get(id)
	require.NoError(t, err)
	require.Equal(t, "new", got2.Content)

	err = r.Delete(id)
	require.NoError(t, err)
	_, err = r.Get(id)
	require.Error(t, err)
}
