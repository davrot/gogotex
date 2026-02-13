package handlers

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestCreateUpdateGetDocument(t *testing.T) {
	g := gin.New()
	RegisterDocumentRoutes(g)

	// CREATE
	w := httptest.NewRecorder()
	reqBody := `{"name":"test.tex","content":"hello"}`
	req := httptest.NewRequest(http.MethodPost, "/api/documents", strings.NewReader(reqBody))
	req.Header.Set("Content-Type", "application/json")
	g.ServeHTTP(w, req)
	require.Equal(t, http.StatusCreated, w.Code)
	var cr map[string]string
	err := json.Unmarshal(w.Body.Bytes(), &cr)
	require.NoError(t, err)
	id, ok := cr["id"]
	require.True(t, ok)

	// PATCH
	w = httptest.NewRecorder()
	patchBody := `{"content":"updated content"}`
	req = httptest.NewRequest(http.MethodPatch, fmt.Sprintf("/api/documents/%s", id), strings.NewReader(patchBody))
	req.Header.Set("Content-Type", "application/json")
	g.ServeHTTP(w, req)
	assert.Equal(t, http.StatusOK, w.Code)

	// GET (single)
	w = httptest.NewRecorder()
	req = httptest.NewRequest(http.MethodGet, fmt.Sprintf("/api/documents/%s", id), nil)
	g.ServeHTTP(w, req)
	assert.Equal(t, http.StatusOK, w.Code)
	var got map[string]interface{}
	err = json.Unmarshal(w.Body.Bytes(), &got)
	require.NoError(t, err)
	assert.Equal(t, "updated content", got["content"])

	// LIST
	w = httptest.NewRecorder()
	req = httptest.NewRequest(http.MethodGet, "/api/documents", nil)
	g.ServeHTTP(w, req)
	assert.Equal(t, http.StatusOK, w.Code)
	var list []map[string]interface{}
	err = json.Unmarshal(w.Body.Bytes(), &list)
	require.NoError(t, err)
	found := false
	for _, it := range list {
		if idv, ok := it["id"].(string); ok && idv == id {
			found = true
		}
	}
	assert.True(t, found, "created document should appear in list")
}
