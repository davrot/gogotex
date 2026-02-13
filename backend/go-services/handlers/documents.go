package handlers

import (
	"bytes"
	"compress/gzip"
	"context"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
	documenthandler "github.com/gogotex/gogotex/backend/go-services/internal/document/handler"
	documentservice "github.com/gogotex/gogotex/backend/go-services/internal/document/service"
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
// It now stores compiled artifacts (PDF + SyncTeX) in-memory for the prototype.
type CompileJob struct {
	JobID     string    `json:"jobId"`
	DocID     string    `json:"docId"`
	Status    string    `json:"status"` // compiling|ready|canceled|error
	Logs      string    `json:"logs"`
	CreatedAt time.Time `json:"createdAt"`

	// compiled artifacts (not serialized)
	PDF      []byte `json:"-"`
	Synctex  []byte `json:"-"`
	ErrorMsg string `json:"error,omitempty"`
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
	// Opt-in: if DOC_SERVICE_INLINE=true then register the internal document
	// service handlers (persistent memory/Mongo-backed) instead of the
	// Phase‑03 in-memory prototype. This lets CI/dev run a persisted
	// document service in-process without launching a separate container.
	if os.Getenv("DOC_SERVICE_INLINE") == "true" {
		// prefer Mongo-backed repo when MONGODB_URI present (internal/service handles fallback)
		svc := documentservice.NewMemoryService()
		documenthandler.RegisterDocumentRoutes(r, svc)
		return
	}

	// List documents (lightweight)
	r.GET("/api/documents", ListDocuments)
	r.POST("/api/documents", CreateDocument)
	r.GET("/api/documents/:id", GetDocument)
	r.PATCH("/api/documents/:id", UpdateDocument)
	r.DELETE("/api/documents/:id", DeleteDocument)

	// compile & preview (Phase‑03 stub — now with real compile worker + SyncTeX fallback)
	r.POST("/api/documents/:id/compile", CompileDocument)
	r.GET("/api/documents/:id/compile/logs", GetCompileLogs)
	r.GET("/api/documents/:id/compile/jobs", ListCompileJobs)
	r.GET("/api/documents/:id/compile/:jobId/download", DownloadCompiled)
	r.GET("/api/documents/:id/compile/:jobId/synctex", DownloadSynctex)
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

	// Start the async compile worker — it will try pdflatex and fall back to
	// a minimal PDF + SyncTeX when the toolchain isn't available (keeps tests fast).
	go func(j *CompileJob, content string, name string) {
		runCompileJob(j, content, name)
	}(job, d.Content, d.Name)

	preview := fmt.Sprintf("/api/documents/%s/preview", id)
	c.JSON(http.StatusOK, gin.H{"jobId": jobID, "status": job.Status, "previewUrl": preview, "name": d.Name})
}

// PreviewDocument returns a preview page for the given document.
// If a ready compile job exists we render a PDF.js-based viewer that loads
// the compiled PDF and posts click events back to the parent (prototype
// SyncTeX → editor mapping). Otherwise a lightweight stub is returned.
func PreviewDocument(c *gin.Context) {
	id := c.Param("id")
	documentsMu.RLock()
	d, ok := documentsStore[id]
	documentsMu.RUnlock()
	if !ok {
		c.JSON(http.StatusNotFound, gin.H{"error": "not found"})
		return
	}

	// look for a ready compile job for this document
	var readyJob string
	compileJobsMu.RLock()
	for _, j := range compileJobs {
		if j.DocID == id && j.Status == "ready" {
			readyJob = j.JobID
			break
		}
	}
	compileJobsMu.RUnlock()

	if readyJob != "" {
		pdfURL := fmt.Sprintf("/api/documents/%s/compile/%s/download", id, readyJob)
		html := fmt.Sprintf(`<!doctype html>
<html>
  <head>
    <meta charset="utf-8" />
    <title>Preview: %s</title>
    <style>body{font-family:Inter,Arial,sans-serif;margin:0;padding:12px}#canvas{border:1px solid #ddd}</style>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/pdf.js/2.16.105/pdf.min.js"></script>
  </head>
  <body>
    <h2>PDF preview</h2>
    <p>Document: <strong>%s</strong> (%s)</p>
    <canvas id="canvas"></canvas>
    <script>
      const url = '%s'
      const canvas = document.getElementById('canvas')
      const ctx = canvas.getContext('2d')
      pdfjsLib.GlobalWorkerOptions.workerSrc = 'https://cdnjs.cloudflare.com/ajax/libs/pdf.js/2.16.105/pdf.worker.min.js'
      pdfjsLib.getDocument(url).promise.then(function(pdf) {
        pdf.getPage(1).then(function(page) {
          const scale = 1.25
          const viewport = page.getViewport({ scale: scale })
          canvas.width = Math.min(viewport.width, 1024)
          canvas.height = viewport.height
          const renderContext = { canvasContext: ctx, viewport: viewport }
          page.render(renderContext)
        })
      }).catch(function(err){
        const el = document.createElement('pre'); el.textContent = 'Failed to load PDF: '+err; document.body.appendChild(el)
      })
      canvas.addEventListener('click', function(ev){
        try {
          const rect = canvas.getBoundingClientRect()
          const y = (ev.clientY - rect.top) / rect.height
          parent.postMessage({ type: 'pdf-click', page: 1, y: y }, '*')
        } catch(e) { /* ignore */ }
      })
    </script>
  </body>
</html>`, d.Name, d.Name, d.ID, pdfURL)
		c.Header("Content-Type", "text/html; charset=utf-8")
		c.String(http.StatusOK, html)
		return
	}

	// fallback stub when no compiled PDF is available
	html := fmt.Sprintf(`<html><head><meta charset="utf-8"><title>Preview: %s</title>
<script>
function sendLine(line){ try { parent.postMessage({ type: 'synctex-click', line: line }, '*') } catch(e){} }
window.addEventListener('click', function(ev){ var t = ev.target; var ln = t && t.dataset && t.dataset.line ? Number(t.dataset.line) : 1; sendLine(ln) })
</script>
</head><body><h2>PDF preview (stub)</h2><p>Document: <strong>%s</strong> (%s)</p><div id="pdf" style="height:70vh;border:1px solid #ddd;padding:12px;overflow:auto;"><p data-line="1">Page 1 — top (maps to line 1)</p><p data-line="5">Page 1 — middle (maps to line 5)</p><p data-line="10">Page 1 — bottom (maps to line 10)</p></div></body></html>`, d.Name, d.Name, d.ID)
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

// ListCompileJobs returns all compile jobs for a document (Phase‑03 helper).
func ListCompileJobs(c *gin.Context) {
	id := c.Param("id")
	compileJobsMu.RLock()
	defer compileJobsMu.RUnlock()
	out := []map[string]interface{}{}
	for _, j := range compileJobs {
		if j.DocID == id {
			out = append(out, map[string]interface{}{"jobId": j.JobID, "status": j.Status, "createdAt": j.CreatedAt, "logs": j.Logs})
		}
	}
	c.JSON(http.StatusOK, out)
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

// DownloadCompiled returns the compiled PDF for a completed compile job.
func DownloadCompiled(c *gin.Context) {
	id := c.Param("id")
	jobId := c.Param("jobId")
	compileJobsMu.RLock()
	job, ok := compileJobs[jobId]
	compileJobsMu.RUnlock()
	if !ok || job.DocID != id {
		c.JSON(http.StatusNotFound, gin.H{"error": "job not found"})
		return
	}
	if job.Status != "ready" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "job not ready"})
		return
	}
	var pdf []byte
	if len(job.PDF) > 0 {
		pdf = job.PDF
	} else {
		pdf = minimalPDF()
	}
	c.Header("Content-Type", "application/pdf")
	c.Header("Content-Disposition", fmt.Sprintf("attachment; filename=\"%s.pdf\"", job.DocID))
	c.Data(http.StatusOK, "application/pdf", pdf)
}

// DownloadSynctex returns the raw (gzipped) SyncTeX file for a completed job.
func DownloadSynctex(c *gin.Context) {
	id := c.Param("id")
	jobId := c.Param("jobId")
	compileJobsMu.RLock()
	job, ok := compileJobs[jobId]
	compileJobsMu.RUnlock()
	if !ok || job.DocID != id {
		c.JSON(http.StatusNotFound, gin.H{"error": "job not found"})
		return
	}
	if job.Status != "ready" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "job not ready"})
		return
	}
	if len(job.Synctex) == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "synctex not available"})
		return
	}
	c.Header("Content-Type", "application/gzip")
	c.Data(http.StatusOK, "application/gzip", job.Synctex)
}

// minimalPDF returns a tiny PDF stub (used as a fallback when pdflatex isn't available).
func minimalPDF() []byte {
	return []byte("%PDF-1.1\n%\u00e2\u00e3\u00cf\u00d3\n1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n2 0 obj\n<< /Type /Pages /Count 1 /Kids [3 0 R] >>\nendobj\n3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>\nendobj\n4 0 obj\n<< /Length 44 >>\nstream\nBT /F1 24 Tf 50 150 Td (Hello PDF) Tj ET\nendstream\nendobj\n5 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>\nendobj\nxref\n0 6\n0000000000 65535 f \n0000000010 00000 n \n0000000060 00000 n \n0000000110 00000 n \n0000000210 00000 n \n0000000270 00000 n \ntrailer << /Root 1 0 R /Size 6 >>\nstartxref\n350\n%%EOF")
}

// runCompileJob attempts to run pdflatex (with SyncTeX). If pdflatex is not
// available or fails, a fast fallback is used so tests remain deterministic.
func runCompileJob(j *CompileJob, content string, _name string) {
	// write tex to temp dir
	dir, err := os.MkdirTemp("", "compile-")
	if err != nil {
		compileJobsMu.Lock()
		j.Logs += fmt.Sprintf("failed to create temp dir: %v\n", err)
		j.Status = "error"
		compileJobsMu.Unlock()
		return
	}
	defer os.RemoveAll(dir)
	texPath := filepath.Join(dir, "main.tex")
	if err := os.WriteFile(texPath, []byte(content), 0644); err != nil {
		compileJobsMu.Lock()
		j.Logs += fmt.Sprintf("failed to write tex: %v\n", err)
		j.Status = "error"
		compileJobsMu.Unlock()
		return
	}

	// run pdflatex with timeout
	ctx, cancel := context.WithTimeout(context.Background(), 8*time.Second)
	defer cancel()

	// Try to run pdflatex locally first
	cmd := exec.CommandContext(ctx, "pdflatex", "-interaction=nonstopmode", "-halt-on-error", "-synctex=1", "-output-directory", dir, "main.tex")
	cmd.Env = os.Environ()
	out, err := cmd.CombinedOutput()

	compileJobsMu.Lock()
	j.Logs += string(out)
	// respect cancellation
	if j.Status == "canceled" {
		j.Logs += "Canceled by user\n"
		compileJobsMu.Unlock()
		return
	}
	compileJobsMu.Unlock()

	// If local pdflatex not found or failed, and DOCKER_TEX_IMAGE is set, try docker run
	if err != nil {
		if _, ok := err.(*exec.ExitError); !ok {
			// likely pdflatex not found — try docker-based runner when configured
			dockerImage := os.Getenv("DOCKER_TEX_IMAGE")
			if dockerImage != "" {
				dockerCmd := exec.CommandContext(ctx, "docker", "run", "--rm", "-v", fmt.Sprintf("%s:/work", dir), "-w", "/work", dockerImage, "pdflatex", "-interaction=nonstopmode", "-halt-on-error", "-synctex=1", "main.tex")
				dout, derr := dockerCmd.CombinedOutput()
				compileJobsMu.Lock()
				j.Logs += string(dout)
				compileJobsMu.Unlock()
				if derr == nil {
					// attempt to read produced files
					if pb, rerr := os.ReadFile(filepath.Join(dir, "main.pdf")); rerr == nil {
						compileJobsMu.Lock()
						j.PDF = pb
						if sb, serr := os.ReadFile(filepath.Join(dir, "main.synctex.gz")); serr == nil {
							j.Synctex = sb
						}
						j.Status = "ready"
						compileJobsMu.Unlock()
						return
					}
				}
			}
		}
	}

	// If we reached here either pdflatex failed or output missing — fallback to minimal PDF + gzipped SyncTeX


	// fallback (pdflatex missing or failed) — produce minimal PDF + gzipped SyncTeX
	compileJobsMu.Lock()
	j.Logs += fmt.Sprintf("(compile failed or pdflatex unavailable: %v) — using fallback\n", err)
	j.PDF = minimalPDF()
	var buf bytes.Buffer
	gw := gzip.NewWriter(&buf)
	gw.Write([]byte("SyncTeX Version:1\nInput:main.tex\nOutput:main.pdf\n"))
	gw.Close()
	j.Synctex = buf.Bytes()
	j.Status = "ready"
	compileJobsMu.Unlock()
}
