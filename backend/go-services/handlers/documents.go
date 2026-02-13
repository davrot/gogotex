package handlers

import (
	"fmt"
	"net/http"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
)

// Document is a lightweight in-memory document model used for Phase-03 UI flows.
// This is intentionally simple (in-memory) so the frontend editor features can
// be exercised without a full document microservice. In Phase-05 this will be
// replaced by a proper `go-document` implementation backed by Mongo.
type Document struct {
	ID        string    `json:"id"`
	Name      string    `json:"name"`
	Content   string    `json:"content,omitempty"`
	CreatedAt time.Time `json:"createdAt"`
	UpdatedAt time.Time `json:"updatedAt"`
}

var (
	documentsMu    sync.RWMutex
	documentsStore = map[string]*Document{}
)

// RegisterDocumentRoutes registers minimal document endpoints used by the
// Phase-03 frontend prototype (create, get, update).
func RegisterDocumentRoutes(r *gin.Engine) {
	// List documents (lightweight)
	r.GET("/api/documents", ListDocuments)
	r.POST("/api/documents", CreateDocument)
	r.GET("/api/documents/:id", GetDocument)
	r.PATCH("/api/documents/:id", UpdateDocument)
	r.DELETE("/api/documents/:id", DeleteDocument)
}

// ListDocuments returns a short listing of available documents (id + name)
func ListDocuments(c *gin.Context) {
	documentsMu.RLock()
	defer documentsMu.RUnlock()
	out := make([]map[string]string, 0, len(documentsStore))
	for id, d := range documentsStore {
		out = append(out, map[string]string{"id": id, "name": d.Name})
	}
	c.JSON(http.StatusOK, out)
}

// CreateDocument accepts { name, content } and returns { id, name }
func CreateDocument(c *gin.Context) {
	var req struct {
		Name    string `json:"name"`
		Content string `json:"content"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	if req.Name == "" {
		req.Name = "untitled.tex"
	}
	id := fmt.Sprintf("doc_%d", time.Now().UnixNano())
	d := &Document{ID: id, Name: req.Name, Content: req.Content, CreatedAt: time.Now(), UpdatedAt: time.Now()}
	documentsMu.Lock()
	documentsStore[id] = d
	documentsMu.Unlock()
	c.JSON(http.StatusCreated, gin.H{"id": d.ID, "name": d.Name})
}

// UpdateDocument updates the content (and optionally name) of an existing document
func UpdateDocument(c *gin.Context) {
	id := c.Param("id")
	var req struct {
		Name    *string `json:"name,omitempty"`
		Content string  `json:"content"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	documentsMu.Lock()
	defer documentsMu.Unlock()
	d, ok := documentsStore[id]
	if !ok {
		c.JSON(http.StatusNotFound, gin.H{"error": "not found"})
		return
	}
	if req.Name != nil {
		d.Name = *req.Name
	}
	d.Content = req.Content
	d.UpdatedAt = time.Now()
	c.JSON(http.StatusOK, gin.H{"id": d.ID, "name": d.Name})
}

// GetDocument returns the document including its content
func GetDocument(c *gin.Context) {
	id := c.Param("id")
	documentsMu.RLock()
	defer documentsMu.RUnlock()
	d, ok := documentsStore[id]
	if !ok {
		c.JSON(http.StatusNotFound, gin.H{"error": "not found"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"id": d.ID, "name": d.Name, "content": d.Content, "createdAt": d.CreatedAt, "updatedAt": d.UpdatedAt})
}

// DeleteDocument removes a document from the in-memory store
func DeleteDocument(c *gin.Context) {
	id := c.Param("id")
	documentsMu.Lock()
	defer documentsMu.Unlock()
	if _, ok := documentsStore[id]; !ok {
		c.JSON(http.StatusNotFound, gin.H{"error": "not found"})
		return
	}
	delete(documentsStore, id)
	c.Status(http.StatusNoContent)
}
