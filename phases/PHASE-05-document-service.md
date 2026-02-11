# Phase 5: Document Service (Go REST API)

**Duration**: 4-5 days  
**Goal**: Go microservice for document CRUD, project management, and MinIO file storage

**Prerequisites**: Phases 1-4 completed, infrastructure running

---

## Prerequisites

- [ ] Phase 1-4 completed
- [ ] MongoDB running with replica set
- [ ] MinIO running and accessible
- [ ] Redis available for caching
- [ ] Auth service running for user validation
- [ ] Go 1.21+ installed

---

## Task 1: Go Project Structure (30 min)

### 1.1 Initialize Go Module

```bash
cd latex-collaborative-editor/backend/go-services

# Already initialized in Phase 2, verify:
cat go.mod
# Should show: module github.com/yourusername/gogolatex
```

### 1.2 Create Document Service Directories

```bash
mkdir -p cmd/document
mkdir -p internal/document/{handler,service,repository}
mkdir -p internal/storage
mkdir -p internal/models
```

### 1.3 Install Additional Dependencies

```bash
# MinIO SDK
go get github.com/minio/minio-go/v7

# MongoDB driver (already installed in Phase 2)
# go get go.mongodb.org/mongo-driver/mongo

# UUID generation
go get github.com/google/uuid

# Gin framework (already installed in Phase 2)
# go get github.com/gin-gonic/gin

# Validation
go get github.com/go-playground/validator/v10
```

**Verification**:
```bash
go mod tidy
go mod verify
```

---

## Task 2: Document Models (1 hour)

### 2.1 Project Model

Create: `internal/models/project.go`

```go
package models

import (
	"time"

	"go.mongodb.org/mongo-driver/bson/primitive"
)

// Project represents a LaTeX project
type Project struct {
	ID            primitive.ObjectID `bson:"_id,omitempty" json:"id"`
	Name          string             `bson:"name" json:"name" validate:"required,min=1,max=200"`
	Description   string             `bson:"description,omitempty" json:"description,omitempty" validate:"max=1000"`
	Owner         string             `bson:"owner" json:"owner" validate:"required"` // User ID
	Collaborators []Collaborator     `bson:"collaborators" json:"collaborators"`
	RootDocumentID primitive.ObjectID `bson:"rootDocumentId,omitempty" json:"rootDocumentId,omitempty"`
	CreatedAt     time.Time          `bson:"createdAt" json:"createdAt"`
	UpdatedAt     time.Time          `bson:"updatedAt" json:"updatedAt"`
	LastAccessedAt time.Time         `bson:"lastAccessedAt" json:"lastAccessedAt"`
	IsArchived    bool               `bson:"isArchived" json:"isArchived"`
	Tags          []string           `bson:"tags,omitempty" json:"tags,omitempty"`
}

// Collaborator represents a project collaborator with role-based access
type Collaborator struct {
	UserID    string    `bson:"userId" json:"userId" validate:"required"`
	Role      string    `bson:"role" json:"role" validate:"required,oneof=owner editor reviewer reader"`
	AddedAt   time.Time `bson:"addedAt" json:"addedAt"`
	AddedBy   string    `bson:"addedBy" json:"addedBy"`
	Email     string    `bson:"email,omitempty" json:"email,omitempty"` // For display
	Name      string    `bson:"name,omitempty" json:"name,omitempty"`   // For display
}

// ProjectRole defines access levels
const (
	RoleOwner    = "owner"    // Full access, can delete project
	RoleEditor   = "editor"   // Can edit documents
	RoleReviewer = "reviewer" // Can add comments, no direct edits
	RoleReader   = "reader"   // Read-only access
)

// HasWriteAccess checks if role allows writing
func (c *Collaborator) HasWriteAccess() bool {
	return c.Role == RoleOwner || c.Role == RoleEditor
}

// HasAdminAccess checks if role allows admin operations
func (c *Collaborator) HasAdminAccess() bool {
	return c.Role == RoleOwner
}

// CreateProjectRequest for API
type CreateProjectRequest struct {
	Name        string   `json:"name" validate:"required,min=1,max=200"`
	Description string   `json:"description,omitempty" validate:"max=1000"`
	Tags        []string `json:"tags,omitempty"`
}

// UpdateProjectRequest for API
type UpdateProjectRequest struct {
	Name        *string  `json:"name,omitempty" validate:"omitempty,min=1,max=200"`
	Description *string  `json:"description,omitempty" validate:"omitempty,max=1000"`
	Tags        []string `json:"tags,omitempty"`
}

// AddCollaboratorRequest for API
type AddCollaboratorRequest struct {
	UserID string `json:"userId" validate:"required"`
	Role   string `json:"role" validate:"required,oneof=editor reviewer reader"`
	Email  string `json:"email,omitempty" validate:"omitempty,email"`
	Name   string `json:"name,omitempty"`
}

// UpdateCollaboratorRequest for API
type UpdateCollaboratorRequest struct {
	Role string `json:"role" validate:"required,oneof=editor reviewer reader"`
}
```

### 2.2 Document Model

Create: `internal/models/document.go`

```go
package models

import (
	"time"

	"go.mongodb.org/mongo-driver/bson/primitive"
)

// Document represents a LaTeX file in a project
type Document struct {
	ID             primitive.ObjectID `bson:"_id,omitempty" json:"id"`
	ProjectID      primitive.ObjectID `bson:"projectId" json:"projectId" validate:"required"`
	Name           string             `bson:"name" json:"name" validate:"required,min=1,max=255"`
	Path           string             `bson:"path" json:"path" validate:"required"` // Relative path in project
	Type           string             `bson:"type" json:"type" validate:"required,oneof=tex bib sty cls png jpg pdf"`
	Content        string             `bson:"content,omitempty" json:"content,omitempty"` // For small text files
	MinIOKey       string             `bson:"minioKey,omitempty" json:"minioKey,omitempty"` // For large files
	Size           int64              `bson:"size" json:"size"` // Bytes
	LastModifiedBy string             `bson:"lastModifiedBy" json:"lastModifiedBy"`
	LastModifiedAt time.Time          `bson:"lastModifiedAt" json:"lastModifiedAt"`
	CreatedAt      time.Time          `bson:"createdAt" json:"createdAt"`
	Version        int                `bson:"version" json:"version"` // Optimistic locking
	IsDeleted      bool               `bson:"isDeleted" json:"isDeleted"`
}

// DocumentType constants
const (
	DocTypeTex  = "tex"
	DocTypeBib  = "bib"
	DocTypeSty  = "sty"
	DocTypeCls  = "cls"
	DocTypePng  = "png"
	DocTypeJpg  = "jpg"
	DocTypePdf  = "pdf"
)

// ContentStorageThreshold - files larger than this go to MinIO
const ContentStorageThreshold = 100 * 1024 // 100KB

// IsTextFile checks if document is a text file
func (d *Document) IsTextFile() bool {
	return d.Type == DocTypeTex || d.Type == DocTypeBib || 
	       d.Type == DocTypeSty || d.Type == DocTypeCls
}

// IsImageFile checks if document is an image
func (d *Document) IsImageFile() bool {
	return d.Type == DocTypePng || d.Type == DocTypeJpg
}

// ShouldStoreInMinIO checks if file should go to MinIO
func (d *Document) ShouldStoreInMinIO() bool {
	return d.Size > ContentStorageThreshold
}

// CreateDocumentRequest for API
type CreateDocumentRequest struct {
	ProjectID primitive.ObjectID `json:"projectId" validate:"required"`
	Name      string             `json:"name" validate:"required,min=1,max=255"`
	Path      string             `json:"path" validate:"required"`
	Type      string             `json:"type" validate:"required,oneof=tex bib sty cls png jpg pdf"`
	Content   string             `json:"content,omitempty"`
}

// UpdateDocumentRequest for API
type UpdateDocumentRequest struct {
	Name    *string `json:"name,omitempty" validate:"omitempty,min=1,max=255"`
	Path    *string `json:"path,omitempty"`
	Content *string `json:"content,omitempty"`
}

// DocumentListResponse for API
type DocumentListResponse struct {
	Documents []Document `json:"documents"`
	Total     int64      `json:"total"`
}
```

### 2.3 Project Tree Model

Create: `internal/models/tree.go`

```go
package models

// ProjectTree represents the file structure of a project
type ProjectTree struct {
	Root *TreeNode `json:"root"`
}

// TreeNode represents a file or folder in the project tree
type TreeNode struct {
	ID       string      `json:"id"`       // Document ID for files, generated for folders
	Name     string      `json:"name"`
	Type     string      `json:"type"`     // "file" or "folder"
	Path     string      `json:"path"`
	Size     int64       `json:"size,omitempty"`
	Children []*TreeNode `json:"children,omitempty"`
	FileType string      `json:"fileType,omitempty"` // tex, bib, png, etc.
}
```

**Verification**:
```bash
go build ./internal/models/...
# Should compile without errors
```

---

## Task 3: MinIO Storage Service (2 hours)

### 3.1 MinIO Configuration

Create: `internal/storage/config.go`

```go
package storage

import (
	"os"
)

// MinIOConfig holds MinIO connection configuration
type MinIOConfig struct {
	Endpoint        string
	AccessKeyID     string
	SecretAccessKey string
	BucketName      string
	UseSSL          bool
	Region          string
}

// LoadMinIOConfig loads MinIO config from environment
func LoadMinIOConfig() *MinIOConfig {
	return &MinIOConfig{
		Endpoint:        getEnv("MINIO_ENDPOINT", "localhost:9000"),
		AccessKeyID:     getEnv("MINIO_ACCESS_KEY", "minioadmin"),
		SecretAccessKey: getEnv("MINIO_SECRET_KEY", "minioadmin"),
		BucketName:      getEnv("MINIO_BUCKET", "gogolatex"),
		UseSSL:          getEnv("MINIO_USE_SSL", "false") == "true",
		Region:          getEnv("MINIO_REGION", "us-east-1"),
	}
}

func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}
```

### 3.2 MinIO Client

Create: `internal/storage/minio.go`

```go
package storage

import (
	"context"
	"fmt"
	"io"
	"log"
	"time"

	"github.com/minio/minio-go/v7"
	"github.com/minio/minio-go/v7/pkg/credentials"
)

// MinIOStorage handles file storage operations
type MinIOStorage struct {
	client *minio.Client
	bucket string
}

// NewMinIOStorage creates a new MinIO storage client
func NewMinIOStorage(config *MinIOConfig) (*MinIOStorage, error) {
	// Initialize MinIO client
	client, err := minio.New(config.Endpoint, &minio.Options{
		Creds:  credentials.NewStaticV4(config.AccessKeyID, config.SecretAccessKey, ""),
		Secure: config.UseSSL,
	})
	if err != nil {
		return nil, fmt.Errorf("failed to create MinIO client: %w", err)
	}

	storage := &MinIOStorage{
		client: client,
		bucket: config.BucketName,
	}

	// Ensure bucket exists
	if err := storage.ensureBucket(context.Background()); err != nil {
		return nil, fmt.Errorf("failed to ensure bucket exists: %w", err)
	}

	log.Printf("MinIO storage initialized: bucket=%s", config.BucketName)
	return storage, nil
}

// ensureBucket creates the bucket if it doesn't exist
func (s *MinIOStorage) ensureBucket(ctx context.Context) error {
	exists, err := s.client.BucketExists(ctx, s.bucket)
	if err != nil {
		return fmt.Errorf("failed to check bucket existence: %w", err)
	}

	if !exists {
		err = s.client.MakeBucket(ctx, s.bucket, minio.MakeBucketOptions{})
		if err != nil {
			return fmt.Errorf("failed to create bucket: %w", err)
		}
		log.Printf("Created MinIO bucket: %s", s.bucket)
	}

	return nil
}

// UploadFile uploads a file to MinIO
func (s *MinIOStorage) UploadFile(ctx context.Context, key string, reader io.Reader, size int64, contentType string) error {
	_, err := s.client.PutObject(ctx, s.bucket, key, reader, size, minio.PutObjectOptions{
		ContentType: contentType,
	})
	if err != nil {
		return fmt.Errorf("failed to upload file: %w", err)
	}

	log.Printf("Uploaded file to MinIO: key=%s, size=%d", key, size)
	return nil
}

// DownloadFile downloads a file from MinIO
func (s *MinIOStorage) DownloadFile(ctx context.Context, key string) (io.ReadCloser, error) {
	object, err := s.client.GetObject(ctx, s.bucket, key, minio.GetObjectOptions{})
	if err != nil {
		return nil, fmt.Errorf("failed to download file: %w", err)
	}

	return object, nil
}

// DeleteFile deletes a file from MinIO
func (s *MinIOStorage) DeleteFile(ctx context.Context, key string) error {
	err := s.client.RemoveObject(ctx, s.bucket, key, minio.RemoveObjectOptions{})
	if err != nil {
		return fmt.Errorf("failed to delete file: %w", err)
	}

	log.Printf("Deleted file from MinIO: key=%s", key)
	return nil
}

// GetFileInfo gets file metadata
func (s *MinIOStorage) GetFileInfo(ctx context.Context, key string) (*minio.ObjectInfo, error) {
	info, err := s.client.StatObject(ctx, s.bucket, key, minio.StatObjectOptions{})
	if err != nil {
		return nil, fmt.Errorf("failed to get file info: %w", err)
	}

	return &info, nil
}

// GetPresignedURL generates a temporary download URL (expires in 1 hour)
func (s *MinIOStorage) GetPresignedURL(ctx context.Context, key string, expires time.Duration) (string, error) {
	url, err := s.client.PresignedGetObject(ctx, s.bucket, key, expires, nil)
	if err != nil {
		return "", fmt.Errorf("failed to generate presigned URL: %w", err)
	}

	return url.String(), nil
}

// ListFiles lists all files with a given prefix
func (s *MinIOStorage) ListFiles(ctx context.Context, prefix string) ([]string, error) {
	var files []string

	objectCh := s.client.ListObjects(ctx, s.bucket, minio.ListObjectsOptions{
		Prefix:    prefix,
		Recursive: true,
	})

	for object := range objectCh {
		if object.Err != nil {
			return nil, fmt.Errorf("error listing files: %w", object.Err)
		}
		files = append(files, object.Key)
	}

	return files, nil
}

// CopyFile copies a file within MinIO
func (s *MinIOStorage) CopyFile(ctx context.Context, srcKey, dstKey string) error {
	src := minio.CopySrcOptions{
		Bucket: s.bucket,
		Object: srcKey,
	}

	dst := minio.CopyDestOptions{
		Bucket: s.bucket,
		Object: dstKey,
	}

	_, err := s.client.CopyObject(ctx, dst, src)
	if err != nil {
		return fmt.Errorf("failed to copy file: %w", err)
	}

	log.Printf("Copied file in MinIO: %s -> %s", srcKey, dstKey)
	return nil
}

// GenerateKey generates a MinIO object key for a document
func GenerateKey(projectID, documentID string) string {
	return fmt.Sprintf("projects/%s/documents/%s", projectID, documentID)
}
```

**Verification**:
```bash
go build ./internal/storage/...
```

---

## Task 4: Document Repository (2.5 hours)

### 4.1 Project Repository

Create: `internal/document/repository/project_repository.go`

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

// ProjectRepository handles project database operations
type ProjectRepository struct {
	collection *mongo.Collection
}

// NewProjectRepository creates a new project repository
func NewProjectRepository(db *mongo.Database) *ProjectRepository {
	collection := db.Collection("projects")

	// Create indexes
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	// Index on owner for fast user project queries
	collection.Indexes().CreateOne(ctx, mongo.IndexModel{
		Keys: bson.D{{Key: "owner", Value: 1}},
	})

	// Index on collaborators for shared project queries
	collection.Indexes().CreateOne(ctx, mongo.IndexModel{
		Keys: bson.D{{Key: "collaborators.userId", Value: 1}},
	})

	// Index on lastAccessedAt for recent projects
	collection.Indexes().CreateOne(ctx, mongo.IndexModel{
		Keys: bson.D{{Key: "lastAccessedAt", Value: -1}},
	})

	return &ProjectRepository{
		collection: collection,
	}
}

// Create creates a new project
func (r *ProjectRepository) Create(ctx context.Context, project *models.Project) error {
	project.CreatedAt = time.Now()
	project.UpdatedAt = time.Now()
	project.LastAccessedAt = time.Now()

	result, err := r.collection.InsertOne(ctx, project)
	if err != nil {
		return fmt.Errorf("failed to create project: %w", err)
	}

	project.ID = result.InsertedID.(primitive.ObjectID)
	return nil
}

// FindByID finds a project by ID
func (r *ProjectRepository) FindByID(ctx context.Context, id primitive.ObjectID) (*models.Project, error) {
	var project models.Project
	err := r.collection.FindOne(ctx, bson.M{"_id": id, "isArchived": false}).Decode(&project)
	if err != nil {
		if err == mongo.ErrNoDocuments {
			return nil, fmt.Errorf("project not found")
		}
		return nil, fmt.Errorf("failed to find project: %w", err)
	}

	return &project, nil
}

// FindByOwner finds all projects owned by a user
func (r *ProjectRepository) FindByOwner(ctx context.Context, ownerID string, limit, skip int64) ([]models.Project, int64, error) {
	filter := bson.M{
		"owner": ownerID,
		"isArchived": false,
	}

	return r.findWithPagination(ctx, filter, limit, skip)
}

// FindByCollaborator finds all projects where user is a collaborator
func (r *ProjectRepository) FindByCollaborator(ctx context.Context, userID string, limit, skip int64) ([]models.Project, int64, error) {
	filter := bson.M{
		"collaborators.userId": userID,
		"isArchived": false,
	}

	return r.findWithPagination(ctx, filter, limit, skip)
}

// FindRecent finds recently accessed projects for a user
func (r *ProjectRepository) FindRecent(ctx context.Context, userID string, limit int64) ([]models.Project, error) {
	filter := bson.M{
		"$or": []bson.M{
			{"owner": userID},
			{"collaborators.userId": userID},
		},
		"isArchived": false,
	}

	opts := options.Find().
		SetSort(bson.D{{Key: "lastAccessedAt", Value: -1}}).
		SetLimit(limit)

	cursor, err := r.collection.Find(ctx, filter, opts)
	if err != nil {
		return nil, fmt.Errorf("failed to find recent projects: %w", err)
	}
	defer cursor.Close(ctx)

	var projects []models.Project
	if err := cursor.All(ctx, &projects); err != nil {
		return nil, fmt.Errorf("failed to decode projects: %w", err)
	}

	return projects, nil
}

// Update updates a project
func (r *ProjectRepository) Update(ctx context.Context, id primitive.ObjectID, update bson.M) error {
	update["updatedAt"] = time.Now()

	result, err := r.collection.UpdateOne(
		ctx,
		bson.M{"_id": id},
		bson.M{"$set": update},
	)
	if err != nil {
		return fmt.Errorf("failed to update project: %w", err)
	}

	if result.MatchedCount == 0 {
		return fmt.Errorf("project not found")
	}

	return nil
}

// UpdateLastAccessed updates the lastAccessedAt timestamp
func (r *ProjectRepository) UpdateLastAccessed(ctx context.Context, id primitive.ObjectID) error {
	_, err := r.collection.UpdateOne(
		ctx,
		bson.M{"_id": id},
		bson.M{"$set": bson.M{"lastAccessedAt": time.Now()}},
	)
	return err
}

// Delete soft-deletes a project (archives it)
func (r *ProjectRepository) Delete(ctx context.Context, id primitive.ObjectID) error {
	return r.Update(ctx, id, bson.M{"isArchived": true})
}

// HardDelete permanently deletes a project
func (r *ProjectRepository) HardDelete(ctx context.Context, id primitive.ObjectID) error {
	result, err := r.collection.DeleteOne(ctx, bson.M{"_id": id})
	if err != nil {
		return fmt.Errorf("failed to delete project: %w", err)
	}

	if result.DeletedCount == 0 {
		return fmt.Errorf("project not found")
	}

	return nil
}

// AddCollaborator adds a collaborator to a project
func (r *ProjectRepository) AddCollaborator(ctx context.Context, projectID primitive.ObjectID, collaborator models.Collaborator) error {
	_, err := r.collection.UpdateOne(
		ctx,
		bson.M{"_id": projectID},
		bson.M{
			"$push": bson.M{"collaborators": collaborator},
			"$set":  bson.M{"updatedAt": time.Now()},
		},
	)
	if err != nil {
		return fmt.Errorf("failed to add collaborator: %w", err)
	}

	return nil
}

// RemoveCollaborator removes a collaborator from a project
func (r *ProjectRepository) RemoveCollaborator(ctx context.Context, projectID primitive.ObjectID, userID string) error {
	_, err := r.collection.UpdateOne(
		ctx,
		bson.M{"_id": projectID},
		bson.M{
			"$pull": bson.M{"collaborators": bson.M{"userId": userID}},
			"$set":  bson.M{"updatedAt": time.Now()},
		},
	)
	if err != nil {
		return fmt.Errorf("failed to remove collaborator: %w", err)
	}

	return nil
}

// UpdateCollaboratorRole updates a collaborator's role
func (r *ProjectRepository) UpdateCollaboratorRole(ctx context.Context, projectID primitive.ObjectID, userID, role string) error {
	_, err := r.collection.UpdateOne(
		ctx,
		bson.M{
			"_id": projectID,
			"collaborators.userId": userID,
		},
		bson.M{
			"$set": bson.M{
				"collaborators.$.role": role,
				"updatedAt": time.Now(),
			},
		},
	)
	if err != nil {
		return fmt.Errorf("failed to update collaborator role: %w", err)
	}

	return nil
}

// GetCollaborator gets a specific collaborator
func (r *ProjectRepository) GetCollaborator(ctx context.Context, projectID primitive.ObjectID, userID string) (*models.Collaborator, error) {
	project, err := r.FindByID(ctx, projectID)
	if err != nil {
		return nil, err
	}

	for _, collab := range project.Collaborators {
		if collab.UserID == userID {
			return &collab, nil
		}
	}

	return nil, fmt.Errorf("collaborator not found")
}

// findWithPagination helper for paginated queries
func (r *ProjectRepository) findWithPagination(ctx context.Context, filter bson.M, limit, skip int64) ([]models.Project, int64, error) {
	// Get total count
	total, err := r.collection.CountDocuments(ctx, filter)
	if err != nil {
		return nil, 0, fmt.Errorf("failed to count projects: %w", err)
	}

	// Get paginated results
	opts := options.Find().
		SetSort(bson.D{{Key: "updatedAt", Value: -1}}).
		SetLimit(limit).
		SetSkip(skip)

	cursor, err := r.collection.Find(ctx, filter, opts)
	if err != nil {
		return nil, 0, fmt.Errorf("failed to find projects: %w", err)
	}
	defer cursor.Close(ctx)

	var projects []models.Project
	if err := cursor.All(ctx, &projects); err != nil {
		return nil, 0, fmt.Errorf("failed to decode projects: %w", err)
	}

	return projects, total, nil
}
```

### 4.2 Document Repository

Create: `internal/document/repository/document_repository.go`

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

// DocumentRepository handles document database operations
type DocumentRepository struct {
	collection *mongo.Collection
}

// NewDocumentRepository creates a new document repository
func NewDocumentRepository(db *mongo.Database) *DocumentRepository {
	collection := db.Collection("documents")

	// Create indexes
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	// Compound index on projectId and path for fast lookups
	collection.Indexes().CreateOne(ctx, mongo.IndexModel{
		Keys: bson.D{
			{Key: "projectId", Value: 1},
			{Key: "path", Value: 1},
		},
		Options: options.Index().SetUnique(true),
	})

	// Index on projectId for listing project documents
	collection.Indexes().CreateOne(ctx, mongo.IndexModel{
		Keys: bson.D{{Key: "projectId", Value: 1}},
	})

	return &DocumentRepository{
		collection: collection,
	}
}

// Create creates a new document
func (r *DocumentRepository) Create(ctx context.Context, doc *models.Document) error {
	doc.CreatedAt = time.Now()
	doc.LastModifiedAt = time.Now()
	doc.Version = 1

	result, err := r.collection.InsertOne(ctx, doc)
	if err != nil {
		return fmt.Errorf("failed to create document: %w", err)
	}

	doc.ID = result.InsertedID.(primitive.ObjectID)
	return nil
}

// FindByID finds a document by ID
func (r *DocumentRepository) FindByID(ctx context.Context, id primitive.ObjectID) (*models.Document, error) {
	var doc models.Document
	err := r.collection.FindOne(ctx, bson.M{"_id": id, "isDeleted": false}).Decode(&doc)
	if err != nil {
		if err == mongo.ErrNoDocuments {
			return nil, fmt.Errorf("document not found")
		}
		return nil, fmt.Errorf("failed to find document: %w", err)
	}

	return &doc, nil
}

// FindByProjectID finds all documents in a project
func (r *DocumentRepository) FindByProjectID(ctx context.Context, projectID primitive.ObjectID) ([]models.Document, error) {
	filter := bson.M{
		"projectId":  projectID,
		"isDeleted": false,
	}

	cursor, err := r.collection.Find(ctx, filter)
	if err != nil {
		return nil, fmt.Errorf("failed to find documents: %w", err)
	}
	defer cursor.Close(ctx)

	var documents []models.Document
	if err := cursor.All(ctx, &documents); err != nil {
		return nil, fmt.Errorf("failed to decode documents: %w", err)
	}

	return documents, nil
}

// FindByPath finds a document by project and path
func (r *DocumentRepository) FindByPath(ctx context.Context, projectID primitive.ObjectID, path string) (*models.Document, error) {
	var doc models.Document
	err := r.collection.FindOne(ctx, bson.M{
		"projectId": projectID,
		"path":      path,
		"isDeleted": false,
	}).Decode(&doc)
	if err != nil {
		if err == mongo.ErrNoDocuments {
			return nil, fmt.Errorf("document not found")
		}
		return nil, fmt.Errorf("failed to find document: %w", err)
	}

	return &doc, nil
}

// Update updates a document with optimistic locking
func (r *DocumentRepository) Update(ctx context.Context, id primitive.ObjectID, currentVersion int, update bson.M) error {
	update["lastModifiedAt"] = time.Now()
	update["version"] = currentVersion + 1

	result, err := r.collection.UpdateOne(
		ctx,
		bson.M{
			"_id":     id,
			"version": currentVersion,
		},
		bson.M{"$set": update},
	)
	if err != nil {
		return fmt.Errorf("failed to update document: %w", err)
	}

	if result.MatchedCount == 0 {
		return fmt.Errorf("document not found or version mismatch")
	}

	return nil
}

// UpdateContent updates document content
func (r *DocumentRepository) UpdateContent(ctx context.Context, id primitive.ObjectID, content string, userID string) error {
	_, err := r.collection.UpdateOne(
		ctx,
		bson.M{"_id": id},
		bson.M{
			"$set": bson.M{
				"content":         content,
				"lastModifiedBy":  userID,
				"lastModifiedAt":  time.Now(),
			},
			"$inc": bson.M{"version": 1},
		},
	)
	if err != nil {
		return fmt.Errorf("failed to update document content: %w", err)
	}

	return nil
}

// Delete soft-deletes a document
func (r *DocumentRepository) Delete(ctx context.Context, id primitive.ObjectID) error {
	_, err := r.collection.UpdateOne(
		ctx,
		bson.M{"_id": id},
		bson.M{"$set": bson.M{"isDeleted": true}},
	)
	if err != nil {
		return fmt.Errorf("failed to delete document: %w", err)
	}

	return nil
}

// HardDelete permanently deletes a document
func (r *DocumentRepository) HardDelete(ctx context.Context, id primitive.ObjectID) error {
	result, err := r.collection.DeleteOne(ctx, bson.M{"_id": id})
	if err != nil {
		return fmt.Errorf("failed to hard delete document: %w", err)
	}

	if result.DeletedCount == 0 {
		return fmt.Errorf("document not found")
	}

	return nil
}
```

**Verification**:
```bash
go build ./internal/document/repository/...
```

---

## Task 5: Document Service Layer (3 hours)

### 5.1 Project Service

Create: `internal/document/service/project_service.go`

```go
package service

import (
	"context"
	"fmt"
	"time"

	"github.com/yourusername/gogolatex/internal/document/repository"
	"github.com/yourusername/gogolatex/internal/models"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
)

// ProjectService handles project business logic
type ProjectService struct {
	repo *repository.ProjectRepository
}

// NewProjectService creates a new project service
func NewProjectService(repo *repository.ProjectRepository) *ProjectService {
	return &ProjectService{
		repo: repo,
	}
}

// CreateProject creates a new project
func (s *ProjectService) CreateProject(ctx context.Context, req *models.CreateProjectRequest, ownerID string) (*models.Project, error) {
	project := &models.Project{
		Name:        req.Name,
		Description: req.Description,
		Owner:       ownerID,
		Tags:        req.Tags,
		Collaborators: []models.Collaborator{
			{
				UserID:  ownerID,
				Role:    models.RoleOwner,
				AddedAt: time.Now(),
				AddedBy: ownerID,
			},
		},
		IsArchived: false,
	}

	if err := s.repo.Create(ctx, project); err != nil {
		return nil, fmt.Errorf("failed to create project: %w", err)
	}

	return project, nil
}

// GetProject gets a project by ID
func (s *ProjectService) GetProject(ctx context.Context, projectID primitive.ObjectID, userID string) (*models.Project, error) {
	project, err := s.repo.FindByID(ctx, projectID)
	if err != nil {
		return nil, err
	}

	// Update last accessed timestamp
	go s.repo.UpdateLastAccessed(context.Background(), projectID)

	// Check user has access
	if !s.userHasAccess(project, userID) {
		return nil, fmt.Errorf("access denied")
	}

	return project, nil
}

// GetUserProjects gets all projects owned by a user
func (s *ProjectService) GetUserProjects(ctx context.Context, userID string, limit, skip int64) ([]models.Project, int64, error) {
	return s.repo.FindByOwner(ctx, userID, limit, skip)
}

// GetSharedProjects gets all projects shared with a user
func (s *ProjectService) GetSharedProjects(ctx context.Context, userID string, limit, skip int64) ([]models.Project, int64, error) {
	return s.repo.FindByCollaborator(ctx, userID, limit, skip)
}

// GetRecentProjects gets recently accessed projects
func (s *ProjectService) GetRecentProjects(ctx context.Context, userID string, limit int64) ([]models.Project, error) {
	return s.repo.FindRecent(ctx, userID, limit)
}

// UpdateProject updates a project
func (s *ProjectService) UpdateProject(ctx context.Context, projectID primitive.ObjectID, req *models.UpdateProjectRequest, userID string) error {
	// Check user has admin access
	if err := s.checkAdminAccess(ctx, projectID, userID); err != nil {
		return err
	}

	update := bson.M{}
	if req.Name != nil {
		update["name"] = *req.Name
	}
	if req.Description != nil {
		update["description"] = *req.Description
	}
	if req.Tags != nil {
		update["tags"] = req.Tags
	}

	return s.repo.Update(ctx, projectID, update)
}

// DeleteProject deletes a project (soft delete)
func (s *ProjectService) DeleteProject(ctx context.Context, projectID primitive.ObjectID, userID string) error {
	// Check user has admin access
	if err := s.checkAdminAccess(ctx, projectID, userID); err != nil {
		return err
	}

	return s.repo.Delete(ctx, projectID)
}

// AddCollaborator adds a collaborator to a project
func (s *ProjectService) AddCollaborator(ctx context.Context, projectID primitive.ObjectID, req *models.AddCollaboratorRequest, addedBy string) error {
	// Check user has admin access
	if err := s.checkAdminAccess(ctx, projectID, addedBy); err != nil {
		return err
	}

	// Check if user is already a collaborator
	project, err := s.repo.FindByID(ctx, projectID)
	if err != nil {
		return err
	}

	for _, collab := range project.Collaborators {
		if collab.UserID == req.UserID {
			return fmt.Errorf("user is already a collaborator")
		}
	}

	collaborator := models.Collaborator{
		UserID:  req.UserID,
		Role:    req.Role,
		AddedAt: time.Now(),
		AddedBy: addedBy,
		Email:   req.Email,
		Name:    req.Name,
	}

	return s.repo.AddCollaborator(ctx, projectID, collaborator)
}

// RemoveCollaborator removes a collaborator from a project
func (s *ProjectService) RemoveCollaborator(ctx context.Context, projectID primitive.ObjectID, collaboratorID, removedBy string) error {
	// Check user has admin access
	if err := s.checkAdminAccess(ctx, projectID, removedBy); err != nil {
		return err
	}

	// Cannot remove the owner
	project, err := s.repo.FindByID(ctx, projectID)
	if err != nil {
		return err
	}

	if project.Owner == collaboratorID {
		return fmt.Errorf("cannot remove project owner")
	}

	return s.repo.RemoveCollaborator(ctx, projectID, collaboratorID)
}

// UpdateCollaboratorRole updates a collaborator's role
func (s *ProjectService) UpdateCollaboratorRole(ctx context.Context, projectID primitive.ObjectID, collaboratorID string, req *models.UpdateCollaboratorRequest, updatedBy string) error {
	// Check user has admin access
	if err := s.checkAdminAccess(ctx, projectID, updatedBy); err != nil {
		return err
	}

	// Cannot change owner's role
	project, err := s.repo.FindByID(ctx, projectID)
	if err != nil {
		return err
	}

	if project.Owner == collaboratorID {
		return fmt.Errorf("cannot change owner's role")
	}

	return s.repo.UpdateCollaboratorRole(ctx, projectID, collaboratorID, req.Role)
}

// userHasAccess checks if user has any access to project
func (s *ProjectService) userHasAccess(project *models.Project, userID string) bool {
	if project.Owner == userID {
		return true
	}

	for _, collab := range project.Collaborators {
		if collab.UserID == userID {
			return true
		}
	}

	return false
}

// checkAdminAccess checks if user has admin access to project
func (s *ProjectService) checkAdminAccess(ctx context.Context, projectID primitive.ObjectID, userID string) error {
	project, err := s.repo.FindByID(ctx, projectID)
	if err != nil {
		return err
	}

	if project.Owner != userID {
		return fmt.Errorf("admin access required")
	}

	return nil
}

// checkWriteAccess checks if user has write access to project
func (s *ProjectService) checkWriteAccess(ctx context.Context, projectID primitive.ObjectID, userID string) error {
	project, err := s.repo.FindByID(ctx, projectID)
	if err != nil {
		return err
	}

	if project.Owner == userID {
		return nil
	}

	for _, collab := range project.Collaborators {
		if collab.UserID == userID && collab.HasWriteAccess() {
			return nil
		}
	}

	return fmt.Errorf("write access required")
}
```

### 5.2 Document Service

Create: `internal/document/service/document_service.go`

```go
package service

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"strings"

	"github.com/google/uuid"
	"github.com/yourusername/gogolatex/internal/document/repository"
	"github.com/yourusername/gogolatex/internal/models"
	"github.com/yourusername/gogolatex/internal/storage"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
)

// DocumentService handles document business logic
type DocumentService struct {
	repo           *repository.DocumentRepository
	projectService *ProjectService
	storage        *storage.MinIOStorage
}

// NewDocumentService creates a new document service
func NewDocumentService(
	repo *repository.DocumentRepository,
	projectService *ProjectService,
	storage *storage.MinIOStorage,
) *DocumentService {
	return &DocumentService{
		repo:           repo,
		projectService: projectService,
		storage:        storage,
	}
}

// CreateDocument creates a new document
func (s *DocumentService) CreateDocument(ctx context.Context, req *models.CreateDocumentRequest, userID string) (*models.Document, error) {
	// Check user has write access to project
	if err := s.projectService.checkWriteAccess(ctx, req.ProjectID, userID); err != nil {
		return nil, err
	}

	// Check if document already exists at this path
	existing, _ := s.repo.FindByPath(ctx, req.ProjectID, req.Path)
	if existing != nil {
		return nil, fmt.Errorf("document already exists at path: %s", req.Path)
	}

	doc := &models.Document{
		ProjectID:      req.ProjectID,
		Name:           req.Name,
		Path:           req.Path,
		Type:           req.Type,
		Content:        req.Content,
		Size:           int64(len(req.Content)),
		LastModifiedBy: userID,
		IsDeleted:      false,
	}

	// If content is large, store in MinIO
	if doc.Size > models.ContentStorageThreshold {
		key := storage.GenerateKey(req.ProjectID.Hex(), uuid.New().String())
		reader := strings.NewReader(req.Content)

		if err := s.storage.UploadFile(ctx, key, reader, doc.Size, "text/plain"); err != nil {
			return nil, fmt.Errorf("failed to upload to MinIO: %w", err)
		}

		doc.MinIOKey = key
		doc.Content = "" // Clear content from MongoDB
	}

	if err := s.repo.Create(ctx, doc); err != nil {
		// Cleanup MinIO if document creation fails
		if doc.MinIOKey != "" {
			s.storage.DeleteFile(context.Background(), doc.MinIOKey)
		}
		return nil, err
	}

	return doc, nil
}

// GetDocument gets a document by ID
func (s *DocumentService) GetDocument(ctx context.Context, documentID primitive.ObjectID, userID string) (*models.Document, error) {
	doc, err := s.repo.FindByID(ctx, documentID)
	if err != nil {
		return nil, err
	}

	// Check user has access to project
	if _, err := s.projectService.GetProject(ctx, doc.ProjectID, userID); err != nil {
		return nil, fmt.Errorf("access denied")
	}

	// Load content from MinIO if needed
	if doc.MinIOKey != "" {
		content, err := s.loadFromMinIO(ctx, doc.MinIOKey)
		if err != nil {
			return nil, err
		}
		doc.Content = content
	}

	return doc, nil
}

// GetProjectDocuments gets all documents in a project
func (s *DocumentService) GetProjectDocuments(ctx context.Context, projectID primitive.ObjectID, userID string) ([]models.Document, error) {
	// Check user has access to project
	if _, err := s.projectService.GetProject(ctx, projectID, userID); err != nil {
		return nil, fmt.Errorf("access denied")
	}

	return s.repo.FindByProjectID(ctx, projectID)
}

// UpdateDocument updates a document
func (s *DocumentService) UpdateDocument(ctx context.Context, documentID primitive.ObjectID, req *models.UpdateDocumentRequest, userID string) error {
	doc, err := s.repo.FindByID(ctx, documentID)
	if err != nil {
		return err
	}

	// Check user has write access
	if err := s.projectService.checkWriteAccess(ctx, doc.ProjectID, userID); err != nil {
		return err
	}

	update := bson.M{
		"lastModifiedBy": userID,
	}

	if req.Name != nil {
		update["name"] = *req.Name
	}
	if req.Path != nil {
		update["path"] = *req.Path
	}
	if req.Content != nil {
		newSize := int64(len(*req.Content))

		// Handle MinIO storage for large files
		if newSize > models.ContentStorageThreshold {
			key := doc.MinIOKey
			if key == "" {
				key = storage.GenerateKey(doc.ProjectID.Hex(), documentID.Hex())
			}

			reader := strings.NewReader(*req.Content)
			if err := s.storage.UploadFile(ctx, key, reader, newSize, "text/plain"); err != nil {
				return fmt.Errorf("failed to upload to MinIO: %w", err)
			}

			update["minioKey"] = key
			update["content"] = ""
			update["size"] = newSize
		} else {
			// Small file, store in MongoDB
			if doc.MinIOKey != "" {
				// Delete from MinIO if it was there before
				s.storage.DeleteFile(context.Background(), doc.MinIOKey)
			}
			update["content"] = *req.Content
			update["minioKey"] = ""
			update["size"] = newSize
		}
	}

	return s.repo.Update(ctx, documentID, doc.Version, update)
}

// DeleteDocument deletes a document
func (s *DocumentService) DeleteDocument(ctx context.Context, documentID primitive.ObjectID, userID string) error {
	doc, err := s.repo.FindByID(ctx, documentID)
	if err != nil {
		return err
	}

	// Check user has write access
	if err := s.projectService.checkWriteAccess(ctx, doc.ProjectID, userID); err != nil {
		return err
	}

	// Delete from MinIO if applicable
	if doc.MinIOKey != "" {
		if err := s.storage.DeleteFile(ctx, doc.MinIOKey); err != nil {
			// Log error but don't fail the operation
			fmt.Printf("Warning: failed to delete from MinIO: %v\n", err)
		}
	}

	return s.repo.Delete(ctx, documentID)
}

// UploadFile uploads a binary file (images, PDFs)
func (s *DocumentService) UploadFile(ctx context.Context, projectID primitive.ObjectID, name, path, fileType string, content io.Reader, size int64, userID string) (*models.Document, error) {
	// Check user has write access
	if err := s.projectService.checkWriteAccess(ctx, projectID, userID); err != nil {
		return nil, err
	}

	// Generate MinIO key
	key := storage.GenerateKey(projectID.Hex(), uuid.New().String())

	// Determine content type
	contentType := "application/octet-stream"
	switch fileType {
	case "png":
		contentType = "image/png"
	case "jpg":
		contentType = "image/jpeg"
	case "pdf":
		contentType = "application/pdf"
	}

	// Upload to MinIO
	if err := s.storage.UploadFile(ctx, key, content, size, contentType); err != nil {
		return nil, fmt.Errorf("failed to upload file: %w", err)
	}

	// Create document metadata
	doc := &models.Document{
		ProjectID:      projectID,
		Name:           name,
		Path:           path,
		Type:           fileType,
		MinIOKey:       key,
		Size:           size,
		LastModifiedBy: userID,
		IsDeleted:      false,
	}

	if err := s.repo.Create(ctx, doc); err != nil {
		// Cleanup MinIO on failure
		s.storage.DeleteFile(context.Background(), key)
		return nil, err
	}

	return doc, nil
}

// DownloadFile downloads a file from storage
func (s *DocumentService) DownloadFile(ctx context.Context, documentID primitive.ObjectID, userID string) (io.ReadCloser, string, error) {
	doc, err := s.repo.FindByID(ctx, documentID)
	if err != nil {
		return nil, "", err
	}

	// Check user has access
	if _, err := s.projectService.GetProject(ctx, doc.ProjectID, userID); err != nil {
		return nil, "", fmt.Errorf("access denied")
	}

	if doc.MinIOKey == "" {
		// Return content from MongoDB
		reader := io.NopCloser(strings.NewReader(doc.Content))
		return reader, doc.Name, nil
	}

	// Download from MinIO
	reader, err := s.storage.DownloadFile(ctx, doc.MinIOKey)
	if err != nil {
		return nil, "", fmt.Errorf("failed to download file: %w", err)
	}

	return reader, doc.Name, nil
}

// GetProjectTree builds a tree structure of project files
func (s *DocumentService) GetProjectTree(ctx context.Context, projectID primitive.ObjectID, userID string) (*models.ProjectTree, error) {
	// Check user has access
	if _, err := s.projectService.GetProject(ctx, projectID, userID); err != nil {
		return nil, fmt.Errorf("access denied")
	}

	documents, err := s.repo.FindByProjectID(ctx, projectID)
	if err != nil {
		return nil, err
	}

	// Build tree structure
	root := &models.TreeNode{
		ID:       "root",
		Name:     "root",
		Type:     "folder",
		Path:     "/",
		Children: []*models.TreeNode{},
	}

	for _, doc := range documents {
		s.addToTree(root, &doc)
	}

	return &models.ProjectTree{Root: root}, nil
}

// addToTree adds a document to the tree structure
func (s *DocumentService) addToTree(root *models.TreeNode, doc *models.Document) {
	parts := strings.Split(strings.Trim(doc.Path, "/"), "/")
	current := root

	// Create folder nodes
	for i := 0; i < len(parts)-1; i++ {
		found := false
		for _, child := range current.Children {
			if child.Name == parts[i] && child.Type == "folder" {
				current = child
				found = true
				break
			}
		}

		if !found {
			folder := &models.TreeNode{
				ID:       uuid.New().String(),
				Name:     parts[i],
				Type:     "folder",
				Path:     "/" + strings.Join(parts[:i+1], "/"),
				Children: []*models.TreeNode{},
			}
			current.Children = append(current.Children, folder)
			current = folder
		}
	}

	// Add file node
	fileNode := &models.TreeNode{
		ID:       doc.ID.Hex(),
		Name:     doc.Name,
		Type:     "file",
		Path:     doc.Path,
		Size:     doc.Size,
		FileType: doc.Type,
	}
	current.Children = append(current.Children, fileNode)
}

// loadFromMinIO loads content from MinIO
func (s *DocumentService) loadFromMinIO(ctx context.Context, key string) (string, error) {
	reader, err := s.storage.DownloadFile(ctx, key)
	if err != nil {
		return "", err
	}
	defer reader.Close()

	buf := new(bytes.Buffer)
	if _, err := io.Copy(buf, reader); err != nil {
		return "", fmt.Errorf("failed to read from MinIO: %w", err)
	}

	return buf.String(), nil
}
```

**Verification**:
```bash
go build ./internal/document/service/...
```

---

## Task 6: HTTP Handlers (3 hours)

### 6.1 Project Handler

Create: `internal/document/handler/project_handler.go`

```go
package handler

import (
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
	"github.com/go-playground/validator/v10"
	"github.com/yourusername/gogolatex/internal/document/service"
	"github.com/yourusername/gogolatex/internal/models"
	"go.mongodb.org/mongo-driver/bson/primitive"
)

// ProjectHandler handles project HTTP requests
type ProjectHandler struct {
	service  *service.ProjectService
	validate *validator.Validate
}

// NewProjectHandler creates a new project handler
func NewProjectHandler(service *service.ProjectService) *ProjectHandler {
	return &ProjectHandler{
		service:  service,
		validate: validator.New(),
	}
}

// CreateProject godoc
// @Summary Create a new project
// @Tags projects
// @Accept json
// @Produce json
// @Param request body models.CreateProjectRequest true "Project details"
// @Success 201 {object} models.Project
// @Failure 400 {object} map[string]string
// @Failure 401 {object} map[string]string
// @Router /api/projects [post]
func (h *ProjectHandler) CreateProject(c *gin.Context) {
	var req models.CreateProjectRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if err := h.validate.Struct(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	userID := c.GetString("userID")
	project, err := h.service.CreateProject(c.Request.Context(), &req, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, project)
}

// GetProject godoc
// @Summary Get project by ID
// @Tags projects
// @Produce json
// @Param id path string true "Project ID"
// @Success 200 {object} models.Project
// @Failure 404 {object} map[string]string
// @Router /api/projects/{id} [get]
func (h *ProjectHandler) GetProject(c *gin.Context) {
	id, err := primitive.ObjectIDFromHex(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid project ID"})
		return
	}

	userID := c.GetString("userID")
	project, err := h.service.GetProject(c.Request.Context(), id, userID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, project)
}

// GetUserProjects godoc
// @Summary Get user's projects
// @Tags projects
// @Produce json
// @Param limit query int false "Limit" default(20)
// @Param skip query int false "Skip" default(0)
// @Success 200 {object} map[string]interface{}
// @Router /api/projects [get]
func (h *ProjectHandler) GetUserProjects(c *gin.Context) {
	userID := c.GetString("userID")

	limit, _ := strconv.ParseInt(c.DefaultQuery("limit", "20"), 10, 64)
	skip, _ := strconv.ParseInt(c.DefaultQuery("skip", "0"), 10, 64)

	projects, total, err := h.service.GetUserProjects(c.Request.Context(), userID, limit, skip)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"projects": projects,
		"total":    total,
		"limit":    limit,
		"skip":     skip,
	})
}

// GetSharedProjects godoc
// @Summary Get projects shared with user
// @Tags projects
// @Produce json
// @Param limit query int false "Limit" default(20)
// @Param skip query int false "Skip" default(0)
// @Success 200 {object} map[string]interface{}
// @Router /api/projects/shared [get]
func (h *ProjectHandler) GetSharedProjects(c *gin.Context) {
	userID := c.GetString("userID")

	limit, _ := strconv.ParseInt(c.DefaultQuery("limit", "20"), 10, 64)
	skip, _ := strconv.ParseInt(c.DefaultQuery("skip", "0"), 10, 64)

	projects, total, err := h.service.GetSharedProjects(c.Request.Context(), userID, limit, skip)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"projects": projects,
		"total":    total,
		"limit":    limit,
		"skip":     skip,
	})
}

// GetRecentProjects godoc
// @Summary Get recently accessed projects
// @Tags projects
// @Produce json
// @Param limit query int false "Limit" default(10)
// @Success 200 {array} models.Project
// @Router /api/projects/recent [get]
func (h *ProjectHandler) GetRecentProjects(c *gin.Context) {
	userID := c.GetString("userID")
	limit, _ := strconv.ParseInt(c.DefaultQuery("limit", "10"), 10, 64)

	projects, err := h.service.GetRecentProjects(c.Request.Context(), userID, limit)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, projects)
}

// UpdateProject godoc
// @Summary Update project
// @Tags projects
// @Accept json
// @Produce json
// @Param id path string true "Project ID"
// @Param request body models.UpdateProjectRequest true "Update data"
// @Success 200 {object} map[string]string
// @Router /api/projects/{id} [patch]
func (h *ProjectHandler) UpdateProject(c *gin.Context) {
	id, err := primitive.ObjectIDFromHex(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid project ID"})
		return
	}

	var req models.UpdateProjectRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	userID := c.GetString("userID")
	if err := h.service.UpdateProject(c.Request.Context(), id, &req, userID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "project updated"})
}

// DeleteProject godoc
// @Summary Delete project
// @Tags projects
// @Param id path string true "Project ID"
// @Success 200 {object} map[string]string
// @Router /api/projects/{id} [delete]
func (h *ProjectHandler) DeleteProject(c *gin.Context) {
	id, err := primitive.ObjectIDFromHex(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid project ID"})
		return
	}

	userID := c.GetString("userID")
	if err := h.service.DeleteProject(c.Request.Context(), id, userID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "project deleted"})
}

// AddCollaborator godoc
// @Summary Add collaborator to project
// @Tags projects
// @Accept json
// @Produce json
// @Param id path string true "Project ID"
// @Param request body models.AddCollaboratorRequest true "Collaborator details"
// @Success 200 {object} map[string]string
// @Router /api/projects/{id}/collaborators [post]
func (h *ProjectHandler) AddCollaborator(c *gin.Context) {
	id, err := primitive.ObjectIDFromHex(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid project ID"})
		return
	}

	var req models.AddCollaboratorRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	userID := c.GetString("userID")
	if err := h.service.AddCollaborator(c.Request.Context(), id, &req, userID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "collaborator added"})
}

// RemoveCollaborator godoc
// @Summary Remove collaborator from project
// @Tags projects
// @Param id path string true "Project ID"
// @Param userId path string true "User ID"
// @Success 200 {object} map[string]string
// @Router /api/projects/{id}/collaborators/{userId} [delete]
func (h *ProjectHandler) RemoveCollaborator(c *gin.Context) {
	id, err := primitive.ObjectIDFromHex(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid project ID"})
		return
	}

	collaboratorID := c.Param("userId")
	userID := c.GetString("userID")

	if err := h.service.RemoveCollaborator(c.Request.Context(), id, collaboratorID, userID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "collaborator removed"})
}

// UpdateCollaboratorRole godoc
// @Summary Update collaborator role
// @Tags projects
// @Accept json
// @Produce json
// @Param id path string true "Project ID"
// @Param userId path string true "User ID"
// @Param request body models.UpdateCollaboratorRequest true "Role update"
// @Success 200 {object} map[string]string
// @Router /api/projects/{id}/collaborators/{userId} [patch]
func (h *ProjectHandler) UpdateCollaboratorRole(c *gin.Context) {
	id, err := primitive.ObjectIDFromHex(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid project ID"})
		return
	}

	collaboratorID := c.Param("userId")

	var req models.UpdateCollaboratorRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	userID := c.GetString("userID")
	if err := h.service.UpdateCollaboratorRole(c.Request.Context(), id, collaboratorID, &req, userID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "collaborator role updated"})
}
```

### 6.2 Document Handler

Create: `internal/document/handler/document_handler.go`

```go
package handler

import (
	"fmt"
	"io"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/go-playground/validator/v10"
	"github.com/yourusername/gogolatex/internal/document/service"
	"github.com/yourusername/gogolatex/internal/models"
	"go.mongodb.org/mongo-driver/bson/primitive"
)

// DocumentHandler handles document HTTP requests
type DocumentHandler struct {
	service  *service.DocumentService
	validate *validator.Validate
}

// NewDocumentHandler creates a new document handler
func NewDocumentHandler(service *service.DocumentService) *DocumentHandler {
	return &DocumentHandler{
		service:  service,
		validate: validator.New(),
	}
}

// CreateDocument godoc
// @Summary Create a new document
// @Tags documents
// @Accept json
// @Produce json
// @Param request body models.CreateDocumentRequest true "Document details"
// @Success 201 {object} models.Document
// @Router /api/documents [post]
func (h *DocumentHandler) CreateDocument(c *gin.Context) {
	var req models.CreateDocumentRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if err := h.validate.Struct(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	userID := c.GetString("userID")
	doc, err := h.service.CreateDocument(c.Request.Context(), &req, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, doc)
}

// GetDocument godoc
// @Summary Get document by ID
// @Tags documents
// @Produce json
// @Param id path string true "Document ID"
// @Success 200 {object} models.Document
// @Router /api/documents/{id} [get]
func (h *DocumentHandler) GetDocument(c *gin.Context) {
	id, err := primitive.ObjectIDFromHex(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid document ID"})
		return
	}

	userID := c.GetString("userID")
	doc, err := h.service.GetDocument(c.Request.Context(), id, userID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, doc)
}

// GetProjectDocuments godoc
// @Summary Get all documents in a project
// @Tags documents
// @Produce json
// @Param projectId query string true "Project ID"
// @Success 200 {array} models.Document
// @Router /api/documents [get]
func (h *DocumentHandler) GetProjectDocuments(c *gin.Context) {
	projectID, err := primitive.ObjectIDFromHex(c.Query("projectId"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid project ID"})
		return
	}

	userID := c.GetString("userID")
	documents, err := h.service.GetProjectDocuments(c.Request.Context(), projectID, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, documents)
}

// UpdateDocument godoc
// @Summary Update document
// @Tags documents
// @Accept json
// @Produce json
// @Param id path string true "Document ID"
// @Param request body models.UpdateDocumentRequest true "Update data"
// @Success 200 {object} map[string]string
// @Router /api/documents/{id} [patch]
func (h *DocumentHandler) UpdateDocument(c *gin.Context) {
	id, err := primitive.ObjectIDFromHex(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid document ID"})
		return
	}

	var req models.UpdateDocumentRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	userID := c.GetString("userID")
	if err := h.service.UpdateDocument(c.Request.Context(), id, &req, userID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "document updated"})
}

// DeleteDocument godoc
// @Summary Delete document
// @Tags documents
// @Param id path string true "Document ID"
// @Success 200 {object} map[string]string
// @Router /api/documents/{id} [delete]
func (h *DocumentHandler) DeleteDocument(c *gin.Context) {
	id, err := primitive.ObjectIDFromHex(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid document ID"})
		return
	}

	userID := c.GetString("userID")
	if err := h.service.DeleteDocument(c.Request.Context(), id, userID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "document deleted"})
}

// UploadFile godoc
// @Summary Upload a file (image, PDF, etc.)
// @Tags documents
// @Accept multipart/form-data
// @Produce json
// @Param projectId formData string true "Project ID"
// @Param name formData string true "File name"
// @Param path formData string true "File path in project"
// @Param type formData string true "File type (png, jpg, pdf)"
// @Param file formData file true "File to upload"
// @Success 201 {object} models.Document
// @Router /api/documents/upload [post]
func (h *DocumentHandler) UploadFile(c *gin.Context) {
	projectID, err := primitive.ObjectIDFromHex(c.PostForm("projectId"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid project ID"})
		return
	}

	name := c.PostForm("name")
	path := c.PostForm("path")
	fileType := c.PostForm("type")

	file, header, err := c.Request.FormFile("file")
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "file is required"})
		return
	}
	defer file.Close()

	userID := c.GetString("userID")
	doc, err := h.service.UploadFile(
		c.Request.Context(),
		projectID,
		name,
		path,
		fileType,
		file,
		header.Size,
		userID,
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, doc)
}

// DownloadFile godoc
// @Summary Download a file
// @Tags documents
// @Produce octet-stream
// @Param id path string true "Document ID"
// @Success 200 {file} binary
// @Router /api/documents/{id}/download [get]
func (h *DocumentHandler) DownloadFile(c *gin.Context) {
	id, err := primitive.ObjectIDFromHex(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid document ID"})
		return
	}

	userID := c.GetString("userID")
	reader, filename, err := h.service.DownloadFile(c.Request.Context(), id, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	defer reader.Close()

	c.Header("Content-Disposition", fmt.Sprintf("attachment; filename=%s", filename))
	c.Header("Content-Type", "application/octet-stream")

	io.Copy(c.Writer, reader)
}

// GetProjectTree godoc
// @Summary Get project file tree
// @Tags documents
// @Produce json
// @Param projectId query string true "Project ID"
// @Success 200 {object} models.ProjectTree
// @Router /api/documents/tree [get]
func (h *DocumentHandler) GetProjectTree(c *gin.Context) {
	projectID, err := primitive.ObjectIDFromHex(c.Query("projectId"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid project ID"})
		return
	}

	userID := c.GetString("userID")
	tree, err := h.service.GetProjectTree(c.Request.Context(), projectID, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, tree)
}
```

**Verification**:
```bash
go build ./internal/document/handler/...
```

---

## Task 7: Main Server & Routes (1.5 hours)

### 7.1 Environment Configuration

Create: `cmd/document/.env.example`

```env
# Server
PORT=5002

# MongoDB
MONGODB_URI=mongodb://localhost:27017,localhost:27018,localhost:27019/?replicaSet=rs0
MONGODB_DATABASE=gogolatex

# MinIO
MINIO_ENDPOINT=localhost:9000
MINIO_ACCESS_KEY=minioadmin
MINIO_SECRET_KEY=minioadmin
MINIO_BUCKET=gogolatex
MINIO_USE_SSL=false
MINIO_REGION=us-east-1

# Auth Service
AUTH_SERVICE_URL=http://localhost:5001

# JWT
JWT_SECRET=your-secret-key-change-in-production

# CORS
ALLOWED_ORIGINS=http://localhost:3000,http://localhost:8080
```

### 7.2 Main Server

Create: `cmd/document/main.go`

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
	"github.com/yourusername/gogolatex/internal/database"
	"github.com/yourusername/gogolatex/internal/document/handler"
	"github.com/yourusername/gogolatex/internal/document/repository"
	"github.com/yourusername/gogolatex/internal/document/service"
	"github.com/yourusername/gogolatex/internal/storage"
	"github.com/yourusername/gogolatex/pkg/middleware"
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

	// Initialize MinIO
	minioConfig := storage.LoadMinIOConfig()
	minioStorage, err := storage.NewMinIOStorage(minioConfig)
	if err != nil {
		log.Fatal("Failed to initialize MinIO:", err)
	}
	log.Println("MinIO storage initialized")

	// Initialize repositories
	projectRepo := repository.NewProjectRepository(db)
	documentRepo := repository.NewDocumentRepository(db)

	// Initialize services
	projectService := service.NewProjectService(projectRepo)
	documentService := service.NewDocumentService(documentRepo, projectService, minioStorage)

	// Initialize handlers
	projectHandler := handler.NewProjectHandler(projectService)
	documentHandler := handler.NewDocumentHandler(documentService)

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
		c.JSON(http.StatusOK, gin.H{
			"status":  "healthy",
			"service": "document-service",
			"time":    time.Now(),
		})
	})

	// API routes with authentication
	authMiddleware := middleware.AuthMiddleware(os.Getenv("JWT_SECRET"))
	api := router.Group("/api", authMiddleware)
	{
		// Project routes
		projects := api.Group("/projects")
		{
			projects.POST("", projectHandler.CreateProject)
			projects.GET("", projectHandler.GetUserProjects)
			projects.GET("/shared", projectHandler.GetSharedProjects)
			projects.GET("/recent", projectHandler.GetRecentProjects)
			projects.GET("/:id", projectHandler.GetProject)
			projects.PATCH("/:id", projectHandler.UpdateProject)
			projects.DELETE("/:id", projectHandler.DeleteProject)
			projects.POST("/:id/collaborators", projectHandler.AddCollaborator)
			projects.DELETE("/:id/collaborators/:userId", projectHandler.RemoveCollaborator)
			projects.PATCH("/:id/collaborators/:userId", projectHandler.UpdateCollaboratorRole)
		}

		// Document routes
		documents := api.Group("/documents")
		{
			documents.POST("", documentHandler.CreateDocument)
			documents.GET("", documentHandler.GetProjectDocuments)
			documents.GET("/tree", documentHandler.GetProjectTree)
			documents.GET("/:id", documentHandler.GetDocument)
			documents.PATCH("/:id", documentHandler.UpdateDocument)
			documents.DELETE("/:id", documentHandler.DeleteDocument)
			documents.POST("/upload", documentHandler.UploadFile)
			documents.GET("/:id/download", documentHandler.DownloadFile)
		}
	}

	// Start server
	port := os.Getenv("PORT")
	if port == "" {
		port = "5002"
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
		log.Printf("Document service listening on port %s", port)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatal("Failed to start server:", err)
		}
	}()

	// Wait for interrupt signal
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	log.Println("Shutting down server...")

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	if err := srv.Shutdown(ctx); err != nil {
		log.Fatal("Server forced to shutdown:", err)
	}

	log.Println("Server exited")
}
```

**Verification**:
```bash
cd cmd/document
cp .env.example .env
# Edit .env with your values

# Build
go build -o document-service

# Run
./document-service
```

---

## Task 8: Docker Configuration (45 min)

### 8.1 Update Dockerfile

Update: `docker/go-services/Dockerfile` to support multiple services

```dockerfile
FROM golang:1.21-alpine AS builder

WORKDIR /app

# Install dependencies
RUN apk add --no-cache git

# Copy go mod files
COPY go.mod go.sum ./
RUN go mod download

# Copy source code
COPY . .

# Build the service based on build arg
ARG SERVICE_NAME
RUN go build -o /app/service ./cmd/${SERVICE_NAME}

# Final stage
FROM alpine:latest

WORKDIR /app

# Copy binary from builder
COPY --from=builder /app/service .

# Expose port
EXPOSE 5000

# Run
CMD ["./service"]
```

### 8.2 Update docker-compose.yml

Add document service to: `docker-compose.yml`

```yaml
services:
  # ... existing services ...

  gogolatex-document-service:
    build:
      context: ./backend/go-services
      dockerfile: ../../docker/go-services/Dockerfile
      args:
        SERVICE_NAME: document
    container_name: gogolatex-document-service
    ports:
      - "5002:5002"
    environment:
      PORT: "5002"
      MONGODB_URI: "mongodb://gogolatex-mongodb-1:27017,gogolatex-mongodb-2:27017,gogolatex-mongodb-3:27017/?replicaSet=rs0"
      MONGODB_DATABASE: "gogolatex"
      MINIO_ENDPOINT: "gogolatex-minio:9000"
      MINIO_ACCESS_KEY: "minioadmin"
      MINIO_SECRET_KEY: "changeme_minio"
      MINIO_BUCKET: "gogolatex"
      MINIO_USE_SSL: "false"
      MINIO_REGION: "us-east-1"
      JWT_SECRET: "your-secret-key-change-in-production"
      ALLOWED_ORIGINS: "http://localhost:3000"
    depends_on:
      - gogolatex-mongodb-1
      - gogolatex-mongodb-2
      - gogolatex-mongodb-3
      - gogolatex-minio
    networks:
      - gogolatex
    restart: unless-stopped
```

**Verification**:
```bash
# Build and start document service
docker-compose up -d gogolatex-document-service

# Check logs
docker-compose logs -f gogolatex-document-service

# Test health endpoint
curl http://localhost:5002/health
```

---

## Phase 5 Completion Checklist

### Code Implementation
- [ ] Go project structure created
- [ ] Models defined (Project, Document, Collaborator)
- [ ] MinIO storage service implemented
- [ ] Project repository with MongoDB operations
- [ ] Document repository with MongoDB operations
- [ ] Project service with business logic
- [ ] Document service with business logic
- [ ] HTTP handlers for projects
- [ ] HTTP handlers for documents
- [ ] Main server with routes

### Database
- [ ] MongoDB indexes created
- [ ] Project collection ready
- [ ] Document collection ready
- [ ] Optimistic locking implemented (version field)

### Storage
- [ ] MinIO client configured
- [ ] File upload working
- [ ] File download working
- [ ] Presigned URLs generating
- [ ] Two-tier storage (MongoDB for small files, MinIO for large)

### API Endpoints
- [ ] POST /api/projects - Create project
- [ ] GET /api/projects - List user's projects
- [ ] GET /api/projects/:id - Get project details
- [ ] PATCH /api/projects/:id - Update project
- [ ] DELETE /api/projects/:id - Delete project
- [ ] POST /api/projects/:id/collaborators - Add collaborator
- [ ] DELETE /api/projects/:id/collaborators/:userId - Remove collaborator
- [ ] POST /api/documents - Create document
- [ ] GET /api/documents?projectId=... - List project documents
- [ ] GET /api/documents/:id - Get document content
- [ ] PATCH /api/documents/:id - Update document
- [ ] DELETE /api/documents/:id - Delete document
- [ ] POST /api/documents/upload - Upload binary file
- [ ] GET /api/documents/:id/download - Download file
- [ ] GET /api/documents/tree?projectId=... - Get file tree

### Security
- [ ] JWT authentication middleware working
- [ ] Role-based access control (owner, editor, reviewer, reader)
- [ ] Permission checks on all operations
- [ ] User can only access own/shared projects

### Docker
- [ ] Document service builds successfully
- [ ] Service starts without errors
- [ ] Health check passing
- [ ] Can connect to MongoDB
- [ ] Can connect to MinIO

---

## Troubleshooting

### MongoDB connection fails
**Solution**:
- Verify MongoDB replica set is initialized
- Check `MONGODB_URI` has all three nodes
- Test connection: `docker exec gogolatex-mongodb-1 mongo --eval "rs.status()"`

### MinIO upload fails
**Solution**:
- Check MinIO is running: `docker ps | grep minio`
- Verify credentials in `.env`
- Check bucket exists: `mc ls minio/gogolatex`

### "Access denied" on project
**Solution**:
- Verify JWT token is valid
- Check user is in project collaborators
- Verify middleware is setting `userID` correctly

### Large file upload timeout
**Solution**:
- Increase `ReadTimeout` and `WriteTimeout` in server config
- Consider chunked upload for very large files
- Add progress tracking

---

## Testing

### Manual API Testing

```bash
# Get JWT token from auth service
TOKEN="your-jwt-token"

# Create project
curl -X POST http://localhost:5002/api/projects \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name": "My LaTeX Project", "description": "Test project"}'

# Get user projects
curl http://localhost:5002/api/projects \
  -H "Authorization: Bearer $TOKEN"

# Create document
curl -X POST http://localhost:5002/api/documents \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "projectId": "PROJECT_ID_HERE",
    "name": "main.tex",
    "path": "/main.tex",
    "type": "tex",
    "content": "\\documentclass{article}\n\\begin{document}\nHello World!\n\\end{document}"
  }'

# Upload image
curl -X POST http://localhost:5002/api/documents/upload \
  -H "Authorization: Bearer $TOKEN" \
  -F "projectId=PROJECT_ID_HERE" \
  -F "name=logo.png" \
  -F "path=/images/logo.png" \
  -F "type=png" \
  -F "file=@logo.png"

# Get project tree
curl "http://localhost:5002/api/documents/tree?projectId=PROJECT_ID_HERE" \
  -H "Authorization: Bearer $TOKEN"
```

---

## Next Steps

**Phase 6 Preview**: Compilation Service

In Phase 6, we'll add:
- WASM-based LaTeX compilation for fast, local compilation
- Docker-based TeX Live Full for complex documents
- Compilation queue with worker pool
- PDF generation and caching
- Compilation error parsing and reporting

**Estimated Duration**: 5-6 days

---

## Copilot Tips for Phase 5

1. **Use repository pattern**:
   ```go
   // TODO: Add full-text search for documents
   // TODO: Implement document versioning (save history)
   // TODO: Add document templates
   ```

2. **Ask for enhancements**:
   - "Add bulk document upload endpoint"
   - "Implement project export to ZIP"
   - "Add document move/rename with path update"
   - "Create project clone functionality"

3. **Performance optimizations**:
   - "Add Redis caching for frequently accessed documents"
   - "Implement pagination for large document lists"
   - "Add streaming for large file downloads"

4. **Security improvements**:
   - "Add rate limiting per user"
   - "Implement file type validation"
   - "Add virus scanning for uploads"

---

**End of Phase 5**
