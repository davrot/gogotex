# Phase 7: Advanced Features

**Duration**: 5-6 days  
**Goal**: Git integration, change tracking, comments system, and mobile UI optimization

**Prerequisites**: Phases 1-6 completed, all core services running

---

## Prerequisites

- [ ] Phases 1-6 completed and tested
- [ ] Document service running
- [ ] Real-time collaboration service running
- [ ] MongoDB and Redis available
- [ ] Frontend accessible
- [ ] Git command-line tools available

---

## Task 1: Git Service Setup (2 hours)

### 1.1 Git Service Dependencies

```bash
cd latex-collaborative-editor/backend/node-services/git-service

# Install additional dependencies
npm install simple-git
npm install diff
npm install isomorphic-git  # Alternative pure-JS implementation
npm install diff-match-patch
```

Update: `package.json`

```json
{
  "name": "git-service",
  "version": "1.0.0",
  "description": "Git integration service for GogoLaTeX",
  "main": "dist/server.js",
  "scripts": {
    "build": "tsc",
    "start": "node dist/server.js",
    "dev": "ts-node-dev --respawn src/server.ts",
    "test": "jest"
  },
  "dependencies": {
    "express": "^4.18.2",
    "cors": "^2.8.5",
    "axios": "^1.6.0",
    "simple-git": "^3.21.0",
    "isomorphic-git": "^1.25.0",
    "diff": "^5.1.0",
    "diff-match-patch": "^1.0.5",
    "winston": "^3.11.0",
    "dotenv": "^16.3.1"
  },
  "devDependencies": {
    "@types/express": "^4.17.21",
    "@types/cors": "^2.8.17",
    "@types/node": "^20.10.0",
    "@types/diff": "^5.0.9",
    "typescript": "^5.3.2",
    "ts-node-dev": "^2.0.0"
  }
}
```

### 1.2 Git Configuration

Create: `src/config/git-config.ts`

```typescript
import path from 'path'

export interface GitConfig {
  repoBasePath: string
  defaultBranch: string
  maxCommitSize: number
  allowedFileTypes: string[]
  authorName: string
  authorEmail: string
}

export const gitConfig: GitConfig = {
  repoBasePath: process.env.GIT_REPO_PATH || '/var/lib/gogolatex/git-repos',
  defaultBranch: 'main',
  maxCommitSize: 50 * 1024 * 1024, // 50MB
  allowedFileTypes: ['.tex', '.bib', '.cls', '.sty', '.png', '.jpg', '.pdf'],
  authorName: process.env.GIT_AUTHOR_NAME || 'GogoLaTeX',
  authorEmail: process.env.GIT_AUTHOR_EMAIL || 'noreply@gogolatex.local',
}

export function getProjectRepoPath(projectId: string): string {
  return path.join(gitConfig.repoBasePath, projectId)
}
```

### 1.3 Git Service Types

Create: `src/types/git.ts`

```typescript
export interface CommitInfo {
  hash: string
  message: string
  author: {
    name: string
    email: string
  }
  date: Date
  files: string[]
}

export interface DiffResult {
  file: string
  additions: number
  deletions: number
  changes: FileDiff[]
}

export interface FileDiff {
  type: 'add' | 'remove' | 'context'
  lineNumber: number
  content: string
}

export interface BranchInfo {
  name: string
  commit: string
  isCurrentBranch: boolean
}

export interface GitStatus {
  modified: string[]
  added: string[]
  deleted: string[]
  renamed: { from: string; to: string }[]
  conflicted: string[]
}

export interface MergeResult {
  success: boolean
  conflicts: string[]
  message: string
}
```

**Verification**:
```bash
npm install
npm run build
```

---

## Task 2: Git Operations Service (3 hours)

### 2.1 Git Manager

Create: `src/services/git-manager.ts`

```typescript
import simpleGit, { SimpleGit, SimpleGitOptions } from 'simple-git'
import fs from 'fs/promises'
import path from 'path'
import { gitConfig, getProjectRepoPath } from '../config/git-config'
import { CommitInfo, DiffResult, BranchInfo, GitStatus, MergeResult, FileDiff } from '../types/git'
import * as Diff from 'diff'

export class GitManager {
  private git: SimpleGit

  constructor(projectId: string) {
    const repoPath = getProjectRepoPath(projectId)
    const options: Partial<SimpleGitOptions> = {
      baseDir: repoPath,
      binary: 'git',
      maxConcurrentProcesses: 6,
    }
    this.git = simpleGit(options)
  }

  /**
   * Initialize a new Git repository for a project
   */
  async initRepository(projectId: string): Promise<void> {
    const repoPath = getProjectRepoPath(projectId)

    // Create directory if it doesn't exist
    await fs.mkdir(repoPath, { recursive: true })

    // Check if already initialized
    const isRepo = await this.git.checkIsRepo()
    if (isRepo) {
      console.log(`Repository already initialized: ${projectId}`)
      return
    }

    // Initialize git repo
    await this.git.init()

    // Set default branch
    await this.git.raw(['branch', '-M', gitConfig.defaultBranch])

    // Create initial commit
    await fs.writeFile(
      path.join(repoPath, 'README.md'),
      `# LaTeX Project\n\nCreated with GogoLaTeX\n`
    )

    await this.git.add('README.md')
    await this.git.commit('Initial commit', {
      '--author': `"${gitConfig.authorName} <${gitConfig.authorEmail}>"`,
    })

    console.log(`Repository initialized: ${projectId}`)
  }

  /**
   * Commit changes to the repository
   */
  async commit(
    message: string,
    files: string[],
    author: { name: string; email: string }
  ): Promise<string> {
    // Add files
    await this.git.add(files)

    // Commit with author info
    const result = await this.git.commit(message, {
      '--author': `"${author.name} <${author.email}>"`,
    })

    return result.commit
  }

  /**
   * Get commit history
   */
  async getCommitHistory(limit: number = 50, branch?: string): Promise<CommitInfo[]> {
    const log = await this.git.log({
      maxCount: limit,
      ...(branch && { from: branch }),
    })

    return log.all.map((commit) => ({
      hash: commit.hash,
      message: commit.message,
      author: {
        name: commit.author_name,
        email: commit.author_email,
      },
      date: new Date(commit.date),
      files: commit.diff?.files.map((f) => f.file) || [],
    }))
  }

  /**
   * Get a specific commit
   */
  async getCommit(commitHash: string): Promise<CommitInfo | null> {
    try {
      const log = await this.git.log({ from: commitHash, to: commitHash })
      if (log.all.length === 0) return null

      const commit = log.all[0]
      return {
        hash: commit.hash,
        message: commit.message,
        author: {
          name: commit.author_name,
          email: commit.author_email,
        },
        date: new Date(commit.date),
        files: commit.diff?.files.map((f) => f.file) || [],
      }
    } catch (error) {
      return null
    }
  }

  /**
   * Get diff between two commits
   */
  async getDiff(fromCommit: string, toCommit: string = 'HEAD'): Promise<DiffResult[]> {
    const diffSummary = await this.git.diffSummary([fromCommit, toCommit])

    const results: DiffResult[] = []

    for (const file of diffSummary.files) {
      // Get detailed diff for each file
      const diffOutput = await this.git.diff([fromCommit, toCommit, '--', file.file])
      const changes = this.parseDiff(diffOutput)

      results.push({
        file: file.file,
        additions: file.insertions,
        deletions: file.deletions,
        changes,
      })
    }

    return results
  }

  /**
   * Parse diff output into structured format
   */
  private parseDiff(diffOutput: string): FileDiff[] {
    const changes: FileDiff[] = []
    const lines = diffOutput.split('\n')

    let lineNumber = 0
    for (const line of lines) {
      if (line.startsWith('@@')) {
        // Parse line number from hunk header
        const match = line.match(/@@ -\d+,?\d* \+(\d+),?\d* @@/)
        if (match) {
          lineNumber = parseInt(match[1], 10)
        }
        continue
      }

      if (line.startsWith('+') && !line.startsWith('+++')) {
        changes.push({
          type: 'add',
          lineNumber: lineNumber++,
          content: line.substring(1),
        })
      } else if (line.startsWith('-') && !line.startsWith('---')) {
        changes.push({
          type: 'remove',
          lineNumber: lineNumber,
          content: line.substring(1),
        })
      } else if (line.startsWith(' ')) {
        changes.push({
          type: 'context',
          lineNumber: lineNumber++,
          content: line.substring(1),
        })
      }
    }

    return changes
  }

  /**
   * Get repository status
   */
  async getStatus(): Promise<GitStatus> {
    const status = await this.git.status()

    return {
      modified: status.modified,
      added: status.created,
      deleted: status.deleted,
      renamed: status.renamed.map((r) => ({ from: r.from, to: r.to })),
      conflicted: status.conflicted,
    }
  }

  /**
   * Create a new branch
   */
  async createBranch(branchName: string, fromBranch?: string): Promise<void> {
    if (fromBranch) {
      await this.git.checkoutBranch(branchName, fromBranch)
    } else {
      await this.git.checkoutLocalBranch(branchName)
    }
  }

  /**
   * Switch to a branch
   */
  async checkoutBranch(branchName: string): Promise<void> {
    await this.git.checkout(branchName)
  }

  /**
   * List all branches
   */
  async listBranches(): Promise<BranchInfo[]> {
    const branchSummary = await this.git.branch()

    return Object.entries(branchSummary.branches).map(([name, branch]) => ({
      name,
      commit: branch.commit,
      isCurrentBranch: name === branchSummary.current,
    }))
  }

  /**
   * Merge a branch into current branch
   */
  async mergeBranch(branchName: string, message?: string): Promise<MergeResult> {
    try {
      const result = await this.git.merge([branchName, ...(message ? ['-m', message] : [])])

      return {
        success: !result.failed,
        conflicts: result.conflicts || [],
        message: result.failed ? 'Merge failed with conflicts' : 'Merge successful',
      }
    } catch (error: any) {
      return {
        success: false,
        conflicts: [],
        message: error.message || 'Merge failed',
      }
    }
  }

  /**
   * Revert a commit
   */
  async revertCommit(commitHash: string): Promise<string> {
    const result = await this.git.revert(commitHash, { '--no-edit': null })
    return result
  }

  /**
   * Reset to a specific commit
   */
  async resetToCommit(commitHash: string, hard: boolean = false): Promise<void> {
    if (hard) {
      await this.git.reset(['--hard', commitHash])
    } else {
      await this.git.reset(['--soft', commitHash])
    }
  }

  /**
   * Get file content at specific commit
   */
  async getFileAtCommit(commitHash: string, filePath: string): Promise<string> {
    const content = await this.git.show([`${commitHash}:${filePath}`])
    return content
  }

  /**
   * Blame a file (show who changed each line)
   */
  async blameFile(filePath: string): Promise<any> {
    const blame = await this.git.raw(['blame', '--line-porcelain', filePath])
    // Parse blame output (complex format)
    return blame
  }

  /**
   * Search commits by message
   */
  async searchCommits(query: string, limit: number = 50): Promise<CommitInfo[]> {
    const log = await this.git.log({
      maxCount: limit,
      '--grep': query,
    })

    return log.all.map((commit) => ({
      hash: commit.hash,
      message: commit.message,
      author: {
        name: commit.author_name,
        email: commit.author_email,
      },
      date: new Date(commit.date),
      files: commit.diff?.files.map((f) => f.file) || [],
    }))
  }

  /**
   * Get statistics for a commit
   */
  async getCommitStats(commitHash: string): Promise<any> {
    const stats = await this.git.show(['--stat', commitHash])
    return stats
  }
}
```

### 2.2 Git Operations Controller

Create: `src/controllers/git-controller.ts`

```typescript
import { Request, Response } from 'express'
import { GitManager } from '../services/git-manager'

export class GitController {
  /**
   * Initialize repository for a project
   */
  async initRepository(req: Request, res: Response) {
    try {
      const { projectId } = req.params
      const gitManager = new GitManager(projectId)
      await gitManager.initRepository(projectId)

      res.json({ success: true, message: 'Repository initialized' })
    } catch (error: any) {
      console.error('Init repository error:', error)
      res.status(500).json({ error: error.message })
    }
  }

  /**
   * Commit changes
   */
  async commit(req: Request, res: Response) {
    try {
      const { projectId } = req.params
      const { message, files, author } = req.body

      if (!message || !files || !author) {
        return res.status(400).json({ error: 'Missing required fields' })
      }

      const gitManager = new GitManager(projectId)
      const commitHash = await gitManager.commit(message, files, author)

      res.json({ success: true, commitHash })
    } catch (error: any) {
      console.error('Commit error:', error)
      res.status(500).json({ error: error.message })
    }
  }

  /**
   * Get commit history
   */
  async getHistory(req: Request, res: Response) {
    try {
      const { projectId } = req.params
      const limit = parseInt(req.query.limit as string) || 50
      const branch = req.query.branch as string

      const gitManager = new GitManager(projectId)
      const history = await gitManager.getCommitHistory(limit, branch)

      res.json({ commits: history })
    } catch (error: any) {
      console.error('Get history error:', error)
      res.status(500).json({ error: error.message })
    }
  }

  /**
   * Get specific commit
   */
  async getCommit(req: Request, res: Response) {
    try {
      const { projectId, commitHash } = req.params

      const gitManager = new GitManager(projectId)
      const commit = await gitManager.getCommit(commitHash)

      if (!commit) {
        return res.status(404).json({ error: 'Commit not found' })
      }

      res.json({ commit })
    } catch (error: any) {
      console.error('Get commit error:', error)
      res.status(500).json({ error: error.message })
    }
  }

  /**
   * Get diff between commits
   */
  async getDiff(req: Request, res: Response) {
    try {
      const { projectId } = req.params
      const { from, to } = req.query

      if (!from) {
        return res.status(400).json({ error: 'Missing from commit' })
      }

      const gitManager = new GitManager(projectId)
      const diff = await gitManager.getDiff(from as string, to as string)

      res.json({ diff })
    } catch (error: any) {
      console.error('Get diff error:', error)
      res.status(500).json({ error: error.message })
    }
  }

  /**
   * Get repository status
   */
  async getStatus(req: Request, res: Response) {
    try {
      const { projectId } = req.params

      const gitManager = new GitManager(projectId)
      const status = await gitManager.getStatus()

      res.json({ status })
    } catch (error: any) {
      console.error('Get status error:', error)
      res.status(500).json({ error: error.message })
    }
  }

  /**
   * Create branch
   */
  async createBranch(req: Request, res: Response) {
    try {
      const { projectId } = req.params
      const { branchName, fromBranch } = req.body

      if (!branchName) {
        return res.status(400).json({ error: 'Missing branch name' })
      }

      const gitManager = new GitManager(projectId)
      await gitManager.createBranch(branchName, fromBranch)

      res.json({ success: true, message: 'Branch created' })
    } catch (error: any) {
      console.error('Create branch error:', error)
      res.status(500).json({ error: error.message })
    }
  }

  /**
   * List branches
   */
  async listBranches(req: Request, res: Response) {
    try {
      const { projectId } = req.params

      const gitManager = new GitManager(projectId)
      const branches = await gitManager.listBranches()

      res.json({ branches })
    } catch (error: any) {
      console.error('List branches error:', error)
      res.status(500).json({ error: error.message })
    }
  }

  /**
   * Merge branch
   */
  async mergeBranch(req: Request, res: Response) {
    try {
      const { projectId } = req.params
      const { branchName, message } = req.body

      if (!branchName) {
        return res.status(400).json({ error: 'Missing branch name' })
      }

      const gitManager = new GitManager(projectId)
      const result = await gitManager.mergeBranch(branchName, message)

      res.json(result)
    } catch (error: any) {
      console.error('Merge branch error:', error)
      res.status(500).json({ error: error.message })
    }
  }

  /**
   * Checkout branch
   */
  async checkoutBranch(req: Request, res: Response) {
    try {
      const { projectId } = req.params
      const { branchName } = req.body

      if (!branchName) {
        return res.status(400).json({ error: 'Missing branch name' })
      }

      const gitManager = new GitManager(projectId)
      await gitManager.checkoutBranch(branchName)

      res.json({ success: true, message: 'Checked out branch' })
    } catch (error: any) {
      console.error('Checkout branch error:', error)
      res.status(500).json({ error: error.message })
    }
  }

  /**
   * Revert commit
   */
  async revertCommit(req: Request, res: Response) {
    try {
      const { projectId, commitHash } = req.params

      const gitManager = new GitManager(projectId)
      const result = await gitManager.revertCommit(commitHash)

      res.json({ success: true, result })
    } catch (error: any) {
      console.error('Revert commit error:', error)
      res.status(500).json({ error: error.message })
    }
  }

  /**
   * Get file at specific commit
   */
  async getFileAtCommit(req: Request, res: Response) {
    try {
      const { projectId, commitHash } = req.params
      const { filePath } = req.query

      if (!filePath) {
        return res.status(400).json({ error: 'Missing file path' })
      }

      const gitManager = new GitManager(projectId)
      const content = await gitManager.getFileAtCommit(commitHash, filePath as string)

      res.json({ content })
    } catch (error: any) {
      console.error('Get file at commit error:', error)
      res.status(500).json({ error: error.message })
    }
  }
}
```

**Verification**:
```bash
npm run build
```

---

## Task 3: Change Tracking Models (1.5 hours)

### 3.1 MongoDB Models

Create: `internal/models/change_tracking.go`

```go
package models

import (
	"time"

	"go.mongodb.org/mongo-driver/bson/primitive"
)

// DocumentChange represents a tracked change in a document
type DocumentChange struct {
	ID             primitive.ObjectID `bson:"_id,omitempty" json:"id"`
	DocumentID     primitive.ObjectID `bson:"documentId" json:"documentId"`
	ProjectID      primitive.ObjectID `bson:"projectId" json:"projectId"`
	UserID         string             `bson:"userId" json:"userId"`
	UserName       string             `bson:"userName" json:"userName"`
	UserEmail      string             `bson:"userEmail" json:"userEmail"`
	ChangeType     string             `bson:"changeType" json:"changeType"` // insert, delete, replace
	Position       int                `bson:"position" json:"position"`     // Character position
	Length         int                `bson:"length" json:"length"`         // Length of change
	OldText        string             `bson:"oldText,omitempty" json:"oldText,omitempty"`
	NewText        string             `bson:"newText,omitempty" json:"newText,omitempty"`
	AcceptedBy     string             `bson:"acceptedBy,omitempty" json:"acceptedBy,omitempty"`
	RejectedBy     string             `bson:"rejectedBy,omitempty" json:"rejectedBy,omitempty"`
	Status         string             `bson:"status" json:"status"` // pending, accepted, rejected
	Timestamp      time.Time          `bson:"timestamp" json:"timestamp"`
	SessionID      string             `bson:"sessionId,omitempty" json:"sessionId,omitempty"`
}

// ChangeType constants
const (
	ChangeTypeInsert  = "insert"
	ChangeTypeDelete  = "delete"
	ChangeTypeReplace = "replace"
)

// ChangeStatus constants
const (
	ChangeStatusPending  = "pending"
	ChangeStatusAccepted = "accepted"
	ChangeStatusRejected = "rejected"
)

// CreateChangeRequest for API
type CreateChangeRequest struct {
	DocumentID primitive.ObjectID `json:"documentId" validate:"required"`
	ChangeType string             `json:"changeType" validate:"required,oneof=insert delete replace"`
	Position   int                `json:"position" validate:"required,min=0"`
	Length     int                `json:"length" validate:"required,min=0"`
	OldText    string             `json:"oldText,omitempty"`
	NewText    string             `json:"newText,omitempty"`
}

// AcceptChangeRequest for API
type AcceptChangeRequest struct {
	ChangeID primitive.ObjectID `json:"changeId" validate:"required"`
}

// RejectChangeRequest for API
type RejectChangeRequest struct {
	ChangeID primitive.ObjectID `json:"changeId" validate:"required"`
	Reason   string             `json:"reason,omitempty"`
}

// ChangeStatistics for analytics
type ChangeStatistics struct {
	TotalChanges    int64 `json:"totalChanges"`
	PendingChanges  int64 `json:"pendingChanges"`
	AcceptedChanges int64 `json:"acceptedChanges"`
	RejectedChanges int64 `json:"rejectedChanges"`
	ByUser          map[string]int64 `json:"byUser"`
}
```

### 3.2 Comment Model

Create: `internal/models/comment.go`

```go
package models

import (
	"time"

	"go.mongodb.org/mongo-driver/bson/primitive"
)

// Comment represents a comment on a document
type Comment struct {
	ID         primitive.ObjectID `bson:"_id,omitempty" json:"id"`
	DocumentID primitive.ObjectID `bson:"documentId" json:"documentId"`
	ProjectID  primitive.ObjectID `bson:"projectId" json:"projectId"`
	UserID     string             `bson:"userId" json:"userId"`
	UserName   string             `bson:"userName" json:"userName"`
	UserEmail  string             `bson:"userEmail" json:"userEmail"`
	Content    string             `bson:"content" json:"content" validate:"required,min=1,max=10000"`
	Position   CommentPosition    `bson:"position" json:"position"`
	ParentID   primitive.ObjectID `bson:"parentId,omitempty" json:"parentId,omitempty"` // For replies
	Resolved   bool               `bson:"resolved" json:"resolved"`
	ResolvedBy string             `bson:"resolvedBy,omitempty" json:"resolvedBy,omitempty"`
	ResolvedAt *time.Time         `bson:"resolvedAt,omitempty" json:"resolvedAt,omitempty"`
	CreatedAt  time.Time          `bson:"createdAt" json:"createdAt"`
	UpdatedAt  time.Time          `bson:"updatedAt" json:"updatedAt"`
	IsDeleted  bool               `bson:"isDeleted" json:"isDeleted"`
}

// CommentPosition represents where a comment is anchored
type CommentPosition struct {
	Line      int    `bson:"line" json:"line"`
	Character int    `bson:"character" json:"character"`
	Text      string `bson:"text,omitempty" json:"text,omitempty"` // Selected text
}

// CreateCommentRequest for API
type CreateCommentRequest struct {
	DocumentID primitive.ObjectID `json:"documentId" validate:"required"`
	Content    string             `json:"content" validate:"required,min=1,max=10000"`
	Position   CommentPosition    `json:"position" validate:"required"`
	ParentID   primitive.ObjectID `json:"parentId,omitempty"`
}

// UpdateCommentRequest for API
type UpdateCommentRequest struct {
	Content string `json:"content" validate:"required,min=1,max=10000"`
}

// ResolveCommentRequest for API
type ResolveCommentRequest struct {
	Resolved bool `json:"resolved"`
}

// CommentThread represents a comment with its replies
type CommentThread struct {
	Comment Comment   `json:"comment"`
	Replies []Comment `json:"replies"`
}
```

**Verification**:
```bash
go build ./internal/models/...
```

---

## Task 4: Change Tracking Service (2.5 hours)

### 4.1 Change Tracking Repository

Create: `internal/tracking/repository/change_repository.go`

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

// ChangeRepository handles document change database operations
type ChangeRepository struct {
	collection *mongo.Collection
}

// NewChangeRepository creates a new change repository
func NewChangeRepository(db *mongo.Database) *ChangeRepository {
	collection := db.Collection("document_changes")

	// Create indexes
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	// Index on documentId for fast document change queries
	collection.Indexes().CreateOne(ctx, mongo.IndexModel{
		Keys: bson.D{{Key: "documentId", Value: 1}},
	})

	// Index on projectId for project-wide queries
	collection.Indexes().CreateOne(ctx, mongo.IndexModel{
		Keys: bson.D{{Key: "projectId", Value: 1}},
	})

	// Index on userId for user activity
	collection.Indexes().CreateOne(ctx, mongo.IndexModel{
		Keys: bson.D{{Key: "userId", Value: 1}},
	})

	// Index on status for filtering
	collection.Indexes().CreateOne(ctx, mongo.IndexModel{
		Keys: bson.D{{Key: "status", Value: 1}},
	})

	// Compound index for document and status
	collection.Indexes().CreateOne(ctx, mongo.IndexModel{
		Keys: bson.D{
			{Key: "documentId", Value: 1},
			{Key: "status", Value: 1},
		},
	})

	return &ChangeRepository{
		collection: collection,
	}
}

// Create creates a new document change
func (r *ChangeRepository) Create(ctx context.Context, change *models.DocumentChange) error {
	change.Timestamp = time.Now()
	change.Status = models.ChangeStatusPending

	result, err := r.collection.InsertOne(ctx, change)
	if err != nil {
		return fmt.Errorf("failed to create change: %w", err)
	}

	change.ID = result.InsertedID.(primitive.ObjectID)
	return nil
}

// FindByID finds a change by ID
func (r *ChangeRepository) FindByID(ctx context.Context, id primitive.ObjectID) (*models.DocumentChange, error) {
	var change models.DocumentChange
	err := r.collection.FindOne(ctx, bson.M{"_id": id}).Decode(&change)
	if err != nil {
		if err == mongo.ErrNoDocuments {
			return nil, fmt.Errorf("change not found")
		}
		return nil, fmt.Errorf("failed to find change: %w", err)
	}

	return &change, nil
}

// FindByDocumentID finds all changes for a document
func (r *ChangeRepository) FindByDocumentID(ctx context.Context, documentID primitive.ObjectID, status string) ([]models.DocumentChange, error) {
	filter := bson.M{"documentId": documentID}
	if status != "" {
		filter["status"] = status
	}

	opts := options.Find().SetSort(bson.D{{Key: "timestamp", Value: 1}})

	cursor, err := r.collection.Find(ctx, filter, opts)
	if err != nil {
		return nil, fmt.Errorf("failed to find changes: %w", err)
	}
	defer cursor.Close(ctx)

	var changes []models.DocumentChange
	if err := cursor.All(ctx, &changes); err != nil {
		return nil, fmt.Errorf("failed to decode changes: %w", err)
	}

	return changes, nil
}

// FindByProjectID finds all changes for a project
func (r *ChangeRepository) FindByProjectID(ctx context.Context, projectID primitive.ObjectID, limit int64) ([]models.DocumentChange, error) {
	opts := options.Find().
		SetSort(bson.D{{Key: "timestamp", Value: -1}}).
		SetLimit(limit)

	cursor, err := r.collection.Find(ctx, bson.M{"projectId": projectID}, opts)
	if err != nil {
		return nil, fmt.Errorf("failed to find changes: %w", err)
	}
	defer cursor.Close(ctx)

	var changes []models.DocumentChange
	if err := cursor.All(ctx, &changes); err != nil {
		return nil, fmt.Errorf("failed to decode changes: %w", err)
	}

	return changes, nil
}

// AcceptChange marks a change as accepted
func (r *ChangeRepository) AcceptChange(ctx context.Context, changeID primitive.ObjectID, userID string) error {
	_, err := r.collection.UpdateOne(
		ctx,
		bson.M{"_id": changeID},
		bson.M{"$set": bson.M{
			"status":     models.ChangeStatusAccepted,
			"acceptedBy": userID,
		}},
	)
	return err
}

// RejectChange marks a change as rejected
func (r *ChangeRepository) RejectChange(ctx context.Context, changeID primitive.ObjectID, userID string) error {
	_, err := r.collection.UpdateOne(
		ctx,
		bson.M{"_id": changeID},
		bson.M{"$set": bson.M{
			"status":     models.ChangeStatusRejected,
			"rejectedBy": userID,
		}},
	)
	return err
}

// GetStatistics returns change statistics for a project
func (r *ChangeRepository) GetStatistics(ctx context.Context, projectID primitive.ObjectID) (*models.ChangeStatistics, error) {
	stats := &models.ChangeStatistics{
		ByUser: make(map[string]int64),
	}

	// Total changes
	total, _ := r.collection.CountDocuments(ctx, bson.M{"projectId": projectID})
	stats.TotalChanges = total

	// Count by status
	statuses := []string{models.ChangeStatusPending, models.ChangeStatusAccepted, models.ChangeStatusRejected}
	for _, status := range statuses {
		count, _ := r.collection.CountDocuments(ctx, bson.M{
			"projectId": projectID,
			"status":    status,
		})
		
		switch status {
		case models.ChangeStatusPending:
			stats.PendingChanges = count
		case models.ChangeStatusAccepted:
			stats.AcceptedChanges = count
		case models.ChangeStatusRejected:
			stats.RejectedChanges = count
		}
	}

	// Count by user
	pipeline := mongo.Pipeline{
		{{Key: "$match", Value: bson.M{"projectId": projectID}}},
		{{Key: "$group", Value: bson.M{
			"_id":   "$userId",
			"count": bson.M{"$sum": 1},
		}}},
	}

	cursor, err := r.collection.Aggregate(ctx, pipeline)
	if err == nil {
		defer cursor.Close(ctx)
		
		for cursor.Next(ctx) {
			var result struct {
				UserID string `bson:"_id"`
				Count  int64  `bson:"count"`
			}
			if err := cursor.Decode(&result); err == nil {
				stats.ByUser[result.UserID] = result.Count
			}
		}
	}

	return stats, nil
}

// DeleteByDocumentID deletes all changes for a document
func (r *ChangeRepository) DeleteByDocumentID(ctx context.Context, documentID primitive.ObjectID) error {
	_, err := r.collection.DeleteMany(ctx, bson.M{"documentId": documentID})
	return err
}
```

### 4.2 Change Tracking Service

Create: `internal/tracking/service/change_service.go`

```go
package service

import (
	"context"
	"fmt"

	"github.com/yourusername/gogolatex/internal/models"
	"github.com/yourusername/gogolatex/internal/tracking/repository"
	"go.mongodb.org/mongo-driver/bson/primitive"
)

// ChangeService handles change tracking business logic
type ChangeService struct {
	repo *repository.ChangeRepository
}

// NewChangeService creates a new change service
func NewChangeService(repo *repository.ChangeRepository) *ChangeService {
	return &ChangeService{
		repo: repo,
	}
}

// CreateChange creates a new document change
func (s *ChangeService) CreateChange(ctx context.Context, req *models.CreateChangeRequest, user *models.User) (*models.DocumentChange, error) {
	change := &models.DocumentChange{
		DocumentID: req.DocumentID,
		// ProjectID will be set by looking up the document
		UserID:     user.ID,
		UserName:   user.Name,
		UserEmail:  user.Email,
		ChangeType: req.ChangeType,
		Position:   req.Position,
		Length:     req.Length,
		OldText:    req.OldText,
		NewText:    req.NewText,
	}

	if err := s.repo.Create(ctx, change); err != nil {
		return nil, err
	}

	return change, nil
}

// GetDocumentChanges gets all changes for a document
func (s *ChangeService) GetDocumentChanges(ctx context.Context, documentID primitive.ObjectID, status string) ([]models.DocumentChange, error) {
	return s.repo.FindByDocumentID(ctx, documentID, status)
}

// GetProjectChanges gets all changes for a project
func (s *ChangeService) GetProjectChanges(ctx context.Context, projectID primitive.ObjectID, limit int64) ([]models.DocumentChange, error) {
	if limit == 0 {
		limit = 100
	}
	return s.repo.FindByProjectID(ctx, projectID, limit)
}

// AcceptChange accepts a pending change
func (s *ChangeService) AcceptChange(ctx context.Context, changeID primitive.ObjectID, userID string) error {
	// Get the change
	change, err := s.repo.FindByID(ctx, changeID)
	if err != nil {
		return err
	}

	if change.Status != models.ChangeStatusPending {
		return fmt.Errorf("change is not pending")
	}

	// TODO: Check user has permission to accept changes

	// Accept the change
	return s.repo.AcceptChange(ctx, changeID, userID)
}

// RejectChange rejects a pending change
func (s *ChangeService) RejectChange(ctx context.Context, changeID primitive.ObjectID, userID string) error {
	// Get the change
	change, err := s.repo.FindByID(ctx, changeID)
	if err != nil {
		return err
	}

	if change.Status != models.ChangeStatusPending {
		return fmt.Errorf("change is not pending")
	}

	// TODO: Check user has permission to reject changes

	// Reject the change
	return s.repo.RejectChange(ctx, changeID, userID)
}

// GetStatistics returns change statistics for a project
func (s *ChangeService) GetStatistics(ctx context.Context, projectID primitive.ObjectID) (*models.ChangeStatistics, error) {
	return s.repo.GetStatistics(ctx, projectID)
}
```

**Verification**:
```bash
go build ./internal/tracking/...
```

---

## Task 5: Comments System (2.5 hours)

### 5.1 Comment Repository

Create: `internal/comments/repository/comment_repository.go`

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

// CommentRepository handles comment database operations
type CommentRepository struct {
	collection *mongo.Collection
}

// NewCommentRepository creates a new comment repository
func NewCommentRepository(db *mongo.Database) *CommentRepository {
	collection := db.Collection("comments")

	// Create indexes
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	// Index on documentId
	collection.Indexes().CreateOne(ctx, mongo.IndexModel{
		Keys: bson.D{{Key: "documentId", Value: 1}},
	})

	// Index on projectId
	collection.Indexes().CreateOne(ctx, mongo.IndexModel{
		Keys: bson.D{{Key: "projectId", Value: 1}},
	})

	// Index on parentId for replies
	collection.Indexes().CreateOne(ctx, mongo.IndexModel{
		Keys: bson.D{{Key: "parentId", Value: 1}},
	})

	// Compound index for document and resolved status
	collection.Indexes().CreateOne(ctx, mongo.IndexModel{
		Keys: bson.D{
			{Key: "documentId", Value: 1},
			{Key: "resolved", Value: 1},
			{Key: "isDeleted", Value: 1},
		},
	})

	return &CommentRepository{
		collection: collection,
	}
}

// Create creates a new comment
func (r *CommentRepository) Create(ctx context.Context, comment *models.Comment) error {
	now := time.Now()
	comment.CreatedAt = now
	comment.UpdatedAt = now
	comment.IsDeleted = false

	result, err := r.collection.InsertOne(ctx, comment)
	if err != nil {
		return fmt.Errorf("failed to create comment: %w", err)
	}

	comment.ID = result.InsertedID.(primitive.ObjectID)
	return nil
}

// FindByID finds a comment by ID
func (r *CommentRepository) FindByID(ctx context.Context, id primitive.ObjectID) (*models.Comment, error) {
	var comment models.Comment
	err := r.collection.FindOne(ctx, bson.M{
		"_id":       id,
		"isDeleted": false,
	}).Decode(&comment)
	
	if err != nil {
		if err == mongo.ErrNoDocuments {
			return nil, fmt.Errorf("comment not found")
		}
		return nil, fmt.Errorf("failed to find comment: %w", err)
	}

	return &comment, nil
}

// FindByDocumentID finds all comments for a document
func (r *CommentRepository) FindByDocumentID(ctx context.Context, documentID primitive.ObjectID, includeResolved bool) ([]models.Comment, error) {
	filter := bson.M{
		"documentId": documentID,
		"isDeleted":  false,
	}

	if !includeResolved {
		filter["resolved"] = false
	}

	opts := options.Find().SetSort(bson.D{{Key: "createdAt", Value: 1}})

	cursor, err := r.collection.Find(ctx, filter, opts)
	if err != nil {
		return nil, fmt.Errorf("failed to find comments: %w", err)
	}
	defer cursor.Close(ctx)

	var comments []models.Comment
	if err := cursor.All(ctx, &comments); err != nil {
		return nil, fmt.Errorf("failed to decode comments: %w", err)
	}

	return comments, nil
}

// FindThreadsByDocumentID finds all comment threads (comments with replies)
func (r *CommentRepository) FindThreadsByDocumentID(ctx context.Context, documentID primitive.ObjectID, includeResolved bool) ([]models.CommentThread, error) {
	// Find all top-level comments (no parentId)
	filter := bson.M{
		"documentId": documentID,
		"isDeleted":  false,
		"parentId":   bson.M{"$exists": false},
	}

	if !includeResolved {
		filter["resolved"] = false
	}

	opts := options.Find().SetSort(bson.D{{Key: "createdAt", Value: 1}})

	cursor, err := r.collection.Find(ctx, filter, opts)
	if err != nil {
		return nil, fmt.Errorf("failed to find comments: %w", err)
	}
	defer cursor.Close(ctx)

	var threads []models.CommentThread

	for cursor.Next(ctx) {
		var comment models.Comment
		if err := cursor.Decode(&comment); err != nil {
			continue
		}

		// Find replies for this comment
		replies, _ := r.FindReplies(ctx, comment.ID)

		threads = append(threads, models.CommentThread{
			Comment: comment,
			Replies: replies,
		})
	}

	return threads, nil
}

// FindReplies finds all replies to a comment
func (r *CommentRepository) FindReplies(ctx context.Context, parentID primitive.ObjectID) ([]models.Comment, error) {
	opts := options.Find().SetSort(bson.D{{Key: "createdAt", Value: 1}})

	cursor, err := r.collection.Find(ctx, bson.M{
		"parentId":  parentID,
		"isDeleted": false,
	}, opts)
	if err != nil {
		return nil, fmt.Errorf("failed to find replies: %w", err)
	}
	defer cursor.Close(ctx)

	var replies []models.Comment
	if err := cursor.All(ctx, &replies); err != nil {
		return nil, fmt.Errorf("failed to decode replies: %w", err)
	}

	return replies, nil
}

// Update updates a comment
func (r *CommentRepository) Update(ctx context.Context, id primitive.ObjectID, content string) error {
	_, err := r.collection.UpdateOne(
		ctx,
		bson.M{"_id": id, "isDeleted": false},
		bson.M{"$set": bson.M{
			"content":   content,
			"updatedAt": time.Now(),
		}},
	)
	return err
}

// Resolve marks a comment as resolved
func (r *CommentRepository) Resolve(ctx context.Context, id primitive.ObjectID, userID string, resolved bool) error {
	update := bson.M{
		"resolved":  resolved,
		"updatedAt": time.Now(),
	}

	if resolved {
		now := time.Now()
		update["resolvedBy"] = userID
		update["resolvedAt"] = now
	} else {
		update["resolvedBy"] = nil
		update["resolvedAt"] = nil
	}

	_, err := r.collection.UpdateOne(
		ctx,
		bson.M{"_id": id, "isDeleted": false},
		bson.M{"$set": update},
	)
	return err
}

// Delete soft-deletes a comment
func (r *CommentRepository) Delete(ctx context.Context, id primitive.ObjectID) error {
	_, err := r.collection.UpdateOne(
		ctx,
		bson.M{"_id": id},
		bson.M{"$set": bson.M{
			"isDeleted": true,
			"updatedAt": time.Now(),
		}},
	)
	return err
}

// CountByDocumentID counts comments for a document
func (r *CommentRepository) CountByDocumentID(ctx context.Context, documentID primitive.ObjectID, resolved *bool) (int64, error) {
	filter := bson.M{
		"documentId": documentID,
		"isDeleted":  false,
	}

	if resolved != nil {
		filter["resolved"] = *resolved
	}

	return r.collection.CountDocuments(ctx, filter)
}
```

### 5.2 Comment Service

Create: `internal/comments/service/comment_service.go`

```go
package service

import (
	"context"
	"fmt"

	"github.com/yourusername/gogolatex/internal/comments/repository"
	"github.com/yourusername/gogolatex/internal/models"
	"go.mongodb.org/mongo-driver/bson/primitive"
)

// CommentService handles comment business logic
type CommentService struct {
	repo *repository.CommentRepository
}

// NewCommentService creates a new comment service
func NewCommentService(repo *repository.CommentRepository) *CommentService {
	return &CommentService{
		repo: repo,
	}
}

// CreateComment creates a new comment
func (s *CommentService) CreateComment(ctx context.Context, req *models.CreateCommentRequest, user *models.User, projectID primitive.ObjectID) (*models.Comment, error) {
	comment := &models.Comment{
		DocumentID: req.DocumentID,
		ProjectID:  projectID,
		UserID:     user.ID,
		UserName:   user.Name,
		UserEmail:  user.Email,
		Content:    req.Content,
		Position:   req.Position,
		ParentID:   req.ParentID,
		Resolved:   false,
	}

	// If this is a reply, check that parent exists
	if !req.ParentID.IsZero() {
		parent, err := s.repo.FindByID(ctx, req.ParentID)
		if err != nil {
			return nil, fmt.Errorf("parent comment not found")
		}

		// Make sure parent is in the same document
		if parent.DocumentID != req.DocumentID {
			return nil, fmt.Errorf("parent comment is in a different document")
		}

		// Replies inherit the parent's position
		comment.Position = parent.Position
	}

	if err := s.repo.Create(ctx, comment); err != nil {
		return nil, err
	}

	return comment, nil
}

// GetComment gets a comment by ID
func (s *CommentService) GetComment(ctx context.Context, id primitive.ObjectID) (*models.Comment, error) {
	return s.repo.FindByID(ctx, id)
}

// GetDocumentComments gets all comments for a document
func (s *CommentService) GetDocumentComments(ctx context.Context, documentID primitive.ObjectID, includeResolved bool) ([]models.Comment, error) {
	return s.repo.FindByDocumentID(ctx, documentID, includeResolved)
}

// GetDocumentThreads gets all comment threads for a document
func (s *CommentService) GetDocumentThreads(ctx context.Context, documentID primitive.ObjectID, includeResolved bool) ([]models.CommentThread, error) {
	return s.repo.FindThreadsByDocumentID(ctx, documentID, includeResolved)
}

// UpdateComment updates a comment
func (s *CommentService) UpdateComment(ctx context.Context, id primitive.ObjectID, content string, userID string) error {
	// Get the comment to check ownership
	comment, err := s.repo.FindByID(ctx, id)
	if err != nil {
		return err
	}

	// Only the author can edit
	if comment.UserID != userID {
		return fmt.Errorf("only the author can edit this comment")
	}

	return s.repo.Update(ctx, id, content)
}

// ResolveComment marks a comment thread as resolved
func (s *CommentService) ResolveComment(ctx context.Context, id primitive.ObjectID, userID string, resolved bool) error {
	// Get the comment
	comment, err := s.repo.FindByID(ctx, id)
	if err != nil {
		return err
	}

	// Only resolve top-level comments (not replies)
	if !comment.ParentID.IsZero() {
		return fmt.Errorf("only top-level comments can be resolved")
	}

	// TODO: Check user has permission to resolve comments

	return s.repo.Resolve(ctx, id, userID, resolved)
}

// DeleteComment soft-deletes a comment
func (s *CommentService) DeleteComment(ctx context.Context, id primitive.ObjectID, userID string) error {
	// Get the comment to check ownership
	comment, err := s.repo.FindByID(ctx, id)
	if err != nil {
		return err
	}

	// Only the author can delete
	if comment.UserID != userID {
		return fmt.Errorf("only the author can delete this comment")
	}

	return s.repo.Delete(ctx, id)
}

// GetCommentCount gets the count of comments for a document
func (s *CommentService) GetCommentCount(ctx context.Context, documentID primitive.ObjectID, resolved *bool) (int64, error) {
	return s.repo.CountByDocumentID(ctx, documentID, resolved)
}
```

### 5.3 HTTP Handlers

Create: `internal/comments/handler/comment_handler.go`

```go
package handler

import (
	"encoding/json"
	"net/http"

	"github.com/gorilla/mux"
	"github.com/yourusername/gogolatex/internal/comments/service"
	"github.com/yourusername/gogolatex/internal/models"
	"go.mongodb.org/mongo-driver/bson/primitive"
)

// CommentHandler handles comment HTTP requests
type CommentHandler struct {
	service *service.CommentService
}

// NewCommentHandler creates a new comment handler
func NewCommentHandler(service *service.CommentService) *CommentHandler {
	return &CommentHandler{
		service: service,
	}
}

// CreateComment creates a new comment
func (h *CommentHandler) CreateComment(w http.ResponseWriter, r *http.Request) {
	var req models.CreateCommentRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	// Get user from context (set by auth middleware)
	user := r.Context().Value("user").(*models.User)

	// Get projectID from context or query params
	projectIDStr := r.URL.Query().Get("projectId")
	projectID, _ := primitive.ObjectIDFromHex(projectIDStr)

	comment, err := h.service.CreateComment(r.Context(), &req, user, projectID)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(comment)
}

// GetComment gets a comment by ID
func (h *CommentHandler) GetComment(w http.ResponseWriter, r *http.Request) {
	vars := mux.Vars(r)
	id, err := primitive.ObjectIDFromHex(vars["id"])
	if err != nil {
		http.Error(w, "Invalid comment ID", http.StatusBadRequest)
		return
	}

	comment, err := h.service.GetComment(r.Context(), id)
	if err != nil {
		http.Error(w, err.Error(), http.StatusNotFound)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(comment)
}

// GetDocumentComments gets all comments for a document
func (h *CommentHandler) GetDocumentComments(w http.ResponseWriter, r *http.Request) {
	vars := mux.Vars(r)
	documentID, err := primitive.ObjectIDFromHex(vars["documentId"])
	if err != nil {
		http.Error(w, "Invalid document ID", http.StatusBadRequest)
		return
	}

	includeResolved := r.URL.Query().Get("includeResolved") == "true"

	comments, err := h.service.GetDocumentComments(r.Context(), documentID, includeResolved)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"comments": comments,
	})
}

// GetDocumentThreads gets all comment threads for a document
func (h *CommentHandler) GetDocumentThreads(w http.ResponseWriter, r *http.Request) {
	vars := mux.Vars(r)
	documentID, err := primitive.ObjectIDFromHex(vars["documentId"])
	if err != nil {
		http.Error(w, "Invalid document ID", http.StatusBadRequest)
		return
	}

	includeResolved := r.URL.Query().Get("includeResolved") == "true"

	threads, err := h.service.GetDocumentThreads(r.Context(), documentID, includeResolved)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"threads": threads,
	})
}

// UpdateComment updates a comment
func (h *CommentHandler) UpdateComment(w http.ResponseWriter, r *http.Request) {
	vars := mux.Vars(r)
	id, err := primitive.ObjectIDFromHex(vars["id"])
	if err != nil {
		http.Error(w, "Invalid comment ID", http.StatusBadRequest)
		return
	}

	var req models.UpdateCommentRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	user := r.Context().Value("user").(*models.User)

	if err := h.service.UpdateComment(r.Context(), id, req.Content, user.ID); err != nil {
		http.Error(w, err.Error(), http.StatusForbidden)
		return
	}

	w.WriteHeader(http.StatusNoContent)
}

// ResolveComment marks a comment as resolved
func (h *CommentHandler) ResolveComment(w http.ResponseWriter, r *http.Request) {
	vars := mux.Vars(r)
	id, err := primitive.ObjectIDFromHex(vars["id"])
	if err != nil {
		http.Error(w, "Invalid comment ID", http.StatusBadRequest)
		return
	}

	var req models.ResolveCommentRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	user := r.Context().Value("user").(*models.User)

	if err := h.service.ResolveComment(r.Context(), id, user.ID, req.Resolved); err != nil {
		http.Error(w, err.Error(), http.StatusForbidden)
		return
	}

	w.WriteHeader(http.StatusNoContent)
}

// DeleteComment soft-deletes a comment
func (h *CommentHandler) DeleteComment(w http.ResponseWriter, r *http.Request) {
	vars := mux.Vars(r)
	id, err := primitive.ObjectIDFromHex(vars["id"])
	if err != nil {
		http.Error(w, "Invalid comment ID", http.StatusBadRequest)
		return
	}

	user := r.Context().Value("user").(*models.User)

	if err := h.service.DeleteComment(r.Context(), id, user.ID); err != nil {
		http.Error(w, err.Error(), http.StatusForbidden)
		return
	}

	w.WriteHeader(http.StatusNoContent)
}
```

**Verification**:
```bash
go build ./internal/comments/...
```

---

## Task 6: Frontend Change Tracking UI (2 hours)

### 6.1 Change Tracking Types

Create: `frontend/src/types/tracking.ts`

```typescript
export interface DocumentChange {
  id: string
  documentId: string
  projectId: string
  userId: string
  userName: string
  userEmail: string
  changeType: 'insert' | 'delete' | 'replace'
  position: number
  length: number
  oldText?: string
  newText?: string
  acceptedBy?: string
  rejectedBy?: string
  status: 'pending' | 'accepted' | 'rejected'
  timestamp: string
  sessionId?: string
}

export interface ChangeStatistics {
  totalChanges: number
  pendingChanges: number
  acceptedChanges: number
  rejectedChanges: number
  byUser: Record<string, number>
}

export interface Comment {
  id: string
  documentId: string
  projectId: string
  userId: string
  userName: string
  userEmail: string
  content: string
  position: CommentPosition
  parentId?: string
  resolved: boolean
  resolvedBy?: string
  resolvedAt?: string
  createdAt: string
  updatedAt: string
  isDeleted: boolean
}

export interface CommentPosition {
  line: number
  character: number
  text?: string
}

export interface CommentThread {
  comment: Comment
  replies: Comment[]
}
```

### 6.2 Tracking Service

Create: `frontend/src/services/tracking.ts`

```typescript
import axios from 'axios'
import { DocumentChange, ChangeStatistics, Comment, CommentThread } from '../types/tracking'

const API_URL = import.meta.env.VITE_API_URL || 'http://localhost:8080'

export const trackingService = {
  // Change tracking
  async getDocumentChanges(documentId: string, status?: string): Promise<DocumentChange[]> {
    const params = status ? { status } : {}
    const response = await axios.get(`${API_URL}/api/documents/${documentId}/changes`, { params })
    return response.data.changes
  },

  async createChange(documentId: string, change: {
    changeType: 'insert' | 'delete' | 'replace'
    position: number
    length: number
    oldText?: string
    newText?: string
  }): Promise<DocumentChange> {
    const response = await axios.post(`${API_URL}/api/changes`, {
      documentId,
      ...change,
    })
    return response.data
  },

  async acceptChange(changeId: string): Promise<void> {
    await axios.post(`${API_URL}/api/changes/${changeId}/accept`)
  },

  async rejectChange(changeId: string): Promise<void> {
    await axios.post(`${API_URL}/api/changes/${changeId}/reject`)
  },

  async getChangeStatistics(projectId: string): Promise<ChangeStatistics> {
    const response = await axios.get(`${API_URL}/api/projects/${projectId}/changes/statistics`)
    return response.data
  },

  // Comments
  async getDocumentThreads(documentId: string, includeResolved: boolean = false): Promise<CommentThread[]> {
    const response = await axios.get(`${API_URL}/api/documents/${documentId}/threads`, {
      params: { includeResolved },
    })
    return response.data.threads
  },

  async getDocumentComments(documentId: string, includeResolved: boolean = false): Promise<Comment[]> {
    const response = await axios.get(`${API_URL}/api/documents/${documentId}/comments`, {
      params: { includeResolved },
    })
    return response.data.comments
  },

  async createComment(documentId: string, comment: {
    content: string
    position: CommentPosition
    parentId?: string
  }): Promise<Comment> {
    const response = await axios.post(`${API_URL}/api/comments`, {
      documentId,
      ...comment,
    })
    return response.data
  },

  async updateComment(commentId: string, content: string): Promise<void> {
    await axios.put(`${API_URL}/api/comments/${commentId}`, { content })
  },

  async resolveComment(commentId: string, resolved: boolean): Promise<void> {
    await axios.post(`${API_URL}/api/comments/${commentId}/resolve`, { resolved })
  },

  async deleteComment(commentId: string): Promise<void> {
    await axios.delete(`${API_URL}/api/comments/${commentId}`)
  },
}
```

### 6.3 Change Tracking Panel Component

Create: `frontend/src/components/ChangeTrackingPanel.tsx`

```typescript
import React, { useState, useEffect } from 'react'
import { DocumentChange } from '../types/tracking'
import { trackingService } from '../services/tracking'

interface ChangeTrackingPanelProps {
  documentId: string
  onSelectChange?: (change: DocumentChange) => void
}

export const ChangeTrackingPanel: React.FC<ChangeTrackingPanelProps> = ({
  documentId,
  onSelectChange,
}) => {
  const [changes, setChanges] = useState<DocumentChange[]>([])
  const [filter, setFilter] = useState<'all' | 'pending' | 'accepted' | 'rejected'>('pending')
  const [loading, setLoading] = useState(false)

  useEffect(() => {
    loadChanges()
  }, [documentId, filter])

  const loadChanges = async () => {
    setLoading(true)
    try {
      const status = filter === 'all' ? undefined : filter
      const data = await trackingService.getDocumentChanges(documentId, status)
      setChanges(data)
    } catch (error) {
      console.error('Failed to load changes:', error)
    } finally {
      setLoading(false)
    }
  }

  const handleAccept = async (changeId: string) => {
    try {
      await trackingService.acceptChange(changeId)
      await loadChanges()
    } catch (error) {
      console.error('Failed to accept change:', error)
    }
  }

  const handleReject = async (changeId: string) => {
    try {
      await trackingService.rejectChange(changeId)
      await loadChanges()
    } catch (error) {
      console.error('Failed to reject change:', error)
    }
  }

  const getChangeIcon = (changeType: string) => {
    switch (changeType) {
      case 'insert':
        return '+'
      case 'delete':
        return '-'
      case 'replace':
        return '±'
      default:
        return '?'
    }
  }

  const getStatusBadge = (status: string) => {
    const colors = {
      pending: 'bg-yellow-100 text-yellow-800',
      accepted: 'bg-green-100 text-green-800',
      rejected: 'bg-red-100 text-red-800',
    }
    return (
      <span className={`px-2 py-1 text-xs rounded-full ${colors[status as keyof typeof colors]}`}>
        {status}
      </span>
    )
  }

  return (
    <div className="h-full flex flex-col bg-white">
      {/* Header */}
      <div className="p-4 border-b">
        <h2 className="text-lg font-semibold mb-3">Change Tracking</h2>
        
        {/* Filter buttons */}
        <div className="flex gap-2">
          {['all', 'pending', 'accepted', 'rejected'].map((f) => (
            <button
              key={f}
              onClick={() => setFilter(f as any)}
              className={`px-3 py-1 text-sm rounded ${
                filter === f
                  ? 'bg-blue-600 text-white'
                  : 'bg-gray-100 text-gray-700 hover:bg-gray-200'
              }`}
            >
              {f.charAt(0).toUpperCase() + f.slice(1)}
            </button>
          ))}
        </div>
      </div>

      {/* Changes list */}
      <div className="flex-1 overflow-y-auto">
        {loading ? (
          <div className="p-4 text-center text-gray-500">Loading changes...</div>
        ) : changes.length === 0 ? (
          <div className="p-4 text-center text-gray-500">
            No {filter !== 'all' ? filter : ''} changes found
          </div>
        ) : (
          <div className="divide-y">
            {changes.map((change) => (
              <div
                key={change.id}
                className="p-4 hover:bg-gray-50 cursor-pointer"
                onClick={() => onSelectChange?.(change)}
              >
                <div className="flex items-start justify-between mb-2">
                  <div className="flex items-center gap-2">
                    <span className="text-2xl font-mono">{getChangeIcon(change.changeType)}</span>
                    <div>
                      <div className="font-medium">{change.userName}</div>
                      <div className="text-xs text-gray-500">
                        {new Date(change.timestamp).toLocaleString()}
                      </div>
                    </div>
                  </div>
                  {getStatusBadge(change.status)}
                </div>

                {/* Change preview */}
                <div className="ml-8 text-sm">
                  {change.oldText && (
                    <div className="bg-red-50 text-red-700 p-2 rounded mb-1">
                      <span className="font-mono">- {change.oldText}</span>
                    </div>
                  )}
                  {change.newText && (
                    <div className="bg-green-50 text-green-700 p-2 rounded">
                      <span className="font-mono">+ {change.newText}</span>
                    </div>
                  )}
                </div>

                {/* Action buttons for pending changes */}
                {change.status === 'pending' && (
                  <div className="mt-3 ml-8 flex gap-2">
                    <button
                      onClick={(e) => {
                        e.stopPropagation()
                        handleAccept(change.id)
                      }}
                      className="px-3 py-1 text-sm bg-green-600 text-white rounded hover:bg-green-700"
                    >
                      Accept
                    </button>
                    <button
                      onClick={(e) => {
                        e.stopPropagation()
                        handleReject(change.id)
                      }}
                      className="px-3 py-1 text-sm bg-red-600 text-white rounded hover:bg-red-700"
                    >
                      Reject
                    </button>
                  </div>
                )}
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  )
}
```

**Verification**: Test in browser with actual changes

---

## Task 7: Frontend Comments UI (2 hours)

### 7.1 Comments Panel Component

Create: `frontend/src/components/CommentsPanel.tsx`

```typescript
import React, { useState, useEffect } from 'react'
import { CommentThread } from '../types/tracking'
import { trackingService } from '../services/tracking'
import { useAuthStore } from '../stores/authStore'

interface CommentsPanelProps {
  documentId: string
  onSelectComment?: (thread: CommentThread) => void
}

export const CommentsPanel: React.FC<CommentsPanelProps> = ({
  documentId,
  onSelectComment,
}) => {
  const [threads, setThreads] = useState<CommentThread[]>([])
  const [includeResolved, setIncludeResolved] = useState(false)
  const [loading, setLoading] = useState(false)
  const [replyingTo, setReplyingTo] = useState<string | null>(null)
  const [replyText, setReplyText] = useState('')
  const user = useAuthStore((state) => state.user)

  useEffect(() => {
    loadThreads()
  }, [documentId, includeResolved])

  const loadThreads = async () => {
    setLoading(true)
    try {
      const data = await trackingService.getDocumentThreads(documentId, includeResolved)
      setThreads(data)
    } catch (error) {
      console.error('Failed to load threads:', error)
    } finally {
      setLoading(false)
    }
  }

  const handleResolve = async (commentId: string, resolved: boolean) => {
    try {
      await trackingService.resolveComment(commentId, resolved)
      await loadThreads()
    } catch (error) {
      console.error('Failed to resolve comment:', error)
    }
  }

  const handleReply = async (parentId: string) => {
    if (!replyText.trim()) return

    try {
      // Get parent comment to find position
      const thread = threads.find(
        (t) => t.comment.id === parentId || t.replies.some((r) => r.id === parentId)
      )
      if (!thread) return

      await trackingService.createComment(documentId, {
        content: replyText,
        position: thread.comment.position,
        parentId,
      })

      setReplyText('')
      setReplyingTo(null)
      await loadThreads()
    } catch (error) {
      console.error('Failed to reply:', error)
    }
  }

  const handleDelete = async (commentId: string) => {
    if (!confirm('Are you sure you want to delete this comment?')) return

    try {
      await trackingService.deleteComment(commentId)
      await loadThreads()
    } catch (error) {
      console.error('Failed to delete comment:', error)
    }
  }

  return (
    <div className="h-full flex flex-col bg-white">
      {/* Header */}
      <div className="p-4 border-b">
        <h2 className="text-lg font-semibold mb-3">Comments</h2>
        
        {/* Toggle resolved */}
        <label className="flex items-center gap-2 text-sm">
          <input
            type="checkbox"
            checked={includeResolved}
            onChange={(e) => setIncludeResolved(e.target.checked)}
            className="rounded"
          />
          Show resolved comments
        </label>
      </div>

      {/* Threads list */}
      <div className="flex-1 overflow-y-auto">
        {loading ? (
          <div className="p-4 text-center text-gray-500">Loading comments...</div>
        ) : threads.length === 0 ? (
          <div className="p-4 text-center text-gray-500">No comments yet</div>
        ) : (
          <div className="divide-y">
            {threads.map((thread) => (
              <div
                key={thread.comment.id}
                className={`p-4 ${thread.comment.resolved ? 'bg-gray-50' : 'bg-white'}`}
              >
                {/* Main comment */}
                <div
                  className="cursor-pointer hover:bg-gray-100 -m-2 p-2 rounded"
                  onClick={() => onSelectComment?.(thread)}
                >
                  <div className="flex items-start justify-between mb-2">
                    <div>
                      <div className="font-medium">{thread.comment.userName}</div>
                      <div className="text-xs text-gray-500">
                        Line {thread.comment.position.line}
                        {' • '}
                        {new Date(thread.comment.createdAt).toLocaleString()}
                      </div>
                    </div>
                    {thread.comment.resolved && (
                      <span className="px-2 py-1 text-xs bg-green-100 text-green-800 rounded-full">
                        Resolved
                      </span>
                    )}
                  </div>

                  <div className="text-sm mb-2">{thread.comment.content}</div>

                  {thread.comment.position.text && (
                    <div className="text-xs bg-gray-100 p-2 rounded font-mono mb-2">
                      "{thread.comment.position.text}"
                    </div>
                  )}
                </div>

                {/* Replies */}
                {thread.replies.length > 0 && (
                  <div className="ml-6 mt-3 space-y-3 border-l-2 border-gray-200 pl-4">
                    {thread.replies.map((reply) => (
                      <div key={reply.id} className="text-sm">
                        <div className="flex items-start justify-between mb-1">
                          <div>
                            <span className="font-medium">{reply.userName}</span>
                            <span className="text-xs text-gray-500 ml-2">
                              {new Date(reply.createdAt).toLocaleString()}
                            </span>
                          </div>
                          {reply.userId === user?.id && (
                            <button
                              onClick={() => handleDelete(reply.id)}
                              className="text-xs text-red-600 hover:text-red-800"
                            >
                              Delete
                            </button>
                          )}
                        </div>
                        <div className="text-gray-700">{reply.content}</div>
                      </div>
                    ))}
                  </div>
                )}

                {/* Reply form */}
                {replyingTo === thread.comment.id ? (
                  <div className="mt-3 ml-6">
                    <textarea
                      value={replyText}
                      onChange={(e) => setReplyText(e.target.value)}
                      placeholder="Write a reply..."
                      className="w-full px-3 py-2 text-sm border rounded focus:outline-none focus:ring-2 focus:ring-blue-500"
                      rows={3}
                      autoFocus
                    />
                    <div className="flex gap-2 mt-2">
                      <button
                        onClick={() => handleReply(thread.comment.id)}
                        className="px-3 py-1 text-sm bg-blue-600 text-white rounded hover:bg-blue-700"
                      >
                        Reply
                      </button>
                      <button
                        onClick={() => {
                          setReplyingTo(null)
                          setReplyText('')
                        }}
                        className="px-3 py-1 text-sm bg-gray-200 text-gray-700 rounded hover:bg-gray-300"
                      >
                        Cancel
                      </button>
                    </div>
                  </div>
                ) : (
                  <div className="mt-3 flex gap-2">
                    <button
                      onClick={() => setReplyingTo(thread.comment.id)}
                      className="text-sm text-blue-600 hover:text-blue-800"
                    >
                      Reply
                    </button>
                    {!thread.comment.resolved && (
                      <button
                        onClick={() => handleResolve(thread.comment.id, true)}
                        className="text-sm text-green-600 hover:text-green-800"
                      >
                        Resolve
                      </button>
                    )}
                    {thread.comment.resolved && (
                      <button
                        onClick={() => handleResolve(thread.comment.id, false)}
                        className="text-sm text-gray-600 hover:text-gray-800"
                      >
                        Reopen
                      </button>
                    )}
                    {thread.comment.userId === user?.id && (
                      <button
                        onClick={() => handleDelete(thread.comment.id)}
                        className="text-sm text-red-600 hover:text-red-800"
                      >
                        Delete
                      </button>
                    )}
                  </div>
                )}
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  )
}
```

### 7.2 Inline Comment Widget

Create: `frontend/src/components/InlineCommentWidget.tsx`

```typescript
import React, { useState } from 'react'
import { CommentPosition } from '../types/tracking'
import { trackingService } from '../services/tracking'

interface InlineCommentWidgetProps {
  documentId: string
  position: CommentPosition
  selectedText?: string
  onClose: () => void
  onCreated?: () => void
}

export const InlineCommentWidget: React.FC<InlineCommentWidgetProps> = ({
  documentId,
  position,
  selectedText,
  onClose,
  onCreated,
}) => {
  const [content, setContent] = useState('')
  const [loading, setLoading] = useState(false)

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!content.trim()) return

    setLoading(true)
    try {
      await trackingService.createComment(documentId, {
        content,
        position: {
          ...position,
          text: selectedText,
        },
      })
      
      onCreated?.()
      onClose()
    } catch (error) {
      console.error('Failed to create comment:', error)
      alert('Failed to create comment')
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="absolute z-50 bg-white border rounded-lg shadow-lg p-4 w-80">
      <div className="flex justify-between items-start mb-3">
        <h3 className="font-semibold">Add Comment</h3>
        <button
          onClick={onClose}
          className="text-gray-400 hover:text-gray-600"
        >
          ×
        </button>
      </div>

      {selectedText && (
        <div className="mb-3 p-2 bg-gray-100 rounded text-sm">
          <div className="text-xs text-gray-500 mb-1">Selected text:</div>
          <div className="font-mono">{selectedText}</div>
        </div>
      )}

      <form onSubmit={handleSubmit}>
        <textarea
          value={content}
          onChange={(e) => setContent(e.target.value)}
          placeholder="Write your comment..."
          className="w-full px-3 py-2 border rounded focus:outline-none focus:ring-2 focus:ring-blue-500 mb-3"
          rows={4}
          autoFocus
          disabled={loading}
        />

        <div className="flex justify-end gap-2">
          <button
            type="button"
            onClick={onClose}
            className="px-4 py-2 text-sm bg-gray-200 text-gray-700 rounded hover:bg-gray-300"
            disabled={loading}
          >
            Cancel
          </button>
          <button
            type="submit"
            className="px-4 py-2 text-sm bg-blue-600 text-white rounded hover:bg-blue-700 disabled:opacity-50"
            disabled={loading || !content.trim()}
          >
            {loading ? 'Creating...' : 'Add Comment'}
          </button>
        </div>
      </form>
    </div>
  )
}
```

**Verification**: Test comments in browser with editor integration

---

## Task 8: Git Service Integration (1.5 hours)

### 8.1 Git Service Main Server

Update: `backend/node-services/git-service/src/server.ts`

```typescript
import express from 'express'
import cors from 'cors'
import dotenv from 'dotenv'
import { GitController } from './controllers/git-controller'

dotenv.config()

const app = express()
const port = process.env.PORT || 3004

// Middleware
app.use(cors())
app.use(express.json())

// Initialize controller
const gitController = new GitController()

// Routes
app.post('/api/projects/:projectId/git/init', gitController.initRepository.bind(gitController))
app.post('/api/projects/:projectId/git/commit', gitController.commit.bind(gitController))
app.get('/api/projects/:projectId/git/history', gitController.getHistory.bind(gitController))
app.get('/api/projects/:projectId/git/commits/:commitHash', gitController.getCommit.bind(gitController))
app.get('/api/projects/:projectId/git/diff', gitController.getDiff.bind(gitController))
app.get('/api/projects/:projectId/git/status', gitController.getStatus.bind(gitController))
app.post('/api/projects/:projectId/git/branches', gitController.createBranch.bind(gitController))
app.get('/api/projects/:projectId/git/branches', gitController.listBranches.bind(gitController))
app.post('/api/projects/:projectId/git/branches/checkout', gitController.checkoutBranch.bind(gitController))
app.post('/api/projects/:projectId/git/merge', gitController.mergeBranch.bind(gitController))
app.post('/api/projects/:projectId/git/commits/:commitHash/revert', gitController.revertCommit.bind(gitController))
app.get('/api/projects/:projectId/git/commits/:commitHash/file', gitController.getFileAtCommit.bind(gitController))

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'ok', service: 'git-service' })
})

app.listen(port, () => {
  console.log(`Git service listening on port ${port}`)
})
```

### 8.2 Docker Configuration for Git Service

Update: `docker/node-services/Dockerfile`

Add git installation:

```dockerfile
FROM node:20-alpine

# Install git
RUN apk add --no-cache git

WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm ci --only=production

# Copy source
COPY . .

# Build TypeScript
RUN npm run build

EXPOSE 3000

CMD ["npm", "start"]
```

### 8.3 Add Git Service to Docker Compose

Update: `docker-compose.yml`

```yaml
  git-service:
    build:
      context: ./backend/node-services/git-service
      dockerfile: ../../docker/node-services/Dockerfile
    ports:
      - "3004:3004"
    environment:
      PORT: 3004
      GIT_REPO_PATH: /var/lib/gogolatex/git-repos
      GIT_AUTHOR_NAME: GogoLaTeX
      GIT_AUTHOR_EMAIL: noreply@gogolatex.local
    volumes:
      - git-repos:/var/lib/gogolatex/git-repos
    depends_on:
      - redis
    networks:
      - gogolatex-network

volumes:
  git-repos:
    driver: local
```

**Verification**:
```bash
cd latex-collaborative-editor
docker-compose up -d git-service
docker-compose logs -f git-service
```

---

## Task 9: History & Diff Viewer (2 hours)

### 9.1 History Viewer Component

Create: `frontend/src/components/HistoryViewer.tsx`

```typescript
import React, { useState, useEffect } from 'react'
import axios from 'axios'

interface Commit {
  hash: string
  message: string
  author: {
    name: string
    email: string
  }
  date: string
  files: string[]
}

interface HistoryViewerProps {
  projectId: string
  onSelectCommit?: (commit: Commit) => void
}

const GIT_SERVICE_URL = import.meta.env.VITE_GIT_SERVICE_URL || 'http://localhost:3004'

export const HistoryViewer: React.FC<HistoryViewerProps> = ({
  projectId,
  onSelectCommit,
}) => {
  const [commits, setCommits] = useState<Commit[]>([])
  const [loading, setLoading] = useState(false)
  const [selectedCommit, setSelectedCommit] = useState<string | null>(null)

  useEffect(() => {
    loadHistory()
  }, [projectId])

  const loadHistory = async () => {
    setLoading(true)
    try {
      const response = await axios.get(
        `${GIT_SERVICE_URL}/api/projects/${projectId}/git/history`,
        {
          params: { limit: 50 },
        }
      )
      setCommits(response.data.commits)
    } catch (error) {
      console.error('Failed to load history:', error)
    } finally {
      setLoading(false)
    }
  }

  const handleSelectCommit = (commit: Commit) => {
    setSelectedCommit(commit.hash)
    onSelectCommit?.(commit)
  }

  return (
    <div className="h-full flex flex-col bg-white">
      {/* Header */}
      <div className="p-4 border-b">
        <h2 className="text-lg font-semibold">Version History</h2>
      </div>

      {/* Commits list */}
      <div className="flex-1 overflow-y-auto">
        {loading ? (
          <div className="p-4 text-center text-gray-500">Loading history...</div>
        ) : commits.length === 0 ? (
          <div className="p-4 text-center text-gray-500">No commits yet</div>
        ) : (
          <div className="divide-y">
            {commits.map((commit) => (
              <div
                key={commit.hash}
                className={`p-4 cursor-pointer hover:bg-gray-50 ${
                  selectedCommit === commit.hash ? 'bg-blue-50' : ''
                }`}
                onClick={() => handleSelectCommit(commit)}
              >
                <div className="flex items-start justify-between mb-2">
                  <div className="flex-1">
                    <div className="font-medium mb-1">{commit.message}</div>
                    <div className="text-sm text-gray-600">
                      {commit.author.name}
                      <span className="mx-2">•</span>
                      {new Date(commit.date).toLocaleString()}
                    </div>
                  </div>
                  <div className="ml-4">
                    <span className="text-xs font-mono bg-gray-100 px-2 py-1 rounded">
                      {commit.hash.substring(0, 7)}
                    </span>
                  </div>
                </div>

                {commit.files.length > 0 && (
                  <div className="text-xs text-gray-500 mt-2">
                    {commit.files.length} file{commit.files.length > 1 ? 's' : ''} changed
                  </div>
                )}
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  )
}
```

### 9.2 Diff Viewer Component

Create: `frontend/src/components/DiffViewer.tsx`

```typescript
import React, { useState, useEffect } from 'react'
import axios from 'axios'

interface DiffLine {
  type: 'add' | 'remove' | 'context'
  lineNumber: number
  content: string
}

interface FileDiff {
  file: string
  additions: number
  deletions: number
  changes: DiffLine[]
}

interface DiffViewerProps {
  projectId: string
  fromCommit: string
  toCommit?: string
}

const GIT_SERVICE_URL = import.meta.env.VITE_GIT_SERVICE_URL || 'http://localhost:3004'

export const DiffViewer: React.FC<DiffViewerProps> = ({
  projectId,
  fromCommit,
  toCommit = 'HEAD',
}) => {
  const [diffs, setDiffs] = useState<FileDiff[]>([])
  const [loading, setLoading] = useState(false)
  const [expandedFiles, setExpandedFiles] = useState<Set<string>>(new Set())

  useEffect(() => {
    loadDiff()
  }, [projectId, fromCommit, toCommit])

  const loadDiff = async () => {
    setLoading(true)
    try {
      const response = await axios.get(
        `${GIT_SERVICE_URL}/api/projects/${projectId}/git/diff`,
        {
          params: { from: fromCommit, to: toCommit },
        }
      )
      setDiffs(response.data.diff)
      
      // Auto-expand first file
      if (response.data.diff.length > 0) {
        setExpandedFiles(new Set([response.data.diff[0].file]))
      }
    } catch (error) {
      console.error('Failed to load diff:', error)
    } finally {
      setLoading(false)
    }
  }

  const toggleFile = (file: string) => {
    const newExpanded = new Set(expandedFiles)
    if (newExpanded.has(file)) {
      newExpanded.delete(file)
    } else {
      newExpanded.add(file)
    }
    setExpandedFiles(newExpanded)
  }

  const getLineBackground = (type: string) => {
    switch (type) {
      case 'add':
        return 'bg-green-50'
      case 'remove':
        return 'bg-red-50'
      default:
        return 'bg-white'
    }
  }

  const getLineColor = (type: string) => {
    switch (type) {
      case 'add':
        return 'text-green-800'
      case 'remove':
        return 'text-red-800'
      default:
        return 'text-gray-700'
    }
  }

  const getLinePrefix = (type: string) => {
    switch (type) {
      case 'add':
        return '+'
      case 'remove':
        return '-'
      default:
        return ' '
    }
  }

  return (
    <div className="h-full flex flex-col bg-white">
      {/* Header */}
      <div className="p-4 border-b">
        <h2 className="text-lg font-semibold">Changes</h2>
        <div className="text-sm text-gray-600 mt-1">
          Comparing{' '}
          <span className="font-mono bg-gray-100 px-2 py-0.5 rounded">
            {fromCommit.substring(0, 7)}
          </span>
          {' → '}
          <span className="font-mono bg-gray-100 px-2 py-0.5 rounded">
            {toCommit === 'HEAD' ? 'HEAD' : toCommit.substring(0, 7)}
          </span>
        </div>
      </div>

      {/* Diffs */}
      <div className="flex-1 overflow-y-auto">
        {loading ? (
          <div className="p-4 text-center text-gray-500">Loading diff...</div>
        ) : diffs.length === 0 ? (
          <div className="p-4 text-center text-gray-500">No changes</div>
        ) : (
          <div className="space-y-4 p-4">
            {diffs.map((diff) => (
              <div key={diff.file} className="border rounded-lg overflow-hidden">
                {/* File header */}
                <div
                  className="bg-gray-100 px-4 py-2 flex items-center justify-between cursor-pointer hover:bg-gray-200"
                  onClick={() => toggleFile(diff.file)}
                >
                  <div className="flex items-center gap-2">
                    <span>{expandedFiles.has(diff.file) ? '▼' : '▶'}</span>
                    <span className="font-mono font-semibold">{diff.file}</span>
                  </div>
                  <div className="flex gap-4 text-sm">
                    <span className="text-green-600">+{diff.additions}</span>
                    <span className="text-red-600">-{diff.deletions}</span>
                  </div>
                </div>

                {/* Diff content */}
                {expandedFiles.has(diff.file) && (
                  <div className="bg-white">
                    {diff.changes.map((line, idx) => (
                      <div
                        key={idx}
                        className={`flex font-mono text-sm ${getLineBackground(line.type)}`}
                      >
                        <div className="w-12 text-right px-2 py-1 text-gray-500 bg-gray-50 border-r select-none">
                          {line.lineNumber}
                        </div>
                        <div className={`flex-1 px-2 py-1 ${getLineColor(line.type)}`}>
                          <span className="select-none mr-2">{getLinePrefix(line.type)}</span>
                          <span>{line.content}</span>
                        </div>
                      </div>
                    ))}
                  </div>
                )}
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  )
}
```

**Verification**: Test history and diff viewer with git commits

---

## Task 10: Mobile UI Optimizations (2 hours)

### 10.1 Mobile-Optimized Layout

Create: `frontend/src/components/MobileLayout.tsx`

```typescript
import React, { useState } from 'react'
import { Editor } from './Editor'
import { CommentsPanel } from './CommentsPanel'
import { ChangeTrackingPanel } from './ChangeTrackingPanel'
import { HistoryViewer } from './HistoryViewer'

interface MobileLayoutProps {
  projectId: string
  documentId: string
}

type PanelType = 'editor' | 'comments' | 'changes' | 'history'

export const MobileLayout: React.FC<MobileLayoutProps> = ({
  projectId,
  documentId,
}) => {
  const [activePanel, setActivePanel] = useState<PanelType>('editor')

  const panels = {
    editor: <Editor documentId={documentId} />,
    comments: <CommentsPanel documentId={documentId} />,
    changes: <ChangeTrackingPanel documentId={documentId} />,
    history: <HistoryViewer projectId={projectId} />,
  }

  return (
    <div className="h-screen flex flex-col">
      {/* Mobile header */}
      <div className="bg-white border-b px-4 py-3 flex items-center justify-between">
        <h1 className="text-lg font-semibold truncate">Document</h1>
        <button className="p-2 hover:bg-gray-100 rounded">
          <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 5v.01M12 12v.01M12 19v.01M12 6a1 1 0 110-2 1 1 0 010 2zm0 7a1 1 0 110-2 1 1 0 010 2zm0 7a1 1 0 110-2 1 1 0 010 2z" />
          </svg>
        </button>
      </div>

      {/* Content area */}
      <div className="flex-1 overflow-hidden">
        {panels[activePanel]}
      </div>

      {/* Bottom navigation */}
      <div className="bg-white border-t flex">
        <button
          onClick={() => setActivePanel('editor')}
          className={`flex-1 py-3 text-sm font-medium ${
            activePanel === 'editor'
              ? 'text-blue-600 border-t-2 border-blue-600'
              : 'text-gray-600'
          }`}
        >
          <div className="flex flex-col items-center gap-1">
            <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z" />
            </svg>
            <span>Editor</span>
          </div>
        </button>

        <button
          onClick={() => setActivePanel('comments')}
          className={`flex-1 py-3 text-sm font-medium ${
            activePanel === 'comments'
              ? 'text-blue-600 border-t-2 border-blue-600'
              : 'text-gray-600'
          }`}
        >
          <div className="flex flex-col items-center gap-1">
            <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M7 8h10M7 12h4m1 8l-4-4H5a2 2 0 01-2-2V6a2 2 0 012-2h14a2 2 0 012 2v8a2 2 0 01-2 2h-3l-4 4z" />
            </svg>
            <span>Comments</span>
          </div>
        </button>

        <button
          onClick={() => setActivePanel('changes')}
          className={`flex-1 py-3 text-sm font-medium ${
            activePanel === 'changes'
              ? 'text-blue-600 border-t-2 border-blue-600'
              : 'text-gray-600'
          }`}
        >
          <div className="flex flex-col items-center gap-1">
            <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
            </svg>
            <span>Changes</span>
          </div>
        </button>

        <button
          onClick={() => setActivePanel('history')}
          className={`flex-1 py-3 text-sm font-medium ${
            activePanel === 'history'
              ? 'text-blue-600 border-t-2 border-blue-600'
              : 'text-gray-600'
          }`}
        >
          <div className="flex flex-col items-center gap-1">
            <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
            </svg>
            <span>History</span>
          </div>
        </button>
      </div>
    </div>
  )
}
```

### 10.2 Responsive Utilities

Create: `frontend/src/hooks/useMediaQuery.ts`

```typescript
import { useState, useEffect } from 'react'

export function useMediaQuery(query: string): boolean {
  const [matches, setMatches] = useState(false)

  useEffect(() => {
    const media = window.matchMedia(query)
    
    if (media.matches !== matches) {
      setMatches(media.matches)
    }

    const listener = () => setMatches(media.matches)
    media.addEventListener('change', listener)

    return () => media.removeEventListener('change', listener)
  }, [matches, query])

  return matches
}

export function useIsMobile() {
  return useMediaQuery('(max-width: 768px)')
}

export function useIsTablet() {
  return useMediaQuery('(min-width: 769px) and (max-width: 1024px)')
}

export function useIsDesktop() {
  return useMediaQuery('(min-width: 1025px)')
}
```

### 10.3 Adaptive Layout Component

Create: `frontend/src/components/AdaptiveLayout.tsx`

```typescript
import React from 'react'
import { useIsMobile } from '../hooks/useMediaQuery'
import { MobileLayout } from './MobileLayout'
import { MainLayout } from './MainLayout'

interface AdaptiveLayoutProps {
  projectId: string
  documentId: string
}

export const AdaptiveLayout: React.FC<AdaptiveLayoutProps> = ({
  projectId,
  documentId,
}) => {
  const isMobile = useIsMobile()

  if (isMobile) {
    return <MobileLayout projectId={projectId} documentId={documentId} />
  }

  return <MainLayout projectId={projectId} documentId={documentId} />
}
```

### 10.4 Touch-Optimized Editor Controls

Update: `frontend/src/components/EditorToolbar.tsx`

Add touch-friendly buttons:

```typescript
export const EditorToolbar: React.FC<EditorToolbarProps> = ({ onAction }) => {
  const isMobile = useIsMobile()

  const buttonSize = isMobile ? 'p-3' : 'p-2'
  const iconSize = isMobile ? 'w-6 h-6' : 'w-5 h-5'

  return (
    <div className={`bg-white border-b ${isMobile ? 'px-2 py-2' : 'px-4 py-2'} flex items-center gap-2 overflow-x-auto`}>
      <button
        onClick={() => onAction('bold')}
        className={`${buttonSize} hover:bg-gray-100 rounded`}
        title="Bold"
      >
        <svg className={iconSize} fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 4h8a4 4 0 014 4 4 4 0 01-4 4H6z" />
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 12h9a4 4 0 014 4 4 4 0 01-4 4H6z" />
        </svg>
      </button>

      <button
        onClick={() => onAction('italic')}
        className={`${buttonSize} hover:bg-gray-100 rounded`}
        title="Italic"
      >
        <svg className={iconSize} fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M10 20l4-16m4 4l4 4-4 4M6 16l-4-4 4-4" />
        </svg>
      </button>

      {/* Add more touch-friendly buttons */}
      {isMobile && <div className="flex-1" />}
      
      <button
        onClick={() => onAction('compile')}
        className={`${buttonSize} bg-blue-600 text-white hover:bg-blue-700 rounded font-medium ${isMobile ? 'px-6' : 'px-4'}`}
      >
        Compile
      </button>
    </div>
  )
}
```

**Verification**:
```bash
# Test on mobile device or browser DevTools mobile emulation
npm run dev
```

---

## Testing & Verification

### Complete System Test

1. **Git Service Test**:
```bash
cd latex-collaborative-editor
docker-compose up -d git-service

# Test git operations
curl -X POST http://localhost:3004/api/projects/PROJECT_ID/git/init
curl -X POST http://localhost:3004/api/projects/PROJECT_ID/git/commit \
  -H "Content-Type: application/json" \
  -d '{"message":"Test commit","files":["main.tex"],"author":{"name":"Test User","email":"test@example.com"}}'

curl http://localhost:3004/api/projects/PROJECT_ID/git/history
```

2. **Change Tracking Test**:
```bash
# Create a document change
curl -X POST http://localhost:8080/api/changes \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -d '{
    "documentId":"DOC_ID",
    "changeType":"insert",
    "position":10,
    "length":5,
    "newText":"hello"
  }'

# Get changes
curl http://localhost:8080/api/documents/DOC_ID/changes
```

3. **Comments Test**:
```bash
# Create a comment
curl -X POST http://localhost:8080/api/comments \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -d '{
    "documentId":"DOC_ID",
    "content":"Great work!",
    "position":{"line":10,"character":5,"text":"selected text"}
  }'

# Get comment threads
curl http://localhost:8080/api/documents/DOC_ID/threads
```

4. **Frontend Test**:
```bash
cd frontend
npm run dev

# Open in browser: http://localhost:5173
# Test on mobile: Use Chrome DevTools mobile emulation
```

---

## Troubleshooting

### Common Issues

1. **Git Service Connection Failed**
   - Check if git-service container is running: `docker-compose ps`
   - Check logs: `docker-compose logs git-service`
   - Verify git is installed in container: `docker-compose exec git-service git --version`

2. **Changes Not Showing**
   - Verify MongoDB indexes: Check change_tracking indexes
   - Check WebSocket connection for real-time updates
   - Clear browser cache

3. **Comments Not Loading**
   - Check MongoDB connection
   - Verify comment repository indexes
   - Check browser console for errors

4. **Mobile UI Issues**
   - Test with actual mobile device (not just browser emulation)
   - Check viewport meta tag in index.html
   - Verify touch event handlers

---

## Performance Optimization

### Caching Strategies

1. **Git Operations**: Cache commit history and diffs in Redis
2. **Change Tracking**: Index frequently accessed documents
3. **Comments**: Implement pagination for large comment threads

### Database Indexes

Ensure these indexes exist:
```javascript
// Changes
db.document_changes.createIndex({ documentId: 1, status: 1 })
db.document_changes.createIndex({ projectId: 1, timestamp: -1 })

// Comments
db.comments.createIndex({ documentId: 1, resolved: 1, isDeleted: 1 })
db.comments.createIndex({ parentId: 1 })
```

---

## Phase 7 Complete! ✅

**What We Built**:
- ✅ Git service with full version control (commit, branch, merge, revert)
- ✅ Change tracking system with accept/reject workflow
- ✅ Comments system with threads and replies
- ✅ Frontend panels for changes, comments, and history
- ✅ Diff viewer with syntax highlighting
- ✅ Mobile-optimized UI with bottom navigation
- ✅ Adaptive layouts for desktop/tablet/mobile

**Next Steps**: Phase 8 - Plugins & Polish
- Plugin system architecture
- Template gallery
- Reference manager plugins
- Performance optimization
- Final polish

**Copilot Tips**:
- Use `@workspace` to find existing comment/change components
- Test mobile UI with: `@terminal npm run dev` then open DevTools mobile mode
- Git operations: Check git-service logs with `@terminal docker-compose logs git-service`
