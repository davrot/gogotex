# Phase 6: LaTeX Compilation Service

**Duration**: 5-6 days  
**Goal**: Hybrid WASM + Docker LaTeX compilation with queue management and PDF generation

**Prerequisites**: Phases 1-5 completed, document service running

---

## Prerequisites

- [ ] Phases 1-5 completed
- [ ] Document service running and accessible
- [ ] Redis available for queue management
- [ ] MinIO available for PDF storage
- [ ] Docker available for TeX Live Full compilation
- [ ] Go 1.21+ installed

---

## Task 1: Compilation Service Structure (30 min)

### 1.1 Create Directories

```bash
cd latex-collaborative-editor/backend/go-services

mkdir -p cmd/compiler
mkdir -p internal/compiler/{handler,service,queue,wasm,docker}
mkdir -p internal/compiler/parser
mkdir -p pkg/latex
```

### 1.2 Install Dependencies

```bash
# Redis client
go get github.com/redis/go-redis/v9

# WASM runner (for running WASM binaries)
go get github.com/tetratelabs/wazero

# PDF utilities
go get github.com/pdfcpu/pdfcpu/pkg/api

# Archive utilities for project bundling
go get github.com/mholt/archiver/v3
```

**Verification**:
```bash
go mod tidy
go mod verify
```

---

## Task 2: Compilation Models (1 hour)

### 2.1 Compilation Job Model

Create: `internal/models/compilation.go`

```go
package models

import (
	"time"

	"go.mongodb.org/mongo-driver/bson/primitive"
)

// CompilationJob represents a LaTeX compilation request
type CompilationJob struct {
	ID             primitive.ObjectID `bson:"_id,omitempty" json:"id"`
	ProjectID      primitive.ObjectID `bson:"projectId" json:"projectId"`
	DocumentID     primitive.ObjectID `bson:"documentId" json:"documentId"` // Main .tex file
	UserID         string             `bson:"userId" json:"userId"`
	Status         string             `bson:"status" json:"status"` // pending, processing, success, failed
	Engine         string             `bson:"engine" json:"engine"` // wasm, docker, auto
	ActualEngine   string             `bson:"actualEngine,omitempty" json:"actualEngine,omitempty"` // Which was used
	CompilerType   string             `bson:"compilerType" json:"compilerType"` // pdflatex, xelatex, lualatex
	Priority       int                `bson:"priority" json:"priority"` // Higher = more urgent
	CreatedAt      time.Time          `bson:"createdAt" json:"createdAt"`
	StartedAt      *time.Time         `bson:"startedAt,omitempty" json:"startedAt,omitempty"`
	CompletedAt    *time.Time         `bson:"completedAt,omitempty" json:"completedAt,omitempty"`
	Duration       int64              `bson:"duration,omitempty" json:"duration,omitempty"` // Milliseconds
	OutputPDFKey   string             `bson:"outputPdfKey,omitempty" json:"outputPdfKey,omitempty"` // MinIO key
	OutputLogKey   string             `bson:"outputLogKey,omitempty" json:"outputLogKey,omitempty"` // MinIO key
	Errors         []CompilationError `bson:"errors,omitempty" json:"errors,omitempty"`
	Warnings       []CompilationError `bson:"warnings,omitempty" json:"warnings,omitempty"`
	RetryCount     int                `bson:"retryCount" json:"retryCount"`
	MaxRetries     int                `bson:"maxRetries" json:"maxRetries"`
}

// CompilationError represents a compilation error or warning
type CompilationError struct {
	Line    int    `bson:"line" json:"line"`
	File    string `bson:"file" json:"file"`
	Message string `bson:"message" json:"message"`
	Type    string `bson:"type" json:"type"` // error, warning, info
	Raw     string `bson:"raw" json:"raw"`   // Raw log line
}

// CompilationStatus constants
const (
	StatusPending    = "pending"
	StatusProcessing = "processing"
	StatusSuccess    = "success"
	StatusFailed     = "failed"
	StatusCancelled  = "cancelled"
)

// CompilationEngine constants
const (
	EngineAuto   = "auto"   // Automatic selection
	EngineWASM   = "wasm"   // WASM-based (fast, limited packages)
	EngineDocker = "docker" // Docker-based (slow, full TeX Live)
)

// CompilerType constants
const (
	CompilerPDFLaTeX = "pdflatex"
	CompilerXeLaTeX  = "xelatex"
	CompilerLuaLaTeX = "lualatex"
)

// CreateCompilationRequest for API
type CreateCompilationRequest struct {
	ProjectID    primitive.ObjectID `json:"projectId" validate:"required"`
	DocumentID   primitive.ObjectID `json:"documentId" validate:"required"`
	Engine       string             `json:"engine,omitempty" validate:"omitempty,oneof=auto wasm docker"`
	CompilerType string             `json:"compilerType,omitempty" validate:"omitempty,oneof=pdflatex xelatex lualatex"`
	Priority     int                `json:"priority,omitempty"`
}

// CompilationStatus for API
type CompilationStatusResponse struct {
	Job       *CompilationJob `json:"job"`
	PDFUrl    string          `json:"pdfUrl,omitempty"`    // Presigned download URL
	LogUrl    string          `json:"logUrl,omitempty"`    // Presigned log URL
	Progress  int             `json:"progress"`            // 0-100
	QueueSize int             `json:"queueSize,omitempty"` // Jobs ahead in queue
}
```

### 2.2 Compilation Statistics

Create: `internal/models/compilation_stats.go`

```go
package models

import "time"

// CompilationStats represents compilation statistics
type CompilationStats struct {
	TotalJobs       int64         `json:"totalJobs"`
	SuccessfulJobs  int64         `json:"successfulJobs"`
	FailedJobs      int64         `json:"failedJobs"`
	PendingJobs     int64         `json:"pendingJobs"`
	ProcessingJobs  int64         `json:"processingJobs"`
	AverageDuration time.Duration `json:"averageDuration"`
	WASMJobs        int64         `json:"wasmJobs"`
	DockerJobs      int64         `json:"dockerJobs"`
}
```

**Verification**:
```bash
go build ./internal/models/...
```

---

## Task 3: LaTeX Log Parser (2 hours)

### 3.1 Log Parser

Create: `internal/compiler/parser/log_parser.go`

```go
package parser

import (
	"bufio"
	"fmt"
	"regexp"
	"strconv"
	"strings"

	"github.com/yourusername/gogolatex/internal/models"
)

// LogParser parses LaTeX compilation logs
type LogParser struct {
	errorPattern   *regexp.Regexp
	warningPattern *regexp.Regexp
	linePattern    *regexp.Regexp
	filePattern    *regexp.Regexp
}

// NewLogParser creates a new log parser
func NewLogParser() *LogParser {
	return &LogParser{
		// Match LaTeX errors: "! Error message"
		errorPattern: regexp.MustCompile(`^!\s+(.+)`),
		
		// Match warnings: "LaTeX Warning: ..."
		warningPattern: regexp.MustCompile(`^(?:LaTeX|Package|Class)\s+Warning:\s+(.+)`),
		
		// Match line numbers: "l.123 some content"
		linePattern: regexp.MustCompile(`^l\.(\d+)\s+(.+)`),
		
		// Match file references: "(./filename.tex"
		filePattern: regexp.MustCompile(`\(\.\/([^)]+\.tex)`),
	}
}

// ParseLog parses a LaTeX log and extracts errors and warnings
func (p *LogParser) ParseLog(logContent string) ([]models.CompilationError, []models.CompilationError) {
	var errors []models.CompilationError
	var warnings []models.CompilationError

	scanner := bufio.NewScanner(strings.NewReader(logContent))
	
	var currentFile string
	var inError bool
	var errorBuilder strings.Builder
	var errorLine int

	for scanner.Scan() {
		line := scanner.Text()

		// Track current file
		if matches := p.filePattern.FindStringSubmatch(line); len(matches) > 1 {
			currentFile = matches[1]
		}

		// Check for errors
		if matches := p.errorPattern.FindStringSubmatch(line); len(matches) > 1 {
			inError = true
			errorBuilder.Reset()
			errorBuilder.WriteString(matches[1])
			errorLine = 0
			continue
		}

		// If we're in an error, collect additional lines
		if inError {
			// Check for line number
			if matches := p.linePattern.FindStringSubmatch(line); len(matches) > 2 {
				lineNum, _ := strconv.Atoi(matches[1])
				errorLine = lineNum
				errorBuilder.WriteString(" ")
				errorBuilder.WriteString(matches[2])
			} else if strings.HasPrefix(line, " ") || strings.HasPrefix(line, "<") {
				// Additional error context
				errorBuilder.WriteString(" ")
				errorBuilder.WriteString(strings.TrimSpace(line))
			} else {
				// End of error block
				errors = append(errors, models.CompilationError{
					Line:    errorLine,
					File:    currentFile,
					Message: errorBuilder.String(),
					Type:    "error",
					Raw:     errorBuilder.String(),
				})
				inError = false
			}
			continue
		}

		// Check for warnings
		if matches := p.warningPattern.FindStringSubmatch(line); len(matches) > 1 {
			warning := matches[1]
			
			// Try to extract line number from warning
			lineNum := p.extractLineNumber(warning)
			
			warnings = append(warnings, models.CompilationError{
				Line:    lineNum,
				File:    currentFile,
				Message: warning,
				Type:    "warning",
				Raw:     line,
			})
		}
	}

	// If we ended while still in an error
	if inError && errorBuilder.Len() > 0 {
		errors = append(errors, models.CompilationError{
			Line:    errorLine,
			File:    currentFile,
			Message: errorBuilder.String(),
			Type:    "error",
			Raw:     errorBuilder.String(),
		})
	}

	return errors, warnings
}

// extractLineNumber tries to extract a line number from a warning message
func (p *LogParser) extractLineNumber(message string) int {
	// Common patterns: "on line 123", "line 123", "(123)"
	patterns := []*regexp.Regexp{
		regexp.MustCompile(`on line (\d+)`),
		regexp.MustCompile(`line (\d+)`),
		regexp.MustCompile(`\((\d+)\)`),
	}

	for _, pattern := range patterns {
		if matches := pattern.FindStringSubmatch(message); len(matches) > 1 {
			if lineNum, err := strconv.Atoi(matches[1]); err == nil {
				return lineNum
			}
		}
	}

	return 0
}

// IsSuccessful checks if the log indicates a successful compilation
func (p *LogParser) IsSuccessful(logContent string) bool {
	// Look for success indicators
	successIndicators := []string{
		"Output written on",
		"Transcript written on",
	}

	for _, indicator := range successIndicators {
		if strings.Contains(logContent, indicator) {
			// Check if there are fatal errors
			if !strings.Contains(logContent, "! Emergency stop") &&
			   !strings.Contains(logContent, "! Fatal error") {
				return true
			}
		}
	}

	return false
}

// GetPageCount extracts the number of pages from the log
func (p *LogParser) GetPageCount(logContent string) int {
	// Look for "Output written on filename.pdf (X pages"
	pattern := regexp.MustCompile(`Output written on .+\.pdf \((\d+) pages?`)
	if matches := pattern.FindStringSubmatch(logContent); len(matches) > 1 {
		if count, err := strconv.Atoi(matches[1]); err == nil {
			return count
		}
	}
	return 0
}

// SimplifyError creates a user-friendly error message
func SimplifyError(err models.CompilationError) string {
	msg := err.Message

	// Common error simplifications
	simplifications := map[string]string{
		"Undefined control sequence": "Unknown LaTeX command",
		"Missing $ inserted":         "Missing math mode delimiter ($)",
		"Runaway argument":           "Unclosed bracket or brace",
		"File not found":             "Could not find included file",
		"Package.*not found":         "LaTeX package not installed",
	}

	for pattern, replacement := range simplifications {
		if matched, _ := regexp.MatchString(pattern, msg); matched {
			return fmt.Sprintf("%s on line %d", replacement, err.Line)
		}
	}

	// Default: return first 100 characters of message
	if len(msg) > 100 {
		return msg[:100] + "..."
	}
	return msg
}
```

### 3.2 Package Detector

Create: `internal/compiler/parser/package_detector.go`

```go
package parser

import (
	"bufio"
	"regexp"
	"strings"
)

// PackageDetector detects required LaTeX packages from source
type PackageDetector struct {
	usePackagePattern *regexp.Regexp
	graphicsPattern   *regexp.Regexp
	bibPattern        *regexp.Regexp
}

// NewPackageDetector creates a new package detector
func NewPackageDetector() *PackageDetector {
	return &PackageDetector{
		usePackagePattern: regexp.MustCompile(`\\usepackage(?:\[.*?\])?\{([^}]+)\}`),
		graphicsPattern:   regexp.MustCompile(`\\includegraphics`),
		bibPattern:        regexp.MustCompile(`\\bibliography\{`),
	}
}

// DetectPackages analyzes LaTeX source and returns required packages
func (d *PackageDetector) DetectPackages(content string) []string {
	packagesMap := make(map[string]bool)
	scanner := bufio.NewScanner(strings.NewReader(content))

	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())

		// Skip comments
		if strings.HasPrefix(line, "%") {
			continue
		}

		// Find \usepackage{...}
		matches := d.usePackagePattern.FindAllStringSubmatch(line, -1)
		for _, match := range matches {
			if len(match) > 1 {
				// Handle multiple packages in one usepackage
				packages := strings.Split(match[1], ",")
				for _, pkg := range packages {
					packagesMap[strings.TrimSpace(pkg)] = true
				}
			}
		}

		// Detect implicit packages
		if d.graphicsPattern.MatchString(line) {
			packagesMap["graphicx"] = true
		}
		if d.bibPattern.MatchString(line) {
			packagesMap["natbib"] = true
		}
	}

	// Convert map to slice
	packages := make([]string, 0, len(packagesMap))
	for pkg := range packagesMap {
		packages = append(packages, pkg)
	}

	return packages
}

// RequiresFullTexLive checks if packages require full TeX Live
func (d *PackageDetector) RequiresFullTexLive(packages []string) bool {
	// Packages that require full TeX Live (not in WASM)
	fullTexLivePackages := map[string]bool{
		"pgfplots":    true,
		"tikz-cd":     true,
		"chemfig":     true,
		"minted":      true, // Requires Python
		"pythontex":   true,
		"asymptote":   true,
		"pstricks":    true,
		"xy":          true,
		"beamerposter": true,
	}

	for _, pkg := range packages {
		if fullTexLivePackages[pkg] {
			return true
		}
	}

	return false
}

// GetWASMCompatiblePackages returns packages compatible with WASM LaTeX
func (d *PackageDetector) GetWASMCompatiblePackages() []string {
	return []string{
		"amsmath", "amssymb", "amsthm", "amsfonts",
		"geometry", "graphicx", "hyperref", "xcolor",
		"natbib", "biblatex", "cite",
		"tikz", "pgf",
		"fancyhdr", "lastpage",
		"enumitem", "parskip",
		"babel", "inputenc", "fontenc",
		"caption", "subcaption",
		"booktabs", "longtable", "multirow",
		"listings", "algorithm", "algorithmic",
	}
}
```

**Verification**:
```bash
go build ./internal/compiler/parser/...
```

---

## Task 4: Redis Queue Manager (2 hours)

### 4.1 Queue Configuration

Create: `internal/compiler/queue/config.go`

```go
package queue

import "time"

// QueueConfig holds queue configuration
type QueueConfig struct {
	QueueName           string
	MaxWorkers          int
	MaxRetries          int
	JobTimeout          time.Duration
	RetryDelay          time.Duration
	PriorityLevels      int
	MaxQueueSize        int
	ProcessingQueueName string
	FailedQueueName     string
}

// DefaultQueueConfig returns default queue configuration
func DefaultQueueConfig() *QueueConfig {
	return &QueueConfig{
		QueueName:           "compilation:queue",
		ProcessingQueueName: "compilation:processing",
		FailedQueueName:     "compilation:failed",
		MaxWorkers:          4,
		MaxRetries:          3,
		JobTimeout:          5 * time.Minute,
		RetryDelay:          30 * time.Second,
		PriorityLevels:      3,
		MaxQueueSize:        1000,
	}
}
```

### 4.2 Queue Manager

Create: `internal/compiler/queue/manager.go`

```go
package queue

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"time"

	"github.com/redis/go-redis/v9"
	"go.mongodb.org/mongo-driver/bson/primitive"
)

// JobData represents a queued compilation job
type JobData struct {
	JobID      string    `json:"jobId"`
	ProjectID  string    `json:"projectId"`
	DocumentID string    `json:"documentId"`
	UserID     string    `json:"userId"`
	Engine     string    `json:"engine"`
	Compiler   string    `json:"compiler"`
	Priority   int       `json:"priority"`
	CreatedAt  time.Time `json:"createdAt"`
	RetryCount int       `json:"retryCount"`
}

// QueueManager manages the compilation job queue
type QueueManager struct {
	client *redis.Client
	config *QueueConfig
}

// NewQueueManager creates a new queue manager
func NewQueueManager(client *redis.Client, config *QueueConfig) *QueueManager {
	if config == nil {
		config = DefaultQueueConfig()
	}

	return &QueueManager{
		client: client,
		config: config,
	}
}

// Enqueue adds a job to the queue
func (q *QueueManager) Enqueue(ctx context.Context, job *JobData) error {
	// Serialize job
	data, err := json.Marshal(job)
	if err != nil {
		return fmt.Errorf("failed to marshal job: %w", err)
	}

	// Add to Redis sorted set (score = priority, higher is better)
	score := float64(job.Priority)
	
	err = q.client.ZAdd(ctx, q.config.QueueName, redis.Z{
		Score:  score,
		Member: data,
	}).Err()

	if err != nil {
		return fmt.Errorf("failed to enqueue job: %w", err)
	}

	log.Printf("Enqueued job %s with priority %d", job.JobID, job.Priority)
	return nil
}

// Dequeue removes and returns the highest priority job
func (q *QueueManager) Dequeue(ctx context.Context) (*JobData, error) {
	// Get highest priority job (highest score)
	result, err := q.client.ZPopMax(ctx, q.config.QueueName, 1).Result()
	if err != nil {
		return nil, fmt.Errorf("failed to dequeue: %w", err)
	}

	if len(result) == 0 {
		return nil, nil // Queue is empty
	}

	// Deserialize job
	var job JobData
	if err := json.Unmarshal([]byte(result[0].Member.(string)), &job); err != nil {
		return nil, fmt.Errorf("failed to unmarshal job: %w", err)
	}

	// Add to processing set
	if err := q.markProcessing(ctx, &job); err != nil {
		// If we can't mark as processing, re-enqueue
		q.Enqueue(ctx, &job)
		return nil, fmt.Errorf("failed to mark as processing: %w", err)
	}

	return &job, nil
}

// markProcessing marks a job as being processed
func (q *QueueManager) markProcessing(ctx context.Context, job *JobData) error {
	data, err := json.Marshal(job)
	if err != nil {
		return err
	}

	// Add to processing hash with expiration
	return q.client.HSet(ctx, q.config.ProcessingQueueName, job.JobID, data).Err()
}

// CompleteJob marks a job as completed
func (q *QueueManager) CompleteJob(ctx context.Context, jobID string) error {
	return q.client.HDel(ctx, q.config.ProcessingQueueName, jobID).Err()
}

// FailJob marks a job as failed and potentially re-queues it
func (q *QueueManager) FailJob(ctx context.Context, jobID string, reason string) error {
	// Get job from processing
	data, err := q.client.HGet(ctx, q.config.ProcessingQueueName, jobID).Result()
	if err != nil {
		return fmt.Errorf("job not found in processing: %w", err)
	}

	var job JobData
	if err := json.Unmarshal([]byte(data), &job); err != nil {
		return err
	}

	// Remove from processing
	q.client.HDel(ctx, q.config.ProcessingQueueName, jobID)

	// Check if we should retry
	if job.RetryCount < q.config.MaxRetries {
		job.RetryCount++
		log.Printf("Retrying job %s (attempt %d/%d)", jobID, job.RetryCount, q.config.MaxRetries)
		
		// Re-enqueue with delay
		time.Sleep(q.config.RetryDelay)
		return q.Enqueue(ctx, &job)
	}

	// Max retries reached, move to failed queue
	log.Printf("Job %s failed after %d attempts: %s", jobID, job.RetryCount, reason)
	failedData := map[string]interface{}{
		"job":    job,
		"reason": reason,
		"time":   time.Now(),
	}
	
	failedJSON, _ := json.Marshal(failedData)
	return q.client.HSet(ctx, q.config.FailedQueueName, jobID, failedJSON).Err()
}

// GetQueueSize returns the number of jobs in the queue
func (q *QueueManager) GetQueueSize(ctx context.Context) (int64, error) {
	return q.client.ZCard(ctx, q.config.QueueName).Result()
}

// GetProcessingCount returns the number of jobs being processed
func (q *QueueManager) GetProcessingCount(ctx context.Context) (int64, error) {
	return q.client.HLen(ctx, q.config.ProcessingQueueName).Result()
}

// GetPosition returns the position of a job in the queue (0 = next)
func (q *QueueManager) GetPosition(ctx context.Context, jobID string) (int64, error) {
	// Get all jobs sorted by priority
	jobs, err := q.client.ZRevRangeWithScores(ctx, q.config.QueueName, 0, -1).Result()
	if err != nil {
		return -1, err
	}

	// Find job position
	for i, z := range jobs {
		var job JobData
		if err := json.Unmarshal([]byte(z.Member.(string)), &job); err != nil {
			continue
		}
		if job.JobID == jobID {
			return int64(i), nil
		}
	}

	return -1, fmt.Errorf("job not found in queue")
}

// CleanupStaleJobs removes jobs that have been processing too long
func (q *QueueManager) CleanupStaleJobs(ctx context.Context) error {
	// Get all processing jobs
	jobs, err := q.client.HGetAll(ctx, q.config.ProcessingQueueName).Result()
	if err != nil {
		return err
	}

	now := time.Now()
	for jobID, data := range jobs {
		var job JobData
		if err := json.Unmarshal([]byte(data), &job); err != nil {
			continue
		}

		// If job has been processing for too long, re-queue it
		if now.Sub(job.CreatedAt) > q.config.JobTimeout {
			log.Printf("Job %s timed out, re-queueing", jobID)
			q.FailJob(ctx, jobID, "timeout")
		}
	}

	return nil
}
```

**Verification**:
```bash
go build ./internal/compiler/queue/...
```

---

## Task 5: WASM Compiler (2.5 hours)

### 5.1 WASM Compiler Interface

Create: `internal/compiler/wasm/compiler.go`

```go
package wasm

import (
	"context"
	"fmt"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"time"
)

// Compiler handles WASM-based LaTeX compilation
type Compiler struct {
	wasmPath   string
	workingDir string
}

// NewCompiler creates a new WASM compiler
func NewCompiler(wasmPath, workingDir string) *Compiler {
	return &Compiler{
		wasmPath:   wasmPath,
		workingDir: workingDir,
	}
}

// CompileOptions holds compilation options
type CompileOptions struct {
	MainFile     string
	OutputDir    string
	CompilerType string // pdflatex, xelatex, lualatex
	Timeout      time.Duration
}

// CompileResult holds compilation results
type CompileResult struct {
	Success   bool
	PDFPath   string
	LogPath   string
	LogOutput string
	Duration  time.Duration
	Error     error
}

// Compile compiles a LaTeX document using WASM
func (c *Compiler) Compile(ctx context.Context, opts *CompileOptions) (*CompileResult, error) {
	startTime := time.Now()
	result := &CompileResult{}

	// Create temporary directory for compilation
	tempDir := filepath.Join(c.workingDir, "temp", fmt.Sprintf("compile_%d", time.Now().UnixNano()))
	if err := os.MkdirAll(tempDir, 0755); err != nil {
		return nil, fmt.Errorf("failed to create temp directory: %w", err)
	}
	defer os.RemoveAll(tempDir)

	// Copy source files to temp directory
	mainTexPath := filepath.Join(tempDir, filepath.Base(opts.MainFile))
	if err := copyFile(opts.MainFile, mainTexPath); err != nil {
		return nil, fmt.Errorf("failed to copy main file: %w", err)
	}

	// Prepare command
	var cmd *exec.Cmd
	
	// For now, we'll use system pdflatex as WASM LaTeX is complex
	// In production, you would use a WASM runtime like wazero
	// to run a compiled LaTeX WASM binary
	
	switch opts.CompilerType {
	case "xelatex":
		cmd = exec.CommandContext(ctx, "xelatex",
			"-interaction=nonstopmode",
			"-halt-on-error",
			"-output-directory="+tempDir,
			mainTexPath,
		)
	case "lualatex":
		cmd = exec.CommandContext(ctx, "lualatex",
			"-interaction=nonstopmode",
			"-halt-on-error",
			"-output-directory="+tempDir,
			mainTexPath,
		)
	default: // pdflatex
		cmd = exec.CommandContext(ctx, "pdflatex",
			"-interaction=nonstopmode",
			"-halt-on-error",
			"-output-directory="+tempDir,
			mainTexPath,
		)
	}

	cmd.Dir = tempDir

	// Set timeout
	if opts.Timeout > 0 {
		ctx, cancel := context.WithTimeout(ctx, opts.Timeout)
		defer cancel()
		cmd = exec.CommandContext(ctx, cmd.Path, cmd.Args[1:]...)
	}

	// Run compilation
	output, err := cmd.CombinedOutput()
	result.LogOutput = string(output)
	result.Duration = time.Since(startTime)

	// Check for PDF output
	baseName := filepath.Base(opts.MainFile)
	baseName = baseName[:len(baseName)-4] // Remove .tex
	pdfPath := filepath.Join(tempDir, baseName+".pdf")
	logPath := filepath.Join(tempDir, baseName+".log")

	if _, err := os.Stat(pdfPath); err == nil {
		// PDF was generated
		result.Success = true
		result.PDFPath = pdfPath
		
		// Copy PDF to output directory
		outputPDF := filepath.Join(opts.OutputDir, baseName+".pdf")
		if err := copyFile(pdfPath, outputPDF); err != nil {
			return nil, fmt.Errorf("failed to copy PDF: %w", err)
		}
		result.PDFPath = outputPDF
	} else {
		result.Success = false
		result.Error = fmt.Errorf("PDF not generated: %w", err)
	}

	// Copy log file
	if _, err := os.Stat(logPath); err == nil {
		outputLog := filepath.Join(opts.OutputDir, baseName+".log")
		if err := copyFile(logPath, outputLog); err != nil {
			log.Printf("Warning: failed to copy log file: %v", err)
		}
		result.LogPath = outputLog
	}

	log.Printf("WASM compilation completed in %v, success=%v", result.Duration, result.Success)
	return result, nil
}

// IsAvailable checks if WASM compiler is available
func (c *Compiler) IsAvailable() bool {
	// Check if pdflatex is available
	_, err := exec.LookPath("pdflatex")
	return err == nil
}

// copyFile copies a file from src to dst
func copyFile(src, dst string) error {
	input, err := os.ReadFile(src)
	if err != nil {
		return err
	}

	err = os.WriteFile(dst, input, 0644)
	if err != nil {
		return err
	}

	return nil
}
```

**Verification**:
```bash
go build ./internal/compiler/wasm/...
```

---

## Task 6: Docker Compiler (2.5 hours)

### 6.1 Docker Compiler

Create: `internal/compiler/docker/compiler.go`

```go
package docker

import (
	"archive/tar"
	"bytes"
	"context"
	"fmt"
	"io"
	"log"
	"os"
	"path/filepath"
	"time"

	"github.com/docker/docker/api/types"
	"github.com/docker/docker/api/types/container"
	"github.com/docker/docker/client"
	"github.com/docker/docker/pkg/stdcopy"
)

// Compiler handles Docker-based LaTeX compilation
type Compiler struct {
	client     *client.Client
	image      string
	workingDir string
}

// NewCompiler creates a new Docker compiler
func NewCompiler(dockerImage, workingDir string) (*Compiler, error) {
	cli, err := client.NewClientWithOpts(client.FromEnv, client.WithAPIVersionNegotiation())
	if err != nil {
		return nil, fmt.Errorf("failed to create Docker client: %w", err)
	}

	if dockerImage == "" {
		dockerImage = "texlive/texlive:latest"
	}

	return &Compiler{
		client:     cli,
		image:      dockerImage,
		workingDir: workingDir,
	}, nil
}

// CompileOptions holds compilation options
type CompileOptions struct {
	ProjectDir   string
	MainFile     string
	OutputDir    string
	CompilerType string
	Timeout      time.Duration
	BibtexRuns   int
}

// CompileResult holds compilation results
type CompileResult struct {
	Success   bool
	PDFPath   string
	LogPath   string
	LogOutput string
	Duration  time.Duration
	Error     error
}

// Compile compiles a LaTeX document using Docker
func (c *Compiler) Compile(ctx context.Context, opts *CompileOptions) (*CompileResult, error) {
	startTime := time.Now()
	result := &CompileResult{}

	// Ensure image is available
	if err := c.ensureImage(ctx); err != nil {
		return nil, fmt.Errorf("failed to ensure Docker image: %w", err)
	}

	// Create temporary container directory
	tempDir := filepath.Join(c.workingDir, "docker_temp", fmt.Sprintf("compile_%d", time.Now().UnixNano()))
	if err := os.MkdirAll(tempDir, 0755); err != nil {
		return nil, fmt.Errorf("failed to create temp directory: %w", err)
	}
	defer os.RemoveAll(tempDir)

	// Copy project files to temp directory
	if err := copyDir(opts.ProjectDir, tempDir); err != nil {
		return nil, fmt.Errorf("failed to copy project files: %w", err)
	}

	// Build compilation command
	compileCmd := c.buildCompileCommand(opts)

	// Create container
	containerConfig := &container.Config{
		Image:      c.image,
		Cmd:        compileCmd,
		WorkingDir: "/work",
		Tty:        false,
	}

	hostConfig := &container.HostConfig{
		Binds: []string{
			fmt.Sprintf("%s:/work", tempDir),
		},
		AutoRemove: true,
	}

	// Set timeout
	if opts.Timeout > 0 {
		var cancel context.CancelFunc
		ctx, cancel = context.WithTimeout(ctx, opts.Timeout)
		defer cancel()
	}

	// Create container
	resp, err := c.client.ContainerCreate(ctx, containerConfig, hostConfig, nil, nil, "")
	if err != nil {
		return nil, fmt.Errorf("failed to create container: %w", err)
	}

	// Start container
	if err := c.client.ContainerStart(ctx, resp.ID, types.ContainerStartOptions{}); err != nil {
		return nil, fmt.Errorf("failed to start container: %w", err)
	}

	// Wait for container to finish
	statusCh, errCh := c.client.ContainerWait(ctx, resp.ID, container.WaitConditionNotRunning)
	select {
	case err := <-errCh:
		if err != nil {
			return nil, fmt.Errorf("error waiting for container: %w", err)
		}
	case <-statusCh:
	}

	// Get logs
	out, err := c.client.ContainerLogs(ctx, resp.ID, types.ContainerLogsOptions{
		ShowStdout: true,
		ShowStderr: true,
	})
	if err != nil {
		log.Printf("Warning: failed to get container logs: %v", err)
	} else {
		defer out.Close()
		
		var stdout, stderr bytes.Buffer
		stdcopy.StdCopy(&stdout, &stderr, out)
		result.LogOutput = stdout.String() + stderr.String()
	}

	result.Duration = time.Since(startTime)

	// Check for PDF output
	baseName := filepath.Base(opts.MainFile)
	baseName = baseName[:len(baseName)-4] // Remove .tex
	pdfPath := filepath.Join(tempDir, baseName+".pdf")
	logPath := filepath.Join(tempDir, baseName+".log")

	if _, err := os.Stat(pdfPath); err == nil {
		// PDF was generated
		result.Success = true
		
		// Copy PDF to output directory
		outputPDF := filepath.Join(opts.OutputDir, baseName+".pdf")
		if err := copyFile(pdfPath, outputPDF); err != nil {
			return nil, fmt.Errorf("failed to copy PDF: %w", err)
		}
		result.PDFPath = outputPDF
	} else {
		result.Success = false
		result.Error = fmt.Errorf("PDF not generated")
	}

	// Copy log file
	if _, err := os.Stat(logPath); err == nil {
		outputLog := filepath.Join(opts.OutputDir, baseName+".log")
		if err := copyFile(logPath, outputLog); err != nil {
			log.Printf("Warning: failed to copy log file: %v", err)
		}
		result.LogPath = outputLog
	}

	log.Printf("Docker compilation completed in %v, success=%v", result.Duration, result.Success)
	return result, nil
}

// buildCompileCommand builds the compilation command
func (c *Compiler) buildCompileCommand(opts *CompileOptions) []string {
	var cmd []string

	compiler := "pdflatex"
	switch opts.CompilerType {
	case "xelatex":
		compiler = "xelatex"
	case "lualatex":
		compiler = "lualatex"
	}

	mainFile := filepath.Base(opts.MainFile)

	// First compilation pass
	cmd = append(cmd, "/bin/sh", "-c")
	
	script := fmt.Sprintf("%s -interaction=nonstopmode -halt-on-error %s", compiler, mainFile)
	
	// If bibtex is needed
	if opts.BibtexRuns > 0 {
		baseName := mainFile[:len(mainFile)-4]
		script += fmt.Sprintf(" && bibtex %s", baseName)
		script += fmt.Sprintf(" && %s -interaction=nonstopmode %s", compiler, mainFile)
		script += fmt.Sprintf(" && %s -interaction=nonstopmode %s", compiler, mainFile)
	}

	cmd = append(cmd, script)
	return cmd
}

// ensureImage ensures the Docker image is available
func (c *Compiler) ensureImage(ctx context.Context) error {
	images, err := c.client.ImageList(ctx, types.ImageListOptions{})
	if err != nil {
		return err
	}

	// Check if image exists
	for _, image := range images {
		for _, tag := range image.RepoTags {
			if tag == c.image {
				return nil
			}
		}
	}

	// Pull image
	log.Printf("Pulling Docker image: %s", c.image)
	out, err := c.client.ImagePull(ctx, c.image, types.ImagePullOptions{})
	if err != nil {
		return err
	}
	defer out.Close()

	// Wait for pull to complete
	io.Copy(io.Discard, out)
	log.Printf("Docker image pulled successfully")
	return nil
}

// IsAvailable checks if Docker is available
func (c *Compiler) IsAvailable() bool {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	_, err := c.client.Ping(ctx)
	return err == nil
}

// copyFile copies a file
func copyFile(src, dst string) error {
	input, err := os.ReadFile(src)
	if err != nil {
		return err
	}
	return os.WriteFile(dst, input, 0644)
}

// copyDir recursively copies a directory
func copyDir(src, dst string) error {
	return filepath.Walk(src, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}

		relPath, err := filepath.Rel(src, path)
		if err != nil {
			return err
		}

		dstPath := filepath.Join(dst, relPath)

		if info.IsDir() {
			return os.MkdirAll(dstPath, info.Mode())
		}

		return copyFile(path, dstPath)
	})
}
```

### 6.2 Docker Image

Create: `docker/latex-compiler/Dockerfile`

```dockerfile
FROM texlive/texlive:latest

# Install additional tools
RUN apt-get update && apt-get install -y \
    biber \
    latexmk \
    python3-pygments \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /work

# Default command
CMD ["/bin/bash"]
```

**Verification**:
```bash
# Build Docker image
cd docker/latex-compiler
docker build -t gogolatex-compiler .

# Test
docker run --rm gogolatex-compiler pdflatex --version
```

---

## Task 7: Compilation Service (3 hours)

### 7.1 Compilation Repository

Create: `internal/compiler/repository/compilation_repository.go`

```go
package repository

import (
	"context"
	"fmt"
	"time"

	"github.com/yourusername/gogolatex/internal/models"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
)

// CompilationRepository handles compilation job database operations
type CompilationRepository struct {
	collection *mongo.Collection
}

// NewCompilationRepository creates a new compilation repository
func NewCompilationRepository(db *mongo.Database) *CompilationRepository {
	collection := db.Collection("compilation_jobs")

	// Create indexes
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	// Index on projectId for finding project compilations
	collection.Indexes().CreateOne(ctx, mongo.IndexModel{
		Keys: bson.D{{Key: "projectId", Value: 1}},
	})

	// Index on userId for user history
	collection.Indexes().CreateOne(ctx, mongo.IndexModel{
		Keys: bson.D{{Key: "userId", Value: 1}},
	})

	// Index on status for queue management
	collection.Indexes().CreateOne(ctx, mongo.IndexModel{
		Keys: bson.D{{Key: "status", Value: 1}},
	})

	// Compound index on projectId and createdAt for recent jobs
	collection.Indexes().CreateOne(ctx, mongo.IndexModel{
		Keys: bson.D{
			{Key: "projectId", Value: 1},
			{Key: "createdAt", Value: -1},
		},
	})

	return &CompilationRepository{
		collection: collection,
	}
}

// Create creates a new compilation job
func (r *CompilationRepository) Create(ctx context.Context, job *models.CompilationJob) error {
	job.CreatedAt = time.Now()
	job.Status = models.StatusPending

	result, err := r.collection.InsertOne(ctx, job)
	if err != nil {
		return fmt.Errorf("failed to create compilation job: %w", err)
	}

	job.ID = result.InsertedID.(primitive.ObjectID)
	return nil
}

// FindByID finds a compilation job by ID
func (r *CompilationRepository) FindByID(ctx context.Context, id primitive.ObjectID) (*models.CompilationJob, error) {
	var job models.CompilationJob
	err := r.collection.FindOne(ctx, bson.M{"_id": id}).Decode(&job)
	if err != nil {
		if err == mongo.ErrNoDocuments {
			return nil, fmt.Errorf("compilation job not found")
		}
		return nil, fmt.Errorf("failed to find compilation job: %w", err)
	}

	return &job, nil
}

// FindByProjectID finds all compilation jobs for a project
func (r *CompilationRepository) FindByProjectID(ctx context.Context, projectID primitive.ObjectID, limit int64) ([]models.CompilationJob, error) {
	opts := options.Find().
		SetSort(bson.D{{Key: "createdAt", Value: -1}}).
		SetLimit(limit)

	cursor, err := r.collection.Find(ctx, bson.M{"projectId": projectID}, opts)
	if err != nil {
		return nil, fmt.Errorf("failed to find compilation jobs: %w", err)
	}
	defer cursor.Close(ctx)

	var jobs []models.CompilationJob
	if err := cursor.All(ctx, &jobs); err != nil {
		return nil, fmt.Errorf("failed to decode compilation jobs: %w", err)
	}

	return jobs, nil
}

// FindLatestByProject finds the most recent compilation for a project
func (r *CompilationRepository) FindLatestByProject(ctx context.Context, projectID primitive.ObjectID) (*models.CompilationJob, error) {
	opts := options.FindOne().SetSort(bson.D{{Key: "createdAt", Value: -1}})

	var job models.CompilationJob
	err := r.collection.FindOne(ctx, bson.M{
		"projectId": projectID,
		"status":    models.StatusSuccess,
	}, opts).Decode(&job)

	if err != nil {
		if err == mongo.ErrNoDocuments {
			return nil, nil // No successful compilation yet
		}
		return nil, err
	}

	return &job, nil
}

// UpdateStatus updates the status of a compilation job
func (r *CompilationRepository) UpdateStatus(ctx context.Context, id primitive.ObjectID, status string) error {
	update := bson.M{
		"status": status,
	}

	if status == models.StatusProcessing {
		now := time.Now()
		update["startedAt"] = now
	} else if status == models.StatusSuccess || status == models.StatusFailed {
		now := time.Now()
		update["completedAt"] = now
	}

	_, err := r.collection.UpdateOne(
		ctx,
		bson.M{"_id": id},
		bson.M{"$set": update},
	)

	return err
}

// UpdateResult updates the compilation result
func (r *CompilationRepository) UpdateResult(ctx context.Context, id primitive.ObjectID, result map[string]interface{}) error {
	_, err := r.collection.UpdateOne(
		ctx,
		bson.M{"_id": id},
		bson.M{"$set": result},
	)
	return err
}

// GetStatistics returns compilation statistics
func (r *CompilationRepository) GetStatistics(ctx context.Context) (*models.CompilationStats, error) {
	stats := &models.CompilationStats{}

	// Total jobs
	total, _ := r.collection.CountDocuments(ctx, bson.M{})
	stats.TotalJobs = total

	// Count by status
	statuses := []string{models.StatusSuccess, models.StatusFailed, models.StatusPending, models.StatusProcessing}
	for _, status := range statuses {
		count, _ := r.collection.CountDocuments(ctx, bson.M{"status": status})
		switch status {
		case models.StatusSuccess:
			stats.SuccessfulJobs = count
		case models.StatusFailed:
			stats.FailedJobs = count
		case models.StatusPending:
			stats.PendingJobs = count
		case models.StatusProcessing:
			stats.ProcessingJobs = count
		}
	}

	// Average duration (only successful jobs)
	pipeline := mongo.Pipeline{
		{{Key: "$match", Value: bson.M{
			"status":   models.StatusSuccess,
			"duration": bson.M{"$exists": true},
		}}},
		{{Key: "$group", Value: bson.M{
			"_id":             nil,
			"averageDuration": bson.M{"$avg": "$duration"},
		}}},
	}

	cursor, err := r.collection.Aggregate(ctx, pipeline)
	if err == nil {
		defer cursor.Close(ctx)
		if cursor.Next(ctx) {
			var result struct {
				AverageDuration float64 `bson:"averageDuration"`
			}
			if err := cursor.Decode(&result); err == nil {
				stats.AverageDuration = time.Duration(result.AverageDuration) * time.Millisecond
			}
		}
	}

	// Count by engine
	wasmCount, _ := r.collection.CountDocuments(ctx, bson.M{"actualEngine": models.EngineWASM})
	dockerCount, _ := r.collection.CountDocuments(ctx, bson.M{"actualEngine": models.EngineDocker})
	stats.WASMJobs = wasmCount
	stats.DockerJobs = dockerCount

	return stats, nil
}
```

### 7.2 Compilation Service

Create: `internal/compiler/service/compilation_service.go`

```go
package service

import (
	"context"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"time"

	"github.com/google/uuid"
	"github.com/yourusername/gogolatex/internal/compiler/docker"
	"github.com/yourusername/gogolatex/internal/compiler/parser"
	"github.com/yourusername/gogolatex/internal/compiler/queue"
	"github.com/yourusername/gogolatex/internal/compiler/repository"
	"github.com/yourusername/gogolatex/internal/compiler/wasm"
	"github.com/yourusername/gogolatex/internal/models"
	"github.com/yourusername/gogolatex/internal/storage"
	"go.mongodb.org/mongo-driver/bson/primitive"
)

// CompilationService handles compilation business logic
type CompilationService struct {
	repo            *repository.CompilationRepository
	queueManager    *queue.QueueManager
	wasmCompiler    *wasm.Compiler
	dockerCompiler  *docker.Compiler
	storage         *storage.MinIOStorage
	parser          *parser.LogParser
	packageDetector *parser.PackageDetector
	workingDir      string
}

// NewCompilationService creates a new compilation service
func NewCompilationService(
	repo *repository.CompilationRepository,
	queueManager *queue.QueueManager,
	storage *storage.MinIOStorage,
	workingDir string,
) (*CompilationService, error) {
	// Initialize compilers
	wasmCompiler := wasm.NewCompiler("", filepath.Join(workingDir, "wasm"))
	dockerCompiler, err := docker.NewCompiler("gogolatex-compiler", workingDir)
	if err != nil {
		log.Printf("Warning: Docker compiler not available: %v", err)
	}

	return &CompilationService{
		repo:            repo,
		queueManager:    queueManager,
		wasmCompiler:    wasmCompiler,
		dockerCompiler:  dockerCompiler,
		storage:         storage,
		parser:          parser.NewLogParser(),
		packageDetector: parser.NewPackageDetector(),
		workingDir:      workingDir,
	}, nil
}

// CreateCompilation creates a new compilation job
func (s *CompilationService) CreateCompilation(ctx context.Context, req *models.CreateCompilationRequest, userID string) (*models.CompilationJob, error) {
	// Create job record
	job := &models.CompilationJob{
		ProjectID:    req.ProjectID,
		DocumentID:   req.DocumentID,
		UserID:       userID,
		Engine:       req.Engine,
		CompilerType: req.CompilerType,
		Priority:     req.Priority,
		MaxRetries:   3,
		RetryCount:   0,
	}

	// Set defaults
	if job.Engine == "" {
		job.Engine = models.EngineAuto
	}
	if job.CompilerType == "" {
		job.CompilerType = models.CompilerPDFLaTeX
	}

	// Save to database
	if err := s.repo.Create(ctx, job); err != nil {
		return nil, err
	}

	// Enqueue job
	queueJob := &queue.JobData{
		JobID:      job.ID.Hex(),
		ProjectID:  job.ProjectID.Hex(),
		DocumentID: job.DocumentID.Hex(),
		UserID:     userID,
		Engine:     job.Engine,
		Compiler:   job.CompilerType,
		Priority:   job.Priority,
		CreatedAt:  job.CreatedAt,
	}

	if err := s.queueManager.Enqueue(ctx, queueJob); err != nil {
		return nil, fmt.Errorf("failed to enqueue job: %w", err)
	}

	log.Printf("Created compilation job %s for project %s", job.ID.Hex(), req.ProjectID.Hex())
	return job, nil
}

// ProcessNextJob processes the next job in the queue
func (s *CompilationService) ProcessNextJob(ctx context.Context) error {
	// Dequeue job
	queueJob, err := s.queueManager.Dequeue(ctx)
	if err != nil {
		return err
	}

	if queueJob == nil {
		return nil // Queue is empty
	}

	// Get job from database
	jobID, err := primitive.ObjectIDFromHex(queueJob.JobID)
	if err != nil {
		return err
	}

	job, err := s.repo.FindByID(ctx, jobID)
	if err != nil {
		s.queueManager.FailJob(ctx, queueJob.JobID, err.Error())
		return err
	}

	// Update status to processing
	s.repo.UpdateStatus(ctx, job.ID, models.StatusProcessing)

	// Process compilation
	if err := s.processCompilation(ctx, job); err != nil {
		log.Printf("Compilation failed: %v", err)
		s.repo.UpdateStatus(ctx, job.ID, models.StatusFailed)
		s.queueManager.FailJob(ctx, queueJob.JobID, err.Error())
		return err
	}

	// Mark as complete
	s.repo.UpdateStatus(ctx, job.ID, models.StatusSuccess)
	s.queueManager.CompleteJob(ctx, queueJob.JobID)

	return nil
}

// processCompilation performs the actual compilation
func (s *CompilationService) processCompilation(ctx context.Context, job *models.CompilationJob) error {
	startTime := time.Now()

	// TODO: Download project files from MinIO/MongoDB
	// For now, assume files are in working directory
	projectDir := filepath.Join(s.workingDir, "projects", job.ProjectID.Hex())
	outputDir := filepath.Join(s.workingDir, "output", job.ID.Hex())
	os.MkdirAll(outputDir, 0755)

	// Determine which engine to use
	engine := job.Engine
	if engine == models.EngineAuto {
		// Auto-detect based on document content
		// For now, default to WASM
		engine = models.EngineWASM
		
		// TODO: Load document content and detect packages
		// packages := s.packageDetector.DetectPackages(content)
		// if s.packageDetector.RequiresFullTexLive(packages) {
		//     engine = models.EngineDocker
		// }
	}

	var result interface{}
	var err error

	// Compile based on engine
	if engine == models.EngineWASM && s.wasmCompiler.IsAvailable() {
		job.ActualEngine = models.EngineWASM
		result, err = s.wasmCompiler.Compile(ctx, &wasm.CompileOptions{
			MainFile:     filepath.Join(projectDir, "main.tex"),
			OutputDir:    outputDir,
			CompilerType: job.CompilerType,
			Timeout:      3 * time.Minute,
		})
	} else if s.dockerCompiler != nil && s.dockerCompiler.IsAvailable() {
		job.ActualEngine = models.EngineDocker
		result, err = s.dockerCompiler.Compile(ctx, &docker.CompileOptions{
			ProjectDir:   projectDir,
			MainFile:     "main.tex",
			OutputDir:    outputDir,
			CompilerType: job.CompilerType,
			Timeout:      5 * time.Minute,
			BibtexRuns:   0,
		})
	} else {
		return fmt.Errorf("no compiler available")
	}

	if err != nil {
		return err
	}

	// Process result based on type
	var compileResult interface {
		Success bool
		PDFPath string
		LogPath string
		LogOutput string
		Duration time.Duration
		Error error
	}

	switch v := result.(type) {
	case *wasm.CompileResult:
		compileResult = v
	case *docker.CompileResult:
		compileResult = v
	default:
		return fmt.Errorf("unknown result type")
	}

	// Parse log
	errors, warnings := s.parser.ParseLog(compileResult.LogOutput)

	// Upload PDF to MinIO if successful
	if compileResult.Success && compileResult.PDFPath != "" {
		pdfKey := fmt.Sprintf("compilations/%s/%s.pdf", job.ProjectID.Hex(), job.ID.Hex())
		file, err := os.Open(compileResult.PDFPath)
		if err == nil {
			defer file.Close()
			stat, _ := file.Stat()
			s.storage.UploadFile(ctx, pdfKey, file, stat.Size(), "application/pdf")
			job.OutputPDFKey = pdfKey
		}
	}

	// Upload log to MinIO
	if compileResult.LogPath != "" {
		logKey := fmt.Sprintf("compilations/%s/%s.log", job.ProjectID.Hex(), job.ID.Hex())
		file, err := os.Open(compileResult.LogPath)
		if err == nil {
			defer file.Close()
			stat, _ := file.Stat()
			s.storage.UploadFile(ctx, logKey, file, stat.Size(), "text/plain")
			job.OutputLogKey = logKey
		}
	}

	// Update job with results
	job.Duration = time.Since(startTime).Milliseconds()
	job.Errors = errors
	job.Warnings = warnings

	s.repo.UpdateResult(ctx, job.ID, map[string]interface{}{
		"actualEngine":  job.ActualEngine,
		"duration":      job.Duration,
		"outputPdfKey":  job.OutputPDFKey,
		"outputLogKey":  job.OutputLogKey,
		"errors":        errors,
		"warnings":      warnings,
	})

	if !compileResult.Success {
		return fmt.Errorf("compilation failed with %d errors", len(errors))
	}

	log.Printf("Compilation completed successfully in %v", compileResult.Duration)
	return nil
}

// GetCompilation gets a compilation job
func (s *CompilationService) GetCompilation(ctx context.Context, jobID primitive.ObjectID) (*models.CompilationStatusResponse, error) {
	job, err := s.repo.FindByID(ctx, jobID)
	if err != nil {
		return nil, err
	}

	response := &models.CompilationStatusResponse{
		Job: job,
	}

	// Calculate progress
	switch job.Status {
	case models.StatusPending:
		response.Progress = 0
		// Get queue position
		if pos, err := s.queueManager.GetPosition(ctx, jobID.Hex()); err == nil {
			response.QueueSize = int(pos)
		}
	case models.StatusProcessing:
		response.Progress = 50
	case models.StatusSuccess:
		response.Progress = 100
	case models.StatusFailed:
		response.Progress = 0
	}

	// Generate presigned URLs
	if job.OutputPDFKey != "" {
		url, err := s.storage.GetPresignedURL(ctx, job.OutputPDFKey, 1*time.Hour)
		if err == nil {
			response.PDFUrl = url
		}
	}

	if job.OutputLogKey != "" {
		url, err := s.storage.GetPresignedURL(ctx, job.OutputLogKey, 1*time.Hour)
		if err == nil {
			response.LogUrl = url
		}
	}

	return response, nil
}

// GetProjectCompilations gets compilation history for a project
func (s *CompilationService) GetProjectCompilations(ctx context.Context, projectID primitive.ObjectID, limit int64) ([]models.CompilationJob, error) {
	return s.repo.FindByProjectID(ctx, projectID, limit)
}

// GetStatistics returns compilation statistics
func (s *CompilationService) GetStatistics(ctx context.Context) (*models.CompilationStats, error) {
	return s.repo.GetStatistics(ctx)
}
```

**Verification**:
```bash
go build ./internal/compiler/service/...
```

---

## Task 8: HTTP Handlers & Routes (2 hours)

### 8.1 Compilation Handler

Create: `internal/compiler/handler/compilation_handler.go`

```go
package handler

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/go-playground/validator/v10"
	"github.com/yourusername/gogolatex/internal/compiler/service"
	"github.com/yourusername/gogolatex/internal/models"
	"go.mongodb.org/mongo-driver/bson/primitive"
)

// CompilationHandler handles compilation HTTP requests
type CompilationHandler struct {
	service  *service.CompilationService
	validate *validator.Validate
}

// NewCompilationHandler creates a new compilation handler
func NewCompilationHandler(service *service.CompilationService) *CompilationHandler {
	return &CompilationHandler{
		service:  service,
		validate: validator.New(),
	}
}

// CreateCompilation godoc
// @Summary Create a new compilation job
// @Tags compilation
// @Accept json
// @Produce json
// @Param request body models.CreateCompilationRequest true "Compilation request"
// @Success 201 {object} models.CompilationJob
// @Router /api/compile [post]
func (h *CompilationHandler) CreateCompilation(c *gin.Context) {
	var req models.CreateCompilationRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if err := h.validate.Struct(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	userID := c.GetString("userID")
	job, err := h.service.CreateCompilation(c.Request.Context(), &req, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, job)
}

// GetCompilation godoc
// @Summary Get compilation status
// @Tags compilation
// @Produce json
// @Param id path string true "Compilation Job ID"
// @Success 200 {object} models.CompilationStatusResponse
// @Router /api/compile/{id} [get]
func (h *CompilationHandler) GetCompilation(c *gin.Context) {
	id, err := primitive.ObjectIDFromHex(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid job ID"})
		return
	}

	status, err := h.service.GetCompilation(c.Request.Context(), id)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, status)
}

// GetProjectCompilations godoc
// @Summary Get compilation history for a project
// @Tags compilation
// @Produce json
// @Param projectId query string true "Project ID"
// @Param limit query int false "Limit" default(20)
// @Success 200 {array} models.CompilationJob
// @Router /api/compile/project [get]
func (h *CompilationHandler) GetProjectCompilations(c *gin.Context) {
	projectID, err := primitive.ObjectIDFromHex(c.Query("projectId"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid project ID"})
		return
	}

	limit := int64(20)
	if limitStr := c.Query("limit"); limitStr != "" {
		if l, err := primitive.ParseInt(limitStr, 10, 64); err == nil {
			limit = int64(l)
		}
	}

	jobs, err := h.service.GetProjectCompilations(c.Request.Context(), projectID, limit)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, jobs)
}

// GetStatistics godoc
// @Summary Get compilation statistics
// @Tags compilation
// @Produce json
// @Success 200 {object} models.CompilationStats
// @Router /api/compile/stats [get]
func (h *CompilationHandler) GetStatistics(c *gin.Context) {
	stats, err := h.service.GetStatistics(c.Request.Context())
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, stats)
}
```

**Verification**:
```bash
go build ./internal/compiler/handler/...
```

---

## Task 9: Main Server & Worker Pool (2.5 hours)

### 9.1 Worker Pool

Create: `internal/compiler/worker/pool.go`

```go
package worker

import (
	"context"
	"log"
	"sync"
	"time"

	"github.com/yourusername/gogolatex/internal/compiler/service"
)

// Pool manages compilation worker goroutines
type Pool struct {
	service     *service.CompilationService
	numWorkers  int
	stopChan    chan struct{}
	wg          sync.WaitGroup
	pollInterval time.Duration
}

// NewPool creates a new worker pool
func NewPool(service *service.CompilationService, numWorkers int) *Pool {
	if numWorkers <= 0 {
		numWorkers = 4
	}

	return &Pool{
		service:      service,
		numWorkers:   numWorkers,
		stopChan:     make(chan struct{}),
		pollInterval: 2 * time.Second,
	}
}

// Start starts the worker pool
func (p *Pool) Start() {
	log.Printf("Starting worker pool with %d workers", p.numWorkers)

	for i := 0; i < p.numWorkers; i++ {
		p.wg.Add(1)
		go p.worker(i)
	}
}

// Stop stops the worker pool gracefully
func (p *Pool) Stop() {
	log.Println("Stopping worker pool...")
	close(p.stopChan)
	p.wg.Wait()
	log.Println("Worker pool stopped")
}

// worker processes jobs from the queue
func (p *Pool) worker(id int) {
	defer p.wg.Done()

	log.Printf("Worker %d started", id)

	ticker := time.NewTicker(p.pollInterval)
	defer ticker.Stop()

	for {
		select {
		case <-p.stopChan:
			log.Printf("Worker %d stopping", id)
			return

		case <-ticker.C:
			// Try to process next job
			ctx, cancel := context.WithTimeout(context.Background(), 10*time.Minute)
			err := p.service.ProcessNextJob(ctx)
			cancel()

			if err != nil {
				// Only log if it's not an empty queue
				if err.Error() != "queue is empty" {
					log.Printf("Worker %d error: %v", id, err)
				}
			}
		}
	}
}
```

### 9.2 Environment Configuration

Create: `cmd/compiler/.env.example`

```env
# Server
PORT=5003

# MongoDB
MONGODB_URI=mongodb://localhost:27017,localhost:27018,localhost:27019/?replicaSet=rs0
MONGODB_DATABASE=gogolatex

# Redis
REDIS_ADDR=localhost:6379
REDIS_PASSWORD=changeme_redis
REDIS_DB=0

# MinIO
MINIO_ENDPOINT=localhost:9000
MINIO_ACCESS_KEY=minioadmin
MINIO_SECRET_KEY=minioadmin
MINIO_BUCKET=gogolatex
MINIO_USE_SSL=false
MINIO_REGION=us-east-1

# JWT
JWT_SECRET=your-secret-key-change-in-production

# CORS
ALLOWED_ORIGINS=http://localhost:3000,http://localhost:8080

# Compilation
WORKING_DIR=/tmp/gogolatex-compiler
NUM_WORKERS=4
DOCKER_IMAGE=gogolatex-compiler
```

### 9.3 Main Server

Create: `cmd/compiler/main.go`

```go
package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/gin-contrib/cors"
	"github.com/gin-gonic/gin"
	"github.com/joho/godotenv"
	"github.com/redis/go-redis/v9"
	"github.com/yourusername/gogolatex/internal/compiler/handler"
	compilerRepo "github.com/yourusername/gogolatex/internal/compiler/repository"
	"github.com/yourusername/gogolatex/internal/compiler/queue"
	"github.com/yourusername/gogolatex/internal/compiler/service"
	"github.com/yourusername/gogolatex/internal/compiler/worker"
	"github.com/yourusername/gogolatex/internal/database"
	"github.com/yourusername/gogolatex/internal/storage"
	"github.com/yourusername/gogolatex/pkg/middleware"
	"strconv"
)

func main() {
	// Load .env file
	if err := godotenv.Load(); err != nil {
		log.Println("No .env file found, using environment variables")
	}

	// Connect to MongoDB
	mongoURI := os.Getenv("MONGODB_URI")
	dbName := os.Getenv("MONGODB_DATABASE")
	db, err := database.ConnectMongoDB(mongoURI, dbName)
	if err != nil {
		log.Fatal("Failed to connect to MongoDB:", err)
	}
	log.Println("Connected to MongoDB")

	// Connect to Redis
	redisClient := redis.NewClient(&redis.Options{
		Addr:     os.Getenv("REDIS_ADDR"),
		Password: os.Getenv("REDIS_PASSWORD"),
		DB:       0,
	})

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if err := redisClient.Ping(ctx).Err(); err != nil {
		log.Fatal("Failed to connect to Redis:", err)
	}
	log.Println("Connected to Redis")

	// Initialize MinIO
	minioConfig := storage.LoadMinIOConfig()
	minioStorage, err := storage.NewMinIOStorage(minioConfig)
	if err != nil {
		log.Fatal("Failed to initialize MinIO:", err)
	}
	log.Println("MinIO storage initialized")

	// Initialize repositories
	compilationRepo := compilerRepo.NewCompilationRepository(db)

	// Initialize queue manager
	queueConfig := queue.DefaultQueueConfig()
	queueManager := queue.NewQueueManager(redisClient, queueConfig)

	// Initialize service
	workingDir := os.Getenv("WORKING_DIR")
	if workingDir == "" {
		workingDir = "/tmp/gogolatex-compiler"
	}
	os.MkdirAll(workingDir, 0755)

	compilationService, err := service.NewCompilationService(
		compilationRepo,
		queueManager,
		minioStorage,
		workingDir,
	)
	if err != nil {
		log.Fatal("Failed to initialize compilation service:", err)
	}

	// Initialize handler
	compilationHandler := handler.NewCompilationHandler(compilationService)

	// Start worker pool
	numWorkers, _ := strconv.Atoi(os.Getenv("NUM_WORKERS"))
	if numWorkers == 0 {
		numWorkers = 4
	}
	workerPool := worker.NewPool(compilationService, numWorkers)
	workerPool.Start()

	// Setup Gin router
	router := gin.Default()

	// CORS middleware
	router.Use(cors.New(cors.Config{
		AllowOrigins:     []string{os.Getenv("ALLOWED_ORIGINS")},
		AllowMethods:     []string{"GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"},
		AllowHeaders:     []string{"Origin", "Content-Type", "Authorization"},
		ExposeHeaders:    []string{"Content-Length"},
		AllowCredentials: true,
		MaxAge:           12 * time.Hour,
	}))

	// Health check
	router.GET("/health", func(c *gin.Context) {
		queueSize, _ := queueManager.GetQueueSize(c.Request.Context())
		processingCount, _ := queueManager.GetProcessingCount(c.Request.Context())

		c.JSON(http.StatusOK, gin.H{
			"status":          "healthy",
			"service":         "compilation-service",
			"time":            time.Now(),
			"queueSize":       queueSize,
			"processingCount": processingCount,
			"numWorkers":      numWorkers,
		})
	})

	// API routes with authentication
	authMiddleware := middleware.AuthMiddleware(os.Getenv("JWT_SECRET"))
	api := router.Group("/api", authMiddleware)
	{
		compile := api.Group("/compile")
		{
			compile.POST("", compilationHandler.CreateCompilation)
			compile.GET("/:id", compilationHandler.GetCompilation)
			compile.GET("/project", compilationHandler.GetProjectCompilations)
			compile.GET("/stats", compilationHandler.GetStatistics)
		}
	}

	// Start server
	port := os.Getenv("PORT")
	if port == "" {
		port = "5003"
	}

	srv := &http.Server{
		Addr:         ":" + port,
		Handler:      router,
		ReadTimeout:  30 * time.Second,
		WriteTimeout: 30 * time.Second,
		IdleTimeout:  120 * time.Second,
	}

	// Graceful shutdown
	go func() {
		log.Printf("Compilation service listening on port %s", port)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatal("Failed to start server:", err)
		}
	}()

	// Wait for interrupt signal
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	log.Println("Shutting down server...")

	// Stop worker pool
	workerPool.Stop()

	// Shutdown HTTP server
	ctx, cancel = context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	if err := srv.Shutdown(ctx); err != nil {
		log.Fatal("Server forced to shutdown:", err)
	}

	log.Println("Server exited")
}
```

**Verification**:
```bash
cd cmd/compiler
cp .env.example .env
# Edit .env with your values

# Build
go build -o compiler-service

# Run
./compiler-service
```

---

## Task 10: Docker Configuration & Testing (1.5 hours)

### 10.1 Update docker-compose.yml

Add compilation service to: `docker-compose.yml`

```yaml
services:
  # ... existing services ...

  gogolatex-compiler-service:
    build:
      context: ./backend/go-services
      dockerfile: ../../docker/go-services/Dockerfile
      args:
        SERVICE_NAME: compiler
    container_name: gogolatex-compiler-service
    ports:
      - "5003:5003"
    environment:
      PORT: "5003"
      MONGODB_URI: "mongodb://gogolatex-mongodb-1:27017,gogolatex-mongodb-2:27017,gogolatex-mongodb-3:27017/?replicaSet=rs0"
      MONGODB_DATABASE: "gogolatex"
      REDIS_ADDR: "gogolatex-redis-master:6379"
      REDIS_PASSWORD: "changeme_redis"
      REDIS_DB: "0"
      MINIO_ENDPOINT: "gogolatex-minio:9000"
      MINIO_ACCESS_KEY: "minioadmin"
      MINIO_SECRET_KEY: "changeme_minio"
      MINIO_BUCKET: "gogolatex"
      MINIO_USE_SSL: "false"
      MINIO_REGION: "us-east-1"
      JWT_SECRET: "your-secret-key-change-in-production"
      ALLOWED_ORIGINS: "http://localhost:3000"
      WORKING_DIR: "/tmp/compiler"
      NUM_WORKERS: "4"
      DOCKER_IMAGE: "gogolatex-compiler"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock  # Allow Docker compilation
      - compiler-working:/tmp/compiler
    depends_on:
      - gogolatex-mongodb-1
      - gogolatex-mongodb-2
      - gogolatex-mongodb-3
      - gogolatex-redis-master
      - gogolatex-minio
    networks:
      - gogolatex
    restart: unless-stopped

volumes:
  # ... existing volumes ...
  compiler-working:
```

### 10.2 Testing Script

Create: `scripts/test-compilation.sh`

```bash
#!/bin/bash

# Test compilation service

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
API_URL="http://localhost:5003"
TOKEN="" # Set this to a valid JWT token

echo -e "${YELLOW}Testing Compilation Service${NC}"
echo "================================"

# Test 1: Health Check
echo -e "\n${YELLOW}Test 1: Health Check${NC}"
response=$(curl -s -w "\n%{http_code}" ${API_URL}/health)
http_code=$(echo "$response" | tail -n 1)
body=$(echo "$response" | sed '$d')

if [ "$http_code" == "200" ]; then
    echo -e "${GREEN}✓ Health check passed${NC}"
    echo "$body" | jq '.'
else
    echo -e "${RED}✗ Health check failed (HTTP $http_code)${NC}"
    exit 1
fi

# Test 2: Get Statistics
echo -e "\n${YELLOW}Test 2: Get Statistics${NC}"
response=$(curl -s -w "\n%{http_code}" \
    -H "Authorization: Bearer $TOKEN" \
    ${API_URL}/api/compile/stats)
http_code=$(echo "$response" | tail -n 1)
body=$(echo "$response" | sed '$d')

if [ "$http_code" == "200" ]; then
    echo -e "${GREEN}✓ Get statistics passed${NC}"
    echo "$body" | jq '.'
else
    echo -e "${RED}✗ Get statistics failed (HTTP $http_code)${NC}"
fi

# Test 3: Create Compilation Job
echo -e "\n${YELLOW}Test 3: Create Compilation Job${NC}"

# You need a valid project ID and document ID
PROJECT_ID="000000000000000000000001"  # Replace with real ID
DOCUMENT_ID="000000000000000000000002" # Replace with real ID

response=$(curl -s -w "\n%{http_code}" \
    -X POST \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
        \"projectId\": \"$PROJECT_ID\",
        \"documentId\": \"$DOCUMENT_ID\",
        \"engine\": \"auto\",
        \"compilerType\": \"pdflatex\",
        \"priority\": 5
    }" \
    ${API_URL}/api/compile)
http_code=$(echo "$response" | tail -n 1)
body=$(echo "$response" | sed '$d')

if [ "$http_code" == "201" ]; then
    echo -e "${GREEN}✓ Create compilation job passed${NC}"
    JOB_ID=$(echo "$body" | jq -r '.id')
    echo "Job ID: $JOB_ID"
else
    echo -e "${RED}✗ Create compilation job failed (HTTP $http_code)${NC}"
    echo "$body"
    exit 1
fi

# Test 4: Check Job Status
echo -e "\n${YELLOW}Test 4: Check Job Status${NC}"
sleep 2  # Wait for processing

response=$(curl -s -w "\n%{http_code}" \
    -H "Authorization: Bearer $TOKEN" \
    ${API_URL}/api/compile/${JOB_ID})
http_code=$(echo "$response" | tail -n 1)
body=$(echo "$response" | sed '$d')

if [ "$http_code" == "200" ]; then
    echo -e "${GREEN}✓ Check job status passed${NC}"
    echo "$body" | jq '.'
    
    STATUS=$(echo "$body" | jq -r '.job.status')
    echo "Status: $STATUS"
else
    echo -e "${RED}✗ Check job status failed (HTTP $http_code)${NC}"
fi

echo -e "\n${GREEN}All tests completed!${NC}"
```

Make it executable:
```bash
chmod +x scripts/test-compilation.sh
```

### 10.3 Manual Testing

```bash
# Start services
docker-compose up -d gogolatex-compiler-service

# Check logs
docker-compose logs -f gogolatex-compiler-service

# Test health endpoint
curl http://localhost:5003/health | jq '.'

# Build LaTeX compiler image
cd docker/latex-compiler
docker build -t gogolatex-compiler .

# Test compilation locally
cd ../../
./scripts/test-compilation.sh
```

**Verification**:
```bash
# Check service is running
docker ps | grep compiler

# Check worker logs
docker logs gogolatex-compiler-service | grep "Worker"

# Check queue
docker exec gogolatex-redis-master redis-cli -a changeme_redis ZCARD "compilation:queue"

# Check processing jobs
docker exec gogolatex-redis-master redis-cli -a changeme_redis HLEN "compilation:processing"
```

---

## Phase 6 Completion Checklist

### Code Implementation
- [ ] Compilation models defined (CompilationJob, CompilationError, CompilationStats)
- [ ] LaTeX log parser implemented
- [ ] Package detector for auto engine selection
- [ ] Redis queue manager with priority
- [ ] WASM compiler interface
- [ ] Docker compiler with TeX Live Full
- [ ] Compilation repository with MongoDB
- [ ] Compilation service with engine selection
- [ ] HTTP handlers for compilation API
- [ ] Worker pool for background processing
- [ ] Main server with graceful shutdown

### Compilation Features
- [ ] Hybrid WASM + Docker compilation
- [ ] Auto engine selection based on packages
- [ ] Priority queue for compilation jobs
- [ ] Retry logic for failed compilations
- [ ] Error/warning parsing from logs
- [ ] PDF generation and storage in MinIO
- [ ] Log storage for debugging
- [ ] Presigned URLs for download

### Queue Management
- [ ] Redis-based job queue
- [ ] Priority-based job processing
- [ ] Job status tracking (pending, processing, success, failed)
- [ ] Retry mechanism with configurable max retries
- [ ] Stale job cleanup
- [ ] Queue size monitoring

### Docker Support
- [ ] TeX Live Full Docker image
- [ ] Container-based compilation
- [ ] Volume mounting for project files
- [ ] Log capture from containers
- [ ] Resource cleanup after compilation

### API Endpoints
- [ ] POST /api/compile - Create compilation job
- [ ] GET /api/compile/:id - Get job status
- [ ] GET /api/compile/project?projectId=... - Get project history
- [ ] GET /api/compile/stats - Get statistics
- [ ] GET /health - Health check with queue info

### Worker Pool
- [ ] Configurable number of workers
- [ ] Background job processing
- [ ] Graceful shutdown
- [ ] Error handling and logging

---

## Troubleshooting

### Compilation timeout
**Solution**:
- Increase `JobTimeout` in queue config
- Check Docker daemon is running
- Monitor system resources (CPU/memory)

### "No compiler available"
**Solution**:
- For WASM: Install pdflatex locally
- For Docker: Verify Docker daemon is accessible
- Check `/var/run/docker.sock` is mounted

### Jobs stuck in processing
**Solution**:
- Check worker logs for errors
- Run `CleanupStaleJobs` manually
- Restart worker pool
- Verify Redis connection

### PDF not generated
**Solution**:
- Check LaTeX source for errors
- Review compilation log
- Verify all required packages available
- Try Docker engine for full TeX Live

### High memory usage
**Solution**:
- Reduce `NUM_WORKERS`
- Clean up temp directories
- Limit concurrent Docker containers
- Monitor working directory size

---

## Performance Optimization

### 1. Cache Common Packages
```go
// Cache frequently used LaTeX packages
// Precompile common document templates
```

### 2. Parallel BibTeX Processing
```go
// Run bibtex in parallel for multiple bibliography files
```

### 3. Incremental Compilation
```go
// Store intermediate .aux files
// Only recompile changed sections
```

### 4. Resource Limits
```yaml
# docker-compose.yml
deploy:
  resources:
    limits:
      cpus: '2.0'
      memory: 2G
    reservations:
      cpus: '1.0'
      memory: 1G
```

---

## Next Steps

**Phase 7 Preview**: Advanced Features

In Phase 7, we'll add:
- Git integration (version control for LaTeX projects)
- Change tracking (track document edits with metadata)
- Comments system (inline LaTeX comments with replies)
- Conflict resolution UI
- Document history and diff viewer
- Mobile UI optimizations

**Estimated Duration**: 5-6 days

---

## Copilot Tips for Phase 6

1. **Compilation optimizations**:
   ```go
   // TODO: Add compilation caching (store PDF for unchanged docs)
   // TODO: Implement smart recompilation (only when source changes)
   // TODO: Add parallel processing for multi-file projects
   ```

2. **Error reporting improvements**:
   - "Create user-friendly error messages from LaTeX errors"
   - "Add error suggestion system (common fixes)"
   - "Implement LaTeX syntax checker before compilation"

3. **Advanced features**:
   - "Add custom LaTeX package installation"
   - "Implement compilation templates (presets)"
   - "Create compilation profiles (draft, final, print)"

4. **Monitoring**:
   - "Add Prometheus metrics for compilation queue"
   - "Track compilation success rate"
   - "Monitor compilation duration by engine"

---

**End of Phase 6**