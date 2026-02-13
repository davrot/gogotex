package handlers

import (
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/require"
)

func TestSwaggerEndpoints(t *testing.T) {
	g := gin.New()
	RegisterSwagger(g)

	req := httptest.NewRequest("GET", "/swagger/index.html", nil)
	w := httptest.NewRecorder()
	g.ServeHTTP(w, req)
	require.Equal(t, 200, w.Code)
	require.Contains(t, w.Body.String(), "swagger-ui")

	req2 := httptest.NewRequest("GET", "/swagger/doc.json", nil)
	w2 := httptest.NewRecorder()
	g.ServeHTTP(w2, req2)
	require.Equal(t, 200, w2.Code)
	require.Contains(t, w2.Body.String(), "openapi")
	// ensure auth endpoints are present and use correct paths
	require.Contains(t, w2.Body.String(), "/auth/login")
	require.Contains(t, w2.Body.String(), "/auth/refresh")
	require.Contains(t, w2.Body.String(), "/auth/logout")
}
