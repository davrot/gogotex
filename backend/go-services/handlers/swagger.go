package handlers

import (
	"net/http"

	"github.com/gin-gonic/gin"
)

// RegisterSwagger registers minimal Swagger/OpenAPI endpoints for the auth service.
// - GET /swagger/index.html  -> a small HTML page that loads the OpenAPI JSON
// - GET /swagger/doc.json    -> machine-readable OpenAPI JSON
func RegisterSwagger(rg *gin.Engine) {
	rg.GET("/swagger/index.html", func(c *gin.Context) {
		c.Header("Content-Type", "text/html; charset=utf-8")
		c.String(http.StatusOK, swaggerHTML)
	})

	rg.GET("/swagger/doc.json", func(c *gin.Context) {
		c.JSON(http.StatusOK, swaggerJSON)
	})
}

const swaggerHTML = `<!doctype html>
<html>
  <head>
    <meta charset="utf-8" />
    <title>gogotex-auth — Swagger</title>
    <link rel="stylesheet" href="https://unpkg.com/swagger-ui-dist@4/swagger-ui.css" />
  </head>
  <body>
    <div id="swagger-ui"></div>
    <script src="https://unpkg.com/swagger-ui-dist@4/swagger-ui-bundle.js"></script>
    <script>
      window.ui = SwaggerUIBundle({
        url: '/swagger/doc.json',
        dom_id: '#swagger-ui',
      })
    </script>
  </body>
</html>`

// Minimal OpenAPI document describing important auth endpoints used in Phase‑02.
const swaggerJSON = `{
  "openapi": "3.0.0",
  "info": { "title": "gogotex-auth", "version": "v0.1.0" },
  "paths": {
    "/auth/login": {
      "post": {
        "summary": "Exchange authorization code / login",
        "requestBody": { "content": { "application/json": { "schema": {"type":"object","properties":{"mode":{"type":"string"},"username":{"type":"string"},"password":{"type":"string"},"code":{"type":"string"},"redirect_uri":{"type":"string"}}}}}},
        "responses": { "200": { "description": "tokens returned" } }
      }
    },
    "/auth/refresh": {
      "post": { "summary": "Refresh access token", "requestBody": { "content": { "application/json": { "schema": {"type":"object","properties":{"refresh_token":{"type":"string"}}}}}}, "responses": { "200": { "description": "new access token" }, "401": { "description": "invalid refresh" } } }
    },
    "/auth/logout": {
      "post": { "summary": "Logout and invalidate refresh token", "requestBody": { "content": { "application/json": { "schema": {"type":"object","properties":{"refresh_token":{"type":"string"}}}}}}, "responses": { "200": { "description": "logged out" } } }
    },
    "/api/v1/me": {
      "get": { "summary": "Get user info", "responses": { "200": { "description": "user or claims" } } }
    },
    "/health": { "get": { "summary": "Liveness check", "responses": { "200": { "description": "healthy" } } } },
    "/ready": { "get": { "summary": "Readiness check", "responses": { "200": { "description": "ready" }, "503": { "description": "not ready" } } } }
  }
}`
