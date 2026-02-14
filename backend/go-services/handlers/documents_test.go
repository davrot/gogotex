package handlers

import (
	"bytes"
	"compress/gzip"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

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

	// DELETE
	w = httptest.NewRecorder()
	req = httptest.NewRequest(http.MethodDelete, fmt.Sprintf("/api/documents/%s", id), nil)
	g.ServeHTTP(w, req)
	assert.Equal(t, http.StatusNoContent, w.Code)

	// LIST should no longer contain it
	w = httptest.NewRecorder()
	req = httptest.NewRequest(http.MethodGet, "/api/documents", nil)
	g.ServeHTTP(w, req)
	assert.Equal(t, http.StatusOK, w.Code)
	err = json.Unmarshal(w.Body.Bytes(), &list)
	require.NoError(t, err)
	found = false
	for _, it := range list {
		if idv, ok := it["id"].(string); ok && idv == id {
			found = true
		}
	}
	assert.False(t, found, "deleted document should not appear in list")

	// COMPILE (stub) -> returns job and becomes ready shortly after
	w = httptest.NewRecorder()
	req = httptest.NewRequest(http.MethodPost, fmt.Sprintf("/api/documents/%s/compile", id), nil)
	g.ServeHTTP(w, req)
	assert.Equal(t, http.StatusOK, w.Code)
	var comp map[string]interface{}
	err = json.Unmarshal(w.Body.Bytes(), &comp)
	require.NoError(t, err)
	jobID, ok := comp["jobId"].(string)
	require.True(t, ok)

	// Poll logs until ready (with timeout)
	var logsResp map[string]interface{}
	ready := false
	for i := 0; i < 20; i++ {
		w = httptest.NewRecorder()
		req = httptest.NewRequest(http.MethodGet, fmt.Sprintf("/api/documents/%s/compile/logs", id), nil)
		g.ServeHTTP(w, req)
		if w.Code != http.StatusOK {
			time.Sleep(25 * time.Millisecond)
			continue
		}
		err = json.Unmarshal(w.Body.Bytes(), &logsResp)
		require.NoError(t, err)
		if s, _ := logsResp["status"].(string); s == "ready" {
			ready = true
			break
		}
		time.Sleep(25 * time.Millisecond)
	}
	require.True(t, ready, "compile job did not reach ready state")
	require.Contains(t, logsResp["logs"].(string), "Compiled successfully")

	// PREVIEW -> HTML content
	w = httptest.NewRecorder()
	req = httptest.NewRequest(http.MethodGet, fmt.Sprintf("/api/documents/%s/preview", id), nil)
	g.ServeHTTP(w, req)
	assert.Equal(t, http.StatusOK, w.Code)
	body := w.Body.String()
	assert.Contains(t, body, "PDF preview (stub)")

	// Start another compile then cancel it immediately
	w = httptest.NewRecorder()
	req = httptest.NewRequest(http.MethodPost, fmt.Sprintf("/api/documents/%s/compile", id), nil)
	g.ServeHTTP(w, req)
	assert.Equal(t, http.StatusOK, w.Code)

	// cancel
	w = httptest.NewRecorder()
	req = httptest.NewRequest(http.MethodPost, fmt.Sprintf("/api/documents/%s/compile/cancel", id), nil)
	g.ServeHTTP(w, req)
	assert.Equal(t, http.StatusOK, w.Code)

	// logs should indicate canceled
	w = httptest.NewRecorder()
	req = httptest.NewRequest(http.MethodGet, fmt.Sprintf("/api/documents/%s/compile/logs", id), nil)
	g.ServeHTTP(w, req)
	assert.Equal(t, http.StatusOK, w.Code)
	var logs2 map[string]interface{}
	err = json.Unmarshal(w.Body.Bytes(), &logs2)
	require.NoError(t, err)
	assert.Equal(t, "canceled", logs2["status"])
	assert.Contains(t, logs2["logs"].(string), "Canceled")

	// JOB LIST
	w = httptest.NewRecorder()
	req = httptest.NewRequest(http.MethodGet, fmt.Sprintf("/api/documents/%s/compile/jobs", id), nil)
	g.ServeHTTP(w, req)
	assert.Equal(t, http.StatusOK, w.Code)
	var jobs []map[string]interface{}
	err = json.Unmarshal(w.Body.Bytes(), &jobs)
	require.NoError(t, err)
	assert.GreaterOrEqual(t, len(jobs), 1)

	// download the earlier (ready) job PDF
	// find a ready job id from compileJobs map
	var readyJob string
	compileJobsMu.RLock()
	for k, j := range compileJobs {
		if j.DocID == id && j.Status == "ready" {
			readyJob = k
			break
		}
	}
	compileJobsMu.RUnlock()
	require.NotEmpty(t, readyJob)

	w = httptest.NewRecorder()
	req = httptest.NewRequest(http.MethodGet, fmt.Sprintf("/api/documents/%s/compile/%s/download", id, readyJob), nil)
	g.ServeHTTP(w, req)
	assert.Equal(t, http.StatusOK, w.Code)
	assert.Equal(t, "application/pdf", w.Header().Get("Content-Type"))
	assert.Contains(t, w.Body.String(), "%PDF")

	// synctex endpoint should return gzipped SyncTeX content (fallback or real)
	w = httptest.NewRecorder()
	req = httptest.NewRequest(http.MethodGet, fmt.Sprintf("/api/documents/%s/compile/%s/synctex", id, readyJob), nil)
	g.ServeHTTP(w, req)
	assert.Equal(t, http.StatusOK, w.Code)
	assert.Equal(t, "application/gzip", w.Header().Get("Content-Type"))
	gr, err := gzip.NewReader(bytes.NewReader(w.Body.Bytes()))
	require.NoError(t, err)
	defer gr.Close()
	b, err := io.ReadAll(gr)
	require.NoError(t, err)
	assert.Contains(t, string(b), "SyncTeX")

	// and the new SyncTeX map endpoint should return per-line y->line mappings
	w = httptest.NewRecorder()
	req = httptest.NewRequest(http.MethodGet, fmt.Sprintf("/api/documents/%s/compile/%s/synctex/map", id, readyJob), nil)
	g.ServeHTTP(w, req)
	assert.Equal(t, http.StatusOK, w.Code)
	var mapResp map[string]interface{}
	err = json.Unmarshal(w.Body.Bytes(), &mapResp)
	require.NoError(t, err)
	pages, ok := mapResp["pages"].(map[string]interface{})
	require.True(t, ok)
	p1, ok := pages["1"].([]interface{})
	require.True(t, ok)
	// should contain at least one mapping entry and the line numbers should be present
	require.GreaterOrEqual(t, len(p1), 1)
	first, ok := p1[0].(map[string]interface{})
	require.True(t, ok)
	_, hasLine := first["line"]
	require.True(t, hasLine)

	// simulate a pre-computed SynctexMap and ensure handler returns it unchanged
	compileJobsMu.Lock()
	if j, ok := compileJobs[jobID]; ok {
		j.SynctexMap = map[int][]SyncEntry{1: {{Y: 0.1, Line: 1}, {Y: 0.8, Line: 10}}}
	}
	compileJobsMu.Unlock()

	w = httptest.NewRecorder()
	req = httptest.NewRequest(http.MethodGet, fmt.Sprintf("/api/documents/%s/compile/%s/synctex/map", id, readyJob), nil)
	g.ServeHTTP(w, req)
	assert.Equal(t, http.StatusOK, w.Code)
	var mapResp2 map[string]interface{}
	err = json.Unmarshal(w.Body.Bytes(), &mapResp2)
	require.NoError(t, err)
	pages2, ok := mapResp2["pages"].(map[string]interface{})
	require.True(t, ok)
	p1b, ok := pages2["1"].([]interface{})
	require.True(t, ok)
	require.Equal(t, 2, len(p1b))

	// Lookup endpoint should return a single mapping entry for a requested line
	w = httptest.NewRecorder()
	req = httptest.NewRequest(http.MethodGet, fmt.Sprintf("/api/documents/%s/compile/%s/synctex/lookup?line=1", id, readyJob), nil)
	g.ServeHTTP(w, req)
	assert.Equal(t, http.StatusOK, w.Code)
	var lookup map[string]interface{}
	err = json.Unmarshal(w.Body.Bytes(), &lookup)
	require.NoError(t, err)
	assert.Equal(t, float64(1), lookup["page"])
	assert.Equal(t, float64(1), lookup["line"])
	assert.InDelta(t, 0.1, lookup["y"].(float64), 0.001)

	// Fallback lookup: clear SynctexMap and use proportional mapping from document content
	compileJobsMu.Lock()
	if j, ok := compileJobs[jobID]; ok {
		j.SynctexMap = nil
	}
	compileJobsMu.Unlock()
	documentsMu.Lock()
	if d2, ok := documentsStore[id]; ok {
		d2.Content = strings.Repeat("x\n", 10)
	}
	documentsMu.Unlock()

	w = httptest.NewRecorder()
	req = httptest.NewRequest(http.MethodGet, fmt.Sprintf("/api/documents/%s/compile/%s/synctex/lookup?line=5", id, readyJob), nil)
	g.ServeHTTP(w, req)
	assert.Equal(t, http.StatusOK, w.Code)
	var lookup2 map[string]interface{}
	err = json.Unmarshal(w.Body.Bytes(), &lookup2)
	require.NoError(t, err)
	assert.Equal(t, float64(1), lookup2["page"])
	expectedY := (5.0 - 0.5) / 10.0
	assert.InDelta(t, expectedY, lookup2["y"].(float64), 0.01)
}

func TestParseSynctexGzipFallback(t *testing.T) {
	g := gin.New()
	RegisterDocumentRoutes(g)

	// create a document
	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/api/documents", strings.NewReader(`{"name":"s.tex","content":"line1\nline2\nline3\nline4\nline5\n"}`))
	req.Header.Set("Content-Type", "application/json")
	g.ServeHTTP(w, req)
	require.Equal(t, http.StatusCreated, w.Code)
	var cr map[string]string
	err := json.Unmarshal(w.Body.Bytes(), &cr)
	require.NoError(t, err)
	id := cr["id"]

	// create a fake ready compile job that contains a gzipped SyncTeX with parseable entries
	jobID := fmt.Sprintf("job_%d", time.Now().UnixNano())
	var buf bytes.Buffer
	gw := gzip.NewWriter(&buf)
	// embed simple parseable patterns that our parser recognizes
	gw.Write([]byte("SyncTeX Version:1\nInput:main.tex\npage:1 line:1 y:0.05\npage:1 line:5 y:0.45\n"))
	gw.Close()
	job := &CompileJob{JobID: jobID, DocID: id, Status: "ready", Logs: "ok", CreatedAt: time.Now(), Synctex: buf.Bytes(), PDF: minimalPDF()}
	compileJobsMu.Lock()
	compileJobs[jobID] = job
	compileJobsMu.Unlock()

	// request synctex map -> should parse and return entries
	w = httptest.NewRecorder()
	req = httptest.NewRequest(http.MethodGet, fmt.Sprintf("/api/documents/%s/compile/%s/synctex/map", id, jobID), nil)
	g.ServeHTTP(w, req)
	require.Equal(t, http.StatusOK, w.Code)
	var resp map[string]interface{}
	err = json.Unmarshal(w.Body.Bytes(), &resp)
	require.NoError(t, err)
	pages := resp["pages"].(map[string]interface{})
	p1 := pages["1"].([]interface{})
	require.Equal(t, 2, len(p1))
	first := p1[0].(map[string]interface{})
	require.InDelta(t, 0.05, first["y"].(float64), 1e-6)
	require.Equal(t, float64(1), first["line"].(float64))
}

func TestParseSynctexGzipRobustPatterns(t *testing.T) {
	g := gin.New()
	RegisterDocumentRoutes(g)

	// create a document
	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/api/documents", strings.NewReader(`{"name":"s2.tex","content":"l1\nl2\nl3\nl4\nl5\nl6\n"}`))
	req.Header.Set("Content-Type", "application/json")
	g.ServeHTTP(w, req)
	require.Equal(t, http.StatusCreated, w.Code)
	var cr map[string]string
	err := json.Unmarshal(w.Body.Bytes(), &cr)
	require.NoError(t, err)
	id := cr["id"]

	// craft gzipped synctex with multiple pattern variants
	var buf bytes.Buffer
	gw := gzip.NewWriter(&buf)
	gw.Write([]byte("SyncTeX Version:1\nInput:main.tex\n"))
	// variant A: explicit page/line/y
	gw.Write([]byte("page:1 line:2 y:0.12\n"))
	// variant B: different spacing/capitalization
	gw.Write([]byte("Page 1, Line 5, y=0.45\n"))
	// variant C: page+line without y (parser should synthesize y)
	gw.Write([]byte("line 3 page 1\n"))
	// different page
	gw.Write([]byte("p:2 l:1 v:0.5\n"))
	gw.Close()

	jobID := fmt.Sprintf("job_%d", time.Now().UnixNano())
	job := &CompileJob{JobID: jobID, DocID: id, Status: "ready", Logs: "ok", CreatedAt: time.Now(), Synctex: buf.Bytes(), PDF: minimalPDF()}
	compileJobsMu.Lock()
	compileJobs[jobID] = job
	compileJobsMu.Unlock()

	// request synctex map -> should parse and return entries for page1 and page2
	w = httptest.NewRecorder()
	req = httptest.NewRequest(http.MethodGet, fmt.Sprintf("/api/documents/%s/compile/%s/synctex/map", id, jobID), nil)
	g.ServeHTTP(w, req)
	require.Equal(t, http.StatusOK, w.Code)
	var resp map[string]interface{}
	err = json.Unmarshal(w.Body.Bytes(), &resp)
	require.NoError(t, err)
	pages := resp["pages"].(map[string]interface{})
	p1 := pages["1"].([]interface{})
	p2 := pages["2"].([]interface{})
	// page 1 should contain lines 2,3,5
	foundLines := map[int]bool{}
	for _, it := range p1 {
		m := it.(map[string]interface{})
		ln := int(m["line"].(float64))
		foundLines[ln] = true
	}
	require.True(t, foundLines[2])
	require.True(t, foundLines[3])
	require.True(t, foundLines[5])
	// page 2 should contain line 1 with y approx 0.5
	m2 := p2[0].(map[string]interface{})
	require.Equal(t, float64(1), m2["line"].(float64))
	require.InDelta(t, 0.5, m2["y"].(float64), 0.001)
}

func TestRunCompileJob_PersistsArtifacts(t *testing.T) {
	// prepare a compiling job and ensure fallback path executes
	jobID := fmt.Sprintf("job_%d", time.Now().UnixNano())
	job := &CompileJob{JobID: jobID, DocID: "docX", Status: "compiling", Logs: "", CreatedAt: time.Now()}

	// override minioUploadFunc to capture uploads
	uploads := map[string][]byte{}
	uDone := make(chan struct{}, 2)
	oldUpload := minioUploadFunc
	minioUploadFunc = func(ctx context.Context, key string, data []byte, contentType string) error {
		uploads[key] = append([]byte(nil), data...)
		select {
		case uDone <- struct{}{}:
		default:
		}
		return nil
	}
	defer func() { minioUploadFunc = oldUpload }()

	// override persistCompileFunc to capture persisted record
	var persisted *compilestore.PersistedCompile
	pDone := make(chan struct{}, 1)
	oldPersist := persistCompileFunc
	persistCompileFunc = func(ctx context.Context, j *CompileJob) error {
		persisted = &compilestore.PersistedCompile{JobID: j.JobID, DocID: j.DocID, Status: j.Status, PDFKey: j.OutputPDFKey, SynctexKey: j.SynctexKey}
		select {
		case pDone <- struct{}{}:
		default:
		}
		return nil
	}
	defer func() { persistCompileFunc = oldPersist }()

	// run worker (uses fallback minimal PDF + synctex)
	runCompileJob(job, "some content", "main.tex")

	// wait for both uploads + persistence (with timeout)
	wait := time.After(2 * time.Second)
	count := 0
	for count < 2 {
		select {
		case <-uDone:
			count++
		case <-wait:
			t.Fatalf("timeout waiting for uploads")
		}
	}
	select {
	case <-pDone:
	default:
		t.Fatalf("persist not called")
	}

	// assert job was marked ready and keys set
	if job.Status != "ready" {
		t.Fatalf("expected job ready, got %s", job.Status)
	}
	if job.OutputPDFKey == "" || job.SynctexKey == "" {
		t.Fatalf("expected persisted keys to be set")
	}
	// ensure uploads recorded
	if _, ok := uploads[job.OutputPDFKey]; !ok {
		t.Fatalf("pdf not uploaded")
	}
	if _, ok := uploads[job.SynctexKey]; !ok {
		t.Fatalf("synctex not uploaded")
	}
	// ensure persisted metadata captured
	require.NotNil(t, persisted)
	require.Equal(t, job.JobID, persisted.JobID)
	require.Equal(t, job.OutputPDFKey, persisted.PDFKey)
}
