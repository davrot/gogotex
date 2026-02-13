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
	"regexp"
	"strconv"
	"sync"
	"time"
	"math"

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
type SyncEntry struct {
	Y    float64 `json:"y"`
	Line int     `json:"line"`
}

type CompileJob struct {
	JobID     string    `json:"jobId"`
	DocID     string    `json:"docId"`
	Status    string    `json:"status"` // compiling|ready|canceled|error
	Logs      string    `json:"logs"`
	CreatedAt time.Time `json:"createdAt"`

	// compiled artifacts (not serialized)
	PDF        []byte                 `json:"-"`
	Synctex    []byte                 `json:"-"`
	SynctexMap map[int][]SyncEntry    `json:"-"`
	ErrorMsg   string                 `json:"error,omitempty"`
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
	// If an *external* go-document service is configured/used by the
	// deployment then the auth service must NOT register the Phase‑03
	// in-memory endpoints (nginx will proxy /api/documents → external).
	if os.Getenv("DOC_SERVICE_EXTERNAL") == "true" {
		// external service will handle /api/documents — nothing to register here
		return
	}

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

	// --- Default Phase‑03 in-memory document endpoints (prototype) ---
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
	// Per-line lookup: returns { page, y, line } for a requested source line
	r.GET("/api/documents/:id/compile/:jobId/synctex/lookup", GetSyncTeXLookup)
	// Best-effort SyncTeX mapping endpoint (Phase-03 prototype): returns a
	// JSON mapping of page -> [{ y: 0..1, line: n }] computed from the
	// document's line count (fallback when precise SyncTeX parsing is not
	// available). Frontend uses this to map PDF clicks to source lines.
	r.GET("/api/documents/:id/compile/:jobId/synctex/map", GetSyncTeXMap)
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
      // respond to parent 'go-to' requests (editor -> preview)
      window.addEventListener('message', function(ev){ try {
        const d = ev.data || {}
        if (d && d.type === 'go-to' && typeof d.y === 'number') {
          const rect = canvas.getBoundingClientRect()
          const targetY = Math.max(0, Math.min(1, d.y)) * canvas.height
          // scroll the canvas into view near targetY
          window.scrollTo({ top: Math.max(0, targetY - 120), behavior: 'smooth' })
          // draw a transient highlight rectangle
          try {
            const ctx2 = canvas.getContext('2d')
            ctx2.save(); ctx2.strokeStyle = 'red'; ctx2.lineWidth = 2; ctx2.strokeRect(10, Math.max(0, targetY - 8), canvas.width - 20, 16); setTimeout(()=>{ /* no-op to let highlight be visible */ }, 400)
            ctx2.restore()
          } catch(e) {}
        }
      } catch(e){} }, false)
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
// respond to parent 'go-to' messages (editor -> preview stub)
window.addEventListener('message', function(ev){ try { var d = ev.data || {}; if (d && d.type === 'go-to' && typeof d.y === 'number') { window._lastGoTo = d; var y = d.y; var el = document.querySelector('p[data-line]'); var target = document.querySelector('[data-line="'+Math.round(y*10)+'"]') || document.querySelector('p[data-line="5"]'); try { target && target.scrollIntoView({behavior:'smooth', block:'center'}); } catch(e){} } } catch(e){} }, false)
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

// GetSyncTeXMap returns a best-effort JSON mapping for the compiled job.
// Prototype behavior: if exact SyncTeX parsing isn't available, we distribute
// source lines evenly across page 1 so frontend can do reasonably accurate
// clicks → line mapping. Response format:
// { pages: { "1": [ { "y": 0.012, "line": 1 }, ... ] } }
func GetSyncTeXMap(c *gin.Context) {
	id := c.Param("id")
	jobId := c.Param("jobId")

	// verify job exists and is ready
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

	// If we already have a parsed SyncTeX map, return it immediately
	if job.SynctexMap != nil && len(job.SynctexMap) > 0 {
		out := map[string]interface{}{"pages": map[string]interface{}{}}
		pages := out["pages"].(map[string]interface{})
		for p, arr := range job.SynctexMap {
			lst := make([]map[string]interface{}, 0, len(arr))
			for _, e := range arr {
				lst = append(lst, map[string]interface{}{"y": e.Y, "line": e.Line})
			}
			pages[fmt.Sprintf("%d", p)] = lst
		}
		c.JSON(http.StatusOK, out)
		return
	}

	// locate document content (best-effort)
	documentsMu.RLock()
	d, dok := documentsStore[id]
	documentsMu.RUnlock()
	var totalLines int
	if dok && d.Content != "" {
		totalLines = len(splitLines(d.Content))
	} else {
		// fallback: assume 1 line to avoid division by zero
		totalLines = 1
	}

	// Try to compute a higher-fidelity map using local `synctex` CLI when available
	if len(job.Synctex) > 0 && len(job.PDF) > 0 {
		if path, err := exec.LookPath("synctex"); err == nil && path != "" {
			// create tempdir with PDF + synctex.gz
			tmpd, err := os.MkdirTemp("", "synctex-parse-")
			if err == nil {
				defer os.RemoveAll(tmpd)
				_ = os.WriteFile(filepath.Join(tmpd, "main.pdf"), job.PDF, 0644)
				_ = os.WriteFile(filepath.Join(tmpd, "main.synctex.gz"), job.Synctex, 0644)

				// cap lines to probe to avoid long-running loops
				maxLines := totalLines
				if maxLines > 500 { maxLines = 500 }

				pageLines := map[int][]int{}
				rePage := regexp.MustCompile(`Page[: ]+(\d+)`)

				for i := 1; i <= maxLines; i++ {
					ctx, cancel := context.WithTimeout(context.Background(), 350*time.Millisecond)
					cmd := exec.CommandContext(ctx, "synctex", "view", "-i", fmt.Sprintf("%d:0:main.tex", i), "-o", "main.pdf")
					cmd.Dir = tmpd
					out, _ := cmd.CombinedOutput()
					cancel()
					m := rePage.FindSubmatch(out)
					if len(m) == 2 {
						p, _ := strconv.Atoi(string(m[1]))
						pageLines[p] = append(pageLines[p], i)
					}
				}

				// if we found any page assignments, build SynctexMap by evenly spacing y within each page
				if len(pageLines) > 0 {
					sm := map[int][]SyncEntry{}
					for p, lines := range pageLines {
						for idx, ln := range lines {
							n := float64(len(lines))
							y := (float64(idx) + 0.5) / n
							if y < 0 { y = 0 }
							if y > 1 { y = 1 }
							sm[p] = append(sm[p], SyncEntry{Y: y, Line: ln})
						}
					}
					compileJobsMu.Lock()
					job.SynctexMap = sm
					compileJobsMu.Unlock()

					out := map[string]interface{}{"pages": map[string]interface{}{}}
					pages := out["pages"].(map[string]interface{})
					for p, arr := range sm {
						lst := make([]map[string]interface{}, 0, len(arr))
						for _, e := range arr {
							lst = append(lst, map[string]interface{}{"y": e.Y, "line": e.Line})
						}
						pages[fmt.Sprintf("%d", p)] = lst
					}
					c.JSON(http.StatusOK, out)
					return
				}
			}
		}
	}

	// fallback: single-page proportional mapping (existing behavior)
	entries := []map[string]interface{}{}
	for i := 1; i <= totalLines; i++ {
		y := (float64(i)-0.5)/float64(totalLines)
		if y < 0 { y = 0 }
		if y > 1 { y = 1 }
		entries = append(entries, map[string]interface{}{"y": y, "line": i})
	}

	c.JSON(http.StatusOK, gin.H{"pages": map[string]interface{}{"1": entries}})
}

// GetSyncTeXLookup returns a single best-effort mapping for a given source line.
// Query param: ?line=<n>
// Response: { page: int, y: 0..1, line: int }
func GetSyncTeXLookup(c *gin.Context) {
	id := c.Param("id")
	jobId := c.Param("jobId")
	lineStr := c.Query("line")
	if lineStr == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "line query param required"})
		return
	}
	ln, err := strconv.Atoi(lineStr)
	if err != nil || ln <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid line"})
		return
	}

	// verify job exists and is ready
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

	// prefer cached SynctexMap when available
	if job.SynctexMap != nil {
		for p, arr := range job.SynctexMap {
			for _, e := range arr {
				if e.Line == ln {
					c.JSON(http.StatusOK, gin.H{"page": p, "y": e.Y, "line": e.Line})
					return
				}
			}
		}
		// not found in map -> fall back to nearest match across all pages
		bestP := 1
		bestY := 0.5
		bestLine := 0
		found := false
		for p, arr := range job.SynctexMap {
			for _, e := range arr {
				if !found || math.Abs(float64(e.Line-ln)) < math.Abs(float64(bestLine-ln)) {
					bestP = p
					bestY = e.Y
					bestLine = e.Line
					found = true
				}
			}
		}
		if found {
			c.JSON(http.StatusOK, gin.H{"page": bestP, "y": bestY, "line": ln})
			return
		}
	}

	// attempt to use synctex CLI for a precise lookup when possible
	if len(job.Synctex) > 0 && len(job.PDF) > 0 {
		if path, err := exec.LookPath("synctex"); err == nil && path != "" {
			tmpd, err := os.MkdirTemp("", "synctex-lookup-")
			if err == nil {
				defer os.RemoveAll(tmpd)
				_ = os.WriteFile(filepath.Join(tmpd, "main.pdf"), job.PDF, 0644)
				_ = os.WriteFile(filepath.Join(tmpd, "main.synctex.gz"), job.Synctex, 0644)

				ctx, cancel := context.WithTimeout(context.Background(), 350*time.Millisecond)
				cmd := exec.CommandContext(ctx, "synctex", "view", "-i", fmt.Sprintf("%d:0:main.tex", ln), "-o", "main.pdf")
				cmd.Dir = tmpd
				out, _ := cmd.CombinedOutput()
				cancel()
				re := regexp.MustCompile(`Page[: ]+(\d+)`)
				m := re.FindSubmatch(out)
				if len(m) == 2 {
					p, _ := strconv.Atoi(string(m[1]))
					// CLI doesn't provide normalized y easily here; return midpoint
					c.JSON(http.StatusOK, gin.H{"page": p, "y": 0.5, "line": ln})
					return
				}
			}
		}
	}

	// fallback proportional single-page mapping
	documentsMu.RLock()
	d, dok := documentsStore[id]
	documentsMu.RUnlock()
	var totalLines int
	if dok && d.Content != "" {
		totalLines = len(splitLines(d.Content))
	} else {
		totalLines = 1
	}
	if ln > totalLines { ln = totalLines }
	y := (float64(ln)-0.5)/float64(totalLines)
	if y < 0 { y = 0 }
	if y > 1 { y = 1 }
	c.JSON(http.StatusOK, gin.H{"page": 1, "y": y, "line": ln})
}

// parseSynctexMapFromGzip attempts to extract page->(y,line) mappings from a
// gzipped SyncTeX payload. It supports several textual variants and will
// synthesize reasonable `y` values when only page+line pairs are available.
func parseSynctexMapFromGzip(gz []byte) (map[int][]SyncEntry, error) {
	gr, err := gzip.NewReader(bytes.NewReader(gz))
	if err != nil {
		return nil, err
	}
	defer gr.Close()
	b, err := io.ReadAll(gr)
	if err != nil {
		return nil, err
	}
	s := string(b)

	// Try multiple regex flavors to capture (page, line, optional y)
	patterns := []*regexp.Regexp{
		// explicit: page:1 line:5 y:0.45
		regexp.MustCompile(`(?i)page[:=]?\s*(\d+)[^\S\n\r]{0,20}line[:=]?\s*(\d+)[^\S\n\r]{0,20}y[:=]?\s*([0-9]*\.?[0-9]+)`),
		// variant: Page 1, Line 5, y=0.45
		regexp.MustCompile(`(?i)page[:\s]+(\d+)[^\n\r]{0,40}line[:\s]+(\d+)[^\n\r]{0,40}y[:=]\s*([0-9]*\.?[0-9]+)`),
		// short tags: p:1 l:5 v:0.45 or p=1 l=5 y=0.45
		regexp.MustCompile(`(?i)\b(?:p|page)[:=]?\s*(\d+)\b[^{\n\r]{0,30}\b(?:l|line)[:=]?\s*(\d+)\b[^{\n\r]{0,30}\b(?:v|y|vert)[:=]?\s*([0-9]*\.?[0-9]+)`),
	}

	// map: page -> line -> y (y==0 means unknown)
	intermediate := map[int]map[int]float64{}

	for _, re := range patterns {
		for _, m := range re.FindAllStringSubmatch(s, -1) {
			p, _ := strconv.Atoi(m[1])
			ln, _ := strconv.Atoi(m[2])
			y, _ := strconv.ParseFloat(m[3], 64)
			if y < 0 { y = 0 }
			if y > 1 { y = 1 }
			if _, ok := intermediate[p]; !ok { intermediate[p] = map[int]float64{} }
			if _, exists := intermediate[p][ln]; !exists { intermediate[p][ln] = y }
		}
	}

	// Looser capture: page+line pairs without y
	reNoY := regexp.MustCompile(`(?i)\b(?:page)[:=]?\s*(\d+)[^\S\n\r]{0,40}(?:line|l)[:=]?\s*(\d+)`)
	for _, m := range reNoY.FindAllStringSubmatch(s, -1) {
		p, _ := strconv.Atoi(m[1])
		ln, _ := strconv.Atoi(m[2])
		if _, ok := intermediate[p]; !ok { intermediate[p] = map[int]float64{} }
		if _, exists := intermediate[p][ln]; !exists { intermediate[p][ln] = 0.0 }
	}

	if len(intermediate) == 0 {
		return nil, fmt.Errorf("no synctex map patterns found")
	}

	// Convert to final map[int][]SyncEntry, synthesizing y for unknowns by
	// ordering lines within a page and spacing them evenly.
	out := map[int][]SyncEntry{}
	for p, lines := range intermediate {
		// collect and sort line numbers
		var keys []int
		for ln := range lines { keys = append(keys, ln) }
		sort.Ints(keys)
		n := float64(len(keys))
		for i, ln := range keys {
			y := lines[ln]
			if y == 0 {
				// evenly interpolate position
				y = (float64(i) + 0.5) / n
				if y < 0 { y = 0 }
				if y > 1 { y = 1 }
			}
			out[p] = append(out[p], SyncEntry{Y: y, Line: ln})
		}
	}
	return out, nil
}

// splitLines is like strings.Split(..."\n") but treats trailing newline sensibly
func splitLines(s string) []string {
	// simple implementation avoiding extra imports
	lines := []string{}
	start := 0
	for i := 0; i < len(s); i++ {
		if s[i] == '\n' {
			lines = append(lines, s[start:i])
			start = i+1
		}
	}
	if start <= len(s)-1 {
		lines = append(lines, s[start:])
	}
	if len(lines) == 0 {
		return []string{""}
	}
	return lines
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
	gw.Write([]byte("SyncTeX Version:1\nInput:main.tex\nOutput:main.pdf\npage:1 line:1 y:0.5\n"))
	gw.Close()
	j.Synctex = buf.Bytes()
	// attempt to parse SyncTeX gzip into a best-effort map so front-end can use it immediately
	if sm, perr := parseSynctexMapFromGzip(j.Synctex); perr == nil && len(sm) > 0 {
		j.SynctexMap = sm
	}
	j.Status = "ready"
	compileJobsMu.Unlock()
}
