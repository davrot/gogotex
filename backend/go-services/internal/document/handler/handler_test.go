package handler

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/gogotex/gogotex/backend/go-services/internal/document/service"
	"github.com/stretchr/testify/require"
)

func TestDocumentHandler_CRUD(t *testing.T) {
	g := gin.New()
	svc := service.NewMemoryService()
	RegisterDocumentRoutes(g, svc)

	// create
	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/api/documents", strings.NewReader(`{"name":"a.tex","content":"hi"}`))
	req.Header.Set("Content-Type", "application/json")
	g.ServeHTTP(w, req)
	require.Equal(t, http.StatusCreated, w.Code)
	var cr map[string]string
	require.NoError(t, json.Unmarshal(w.Body.Bytes(), &cr))
	id := cr["id"]
	require.NotEmpty(t, id)

	// get
	w = httptest.NewRecorder()
	req = httptest.NewRequest(http.MethodGet, "/api/documents/"+id, nil)
	g.ServeHTTP(w, req)
	require.Equal(t, http.StatusOK, w.Code)

	// list
	w = httptest.NewRecorder()
	req = httptest.NewRequest(http.MethodGet, "/api/documents", nil)
	g.ServeHTTP(w, req)
	require.Equal(t, http.StatusOK, w.Code)

	// delete
	w = httptest.NewRecorder()
	req = httptest.NewRequest(http.MethodDelete, "/api/documents/"+id, nil)
	g.ServeHTTP(w, req)
	require.Equal(t, http.StatusNoContent, w.Code)
}
