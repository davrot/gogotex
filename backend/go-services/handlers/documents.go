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

// CompileJob represents a short-lived compile job for Phase‑03 prototyping.
type CompileJob struct {
	JobID     string    `json:"jobId"`
	DocID     string    `json:"docId"`
	Status    string    `json:"status"` // compiling|ready|canceled|error
	Logs      string    `json:"logs"`
	CreatedAt time.Time `json:"createdAt"`
}

var (
	documentsMu    sync.RWMutex
	documentsStore = map[string]*Document{}

	// jobs map for compile stubs
	compileJobsMu sync.RWMutex
	compileJobs   = map[string]*CompileJob{}
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

	// compile & preview (Phase‑03 stub)
	r.POST("/api/documents/:id/compile", CompileDocument)
	r.GET("/api/documents/:id/compile/logs", GetCompileLogs)
	r.POST("/api/documents/:id/compile/cancel", CancelCompile)
	r.GET("/api/documents/:id/preview", PreviewDocument)
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

// CompileDocument is a Phase‑03 stub that 'queues' a compile job and returns a preview URL.
// It simulates an async compile by creating an in-memory job and completing it shortly after.
func CompileDocument(c *gin.Context) {
	id := c.Param("id")
	documentsMu.RLock()
	d, ok := documentsStore[id]
	documentsMu.RUnlock()
	if !ok {
		c.JSON(http.StatusNotFound, gin.H{"error": "not found"})
		return
	}
	jobID := fmt.Sprintf("job_%d", time.Now().UnixNano())
	job := &CompileJob{JobID: jobID, DocID: id, Status: "compiling", Logs: "Started compile...\n", CreatedAt: time.Now()}
	compileJobsMu.Lock()
	compileJobs[jobID] = job
	compileJobsMu.Unlock()

	// Simulate async compile completion after a short delay (keeps tests fast)
	go func(j *CompileJob) {
		time.Sleep(150 * time.Millisecond)
		compileJobsMu.Lock()
		defer compileJobsMu.Unlock()
		if cur, ok := compileJobs[j.JobID]; ok {
			if cur.Status != "canceled" {
				cur.Status = "ready"
				cur.Logs += "Compiled successfully\n"
			}
		}
	}(job)

	preview := fmt.Sprintf("/api/documents/%s/preview", id)
	c.JSON(http.StatusOK, gin.H{"jobId": jobID, "status": job.Status, "previewUrl": preview, "name": d.Name})
}

// PreviewDocument returns a lightweight HTML preview (stub) for the given document.
func PreviewDocument(c *gin.Context) {
	id := c.Param("id")
	documentsMu.RLock()
	d, ok := documentsStore[id]
	documentsMu.RUnlock()
	if !ok {
		c.JSON(http.StatusNotFound, gin.H{"error": "not found"})
		return
	}
	html := fmt.Sprintf(`<html><head><meta charset="utf-8"><title>Preview: %s</title></head><body><h2>PDF preview (stub)</h2><p>Document: <strong>%s</strong> (%s)</p><p>This is a placeholder preview for Phase‑03.</p></body></html>`, d.Name, d.Name, d.ID)
	c.Header("Content-Type", "text/html; charset=utf-8")
	c.String(http.StatusOK, html)
}

// GetCompileLogs returns the current compile job status and logs for a document (Phase‑03).
func GetCompileLogs(c *gin.Context) {
	id := c.Param("id")
	compileJobsMu.RLock()
	defer compileJobsMu.RUnlock()
	for _, j := range compileJobs {
		if j.DocID == id {
			c.JSON(http.StatusOK, gin.H{"jobId": j.JobID, "status": j.Status, "logs": j.Logs, "previewUrl": fmt.Sprintf("/api/documents/%s/preview", id)})
			return
		}
	}
	c.JSON(http.StatusNotFound, gin.H{"error": "no compile job"})
}

// CancelCompile attempts to cancel a running compile job for a document.
func CancelCompile(c *gin.Context) {
	id := c.Param("id")
	compileJobsMu.Lock()
	defer compileJobsMu.Unlock()
	for _, j := range compileJobs {
		if j.DocID == id && j.Status == "compiling" {
			j.Status = "canceled"
			j.Logs += "Canceled by user\n"
			c.JSON(http.StatusOK, gin.H{"jobId": j.JobID, "status": j.Status})
			return
		}
	}
	c.JSON(http.StatusNotFound, gin.H{"error": "no running compile job"})
}
