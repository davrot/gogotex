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
}
