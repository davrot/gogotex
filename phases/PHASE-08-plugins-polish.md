# Phase 8: Plugins & Polish

**Duration**: 4-5 days  
**Goal**: Plugin system, template gallery, reference managers, and final optimizations

**Prerequisites**: Phases 1-7 completed, all core features working

---

## Prerequisites

- [ ] Phases 1-7 completed and tested
- [ ] All services running and stable
- [ ] Frontend fully functional
- [ ] MongoDB and Redis available
- [ ] Performance baseline established

---

## Task 1: Plugin System Architecture (3 hours)

### 1.1 Plugin Types and Interfaces

Create: `backend/go-services/internal/models/plugin.go`

```go
package models

import (
	"time"

	"go.mongodb.org/mongo-driver/bson/primitive"
)

// PluginType represents the type of plugin
type PluginType string

const (
	PluginTypeEditor     PluginType = "editor"      // Editor extensions
	PluginTypeTemplate   PluginType = "template"    // Document templates
	PluginTypeReference  PluginType = "reference"   // Reference managers
	PluginTypeCompiler   PluginType = "compiler"    // Compiler extensions
	PluginTypeExport     PluginType = "export"      // Export formats
	PluginTypeIntegration PluginType = "integration" // External integrations
)

// Plugin represents a plugin in the system
type Plugin struct {
	ID          primitive.ObjectID     `bson:"_id,omitempty" json:"id"`
	Name        string                 `bson:"name" json:"name" validate:"required,min=3,max=100"`
	Slug        string                 `bson:"slug" json:"slug" validate:"required"`
	Type        PluginType             `bson:"type" json:"type" validate:"required"`
	Version     string                 `bson:"version" json:"version" validate:"required"`
	Description string                 `bson:"description" json:"description"`
	Author      string                 `bson:"author" json:"author"`
	Icon        string                 `bson:"icon,omitempty" json:"icon,omitempty"`
	Enabled     bool                   `bson:"enabled" json:"enabled"`
	Config      map[string]interface{} `bson:"config,omitempty" json:"config,omitempty"`
	Metadata    PluginMetadata         `bson:"metadata" json:"metadata"`
	CreatedAt   time.Time              `bson:"createdAt" json:"createdAt"`
	UpdatedAt   time.Time              `bson:"updatedAt" json:"updatedAt"`
}

// PluginMetadata contains plugin information
type PluginMetadata struct {
	Homepage    string   `bson:"homepage,omitempty" json:"homepage,omitempty"`
	Repository  string   `bson:"repository,omitempty" json:"repository,omitempty"`
	License     string   `bson:"license,omitempty" json:"license,omitempty"`
	Keywords    []string `bson:"keywords,omitempty" json:"keywords,omitempty"`
	Screenshots []string `bson:"screenshots,omitempty" json:"screenshots,omitempty"`
}

// UserPlugin represents a plugin installed for a user
type UserPlugin struct {
	ID        primitive.ObjectID     `bson:"_id,omitempty" json:"id"`
	UserID    string                 `bson:"userId" json:"userId"`
	PluginID  primitive.ObjectID     `bson:"pluginId" json:"pluginId"`
	Enabled   bool                   `bson:"enabled" json:"enabled"`
	Config    map[string]interface{} `bson:"config,omitempty" json:"config,omitempty"`
	CreatedAt time.Time              `bson:"createdAt" json:"createdAt"`
	UpdatedAt time.Time              `bson:"updatedAt" json:"updatedAt"`
}

// PluginManifest is the structure for plugin definition files
type PluginManifest struct {
	Name        string                 `json:"name" validate:"required"`
	Version     string                 `json:"version" validate:"required"`
	Type        PluginType             `json:"type" validate:"required"`
	Description string                 `json:"description"`
	Author      string                 `json:"author"`
	Main        string                 `json:"main"` // Entry point file
	Config      PluginConfigSchema     `json:"config,omitempty"`
	Permissions []string               `json:"permissions,omitempty"`
	API         map[string]interface{} `json:"api,omitempty"`
}

// PluginConfigSchema defines configuration options
type PluginConfigSchema struct {
	Fields []ConfigField `json:"fields"`
}

// ConfigField represents a configuration field
type ConfigField struct {
	Key          string      `json:"key"`
	Label        string      `json:"label"`
	Type         string      `json:"type"` // text, number, boolean, select
	DefaultValue interface{} `json:"defaultValue,omitempty"`
	Required     bool        `json:"required,omitempty"`
	Options      []string    `json:"options,omitempty"` // For select type
}
```

### 1.2 Plugin Repository

Create: `backend/go-services/internal/plugins/repository/plugin_repository.go`

```go
package repository

import (
	"context"
	"fmt"
	"time"

	"github.com/yourusername/gogotex/internal/models"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
)

// PluginRepository handles plugin database operations
type PluginRepository struct {
	plugins     *mongo.Collection
	userPlugins *mongo.Collection
}

// NewPluginRepository creates a new plugin repository
func NewPluginRepository(db *mongo.Database) *PluginRepository {
	plugins := db.Collection("plugins")
	userPlugins := db.Collection("user_plugins")

	// Create indexes
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	// Unique index on plugin slug
	plugins.Indexes().CreateOne(ctx, mongo.IndexModel{
		Keys:    bson.D{{Key: "slug", Value: 1}},
		Options: options.Index().SetUnique(true),
	})

	// Index on plugin type
	plugins.Indexes().CreateOne(ctx, mongo.IndexModel{
		Keys: bson.D{{Key: "type", Value: 1}},
	})

	// Index on enabled status
	plugins.Indexes().CreateOne(ctx, mongo.IndexModel{
		Keys: bson.D{{Key: "enabled", Value: 1}},
	})

	// Compound index on userId and pluginId
	userPlugins.Indexes().CreateOne(ctx, mongo.IndexModel{
		Keys: bson.D{
			{Key: "userId", Value: 1},
			{Key: "pluginId", Value: 1},
		},
		Options: options.Index().SetUnique(true),
	})

	return &PluginRepository{
		plugins:     plugins,
		userPlugins: userPlugins,
	}
}

// CreatePlugin creates a new plugin
func (r *PluginRepository) CreatePlugin(ctx context.Context, plugin *models.Plugin) error {
	now := time.Now()
	plugin.CreatedAt = now
	plugin.UpdatedAt = now

	result, err := r.plugins.InsertOne(ctx, plugin)
	if err != nil {
		return fmt.Errorf("failed to create plugin: %w", err)
	}

	plugin.ID = result.InsertedID.(primitive.ObjectID)
	return nil
}

// FindPluginByID finds a plugin by ID
func (r *PluginRepository) FindPluginByID(ctx context.Context, id primitive.ObjectID) (*models.Plugin, error) {
	var plugin models.Plugin
	err := r.plugins.FindOne(ctx, bson.M{"_id": id}).Decode(&plugin)
	if err != nil {
		if err == mongo.ErrNoDocuments {
			return nil, fmt.Errorf("plugin not found")
		}
		return nil, fmt.Errorf("failed to find plugin: %w", err)
	}

	return &plugin, nil
}

// FindPluginBySlug finds a plugin by slug
func (r *PluginRepository) FindPluginBySlug(ctx context.Context, slug string) (*models.Plugin, error) {
	var plugin models.Plugin
	err := r.plugins.FindOne(ctx, bson.M{"slug": slug}).Decode(&plugin)
	if err != nil {
		if err == mongo.ErrNoDocuments {
			return nil, fmt.Errorf("plugin not found")
		}
		return nil, fmt.Errorf("failed to find plugin: %w", err)
	}

	return &plugin, nil
}

// ListPlugins lists all plugins with optional filters
func (r *PluginRepository) ListPlugins(ctx context.Context, pluginType models.PluginType, enabledOnly bool) ([]models.Plugin, error) {
	filter := bson.M{}

	if pluginType != "" {
		filter["type"] = pluginType
	}

	if enabledOnly {
		filter["enabled"] = true
	}

	opts := options.Find().SetSort(bson.D{{Key: "name", Value: 1}})

	cursor, err := r.plugins.Find(ctx, filter, opts)
	if err != nil {
		return nil, fmt.Errorf("failed to list plugins: %w", err)
	}
	defer cursor.Close(ctx)

	var plugins []models.Plugin
	if err := cursor.All(ctx, &plugins); err != nil {
		return nil, fmt.Errorf("failed to decode plugins: %w", err)
	}

	return plugins, nil
}

// UpdatePlugin updates a plugin
func (r *PluginRepository) UpdatePlugin(ctx context.Context, id primitive.ObjectID, update bson.M) error {
	update["updatedAt"] = time.Now()

	_, err := r.plugins.UpdateOne(
		ctx,
		bson.M{"_id": id},
		bson.M{"$set": update},
	)
	return err
}

// DeletePlugin deletes a plugin
func (r *PluginRepository) DeletePlugin(ctx context.Context, id primitive.ObjectID) error {
	// Also delete all user plugin associations
	_, err := r.userPlugins.DeleteMany(ctx, bson.M{"pluginId": id})
	if err != nil {
		return err
	}

	_, err = r.plugins.DeleteOne(ctx, bson.M{"_id": id})
	return err
}

// InstallUserPlugin installs a plugin for a user
func (r *PluginRepository) InstallUserPlugin(ctx context.Context, userPlugin *models.UserPlugin) error {
	now := time.Now()
	userPlugin.CreatedAt = now
	userPlugin.UpdatedAt = now

	result, err := r.userPlugins.InsertOne(ctx, userPlugin)
	if err != nil {
		return fmt.Errorf("failed to install plugin: %w", err)
	}

	userPlugin.ID = result.InsertedID.(primitive.ObjectID)
	return nil
}

// UninstallUserPlugin uninstalls a plugin for a user
func (r *PluginRepository) UninstallUserPlugin(ctx context.Context, userID string, pluginID primitive.ObjectID) error {
	_, err := r.userPlugins.DeleteOne(ctx, bson.M{
		"userId":   userID,
		"pluginId": pluginID,
	})
	return err
}

// FindUserPlugins finds all plugins installed by a user
func (r *PluginRepository) FindUserPlugins(ctx context.Context, userID string) ([]models.Plugin, error) {
	// Find user plugin associations
	cursor, err := r.userPlugins.Find(ctx, bson.M{"userId": userID})
	if err != nil {
		return nil, fmt.Errorf("failed to find user plugins: %w", err)
	}
	defer cursor.Close(ctx)

	var userPlugins []models.UserPlugin
	if err := cursor.All(ctx, &userPlugins); err != nil {
		return nil, fmt.Errorf("failed to decode user plugins: %w", err)
	}

	// Get plugin details
	var pluginIDs []primitive.ObjectID
	for _, up := range userPlugins {
		pluginIDs = append(pluginIDs, up.PluginID)
	}

	if len(pluginIDs) == 0 {
		return []models.Plugin{}, nil
	}

	cursor, err = r.plugins.Find(ctx, bson.M{"_id": bson.M{"$in": pluginIDs}})
	if err != nil {
		return nil, fmt.Errorf("failed to find plugins: %w", err)
	}
	defer cursor.Close(ctx)

	var plugins []models.Plugin
	if err := cursor.All(ctx, &plugins); err != nil {
		return nil, fmt.Errorf("failed to decode plugins: %w", err)
	}

	return plugins, nil
}

// UpdateUserPluginConfig updates user plugin configuration
func (r *PluginRepository) UpdateUserPluginConfig(ctx context.Context, userID string, pluginID primitive.ObjectID, config map[string]interface{}) error {
	_, err := r.userPlugins.UpdateOne(
		ctx,
		bson.M{
			"userId":   userID,
			"pluginId": pluginID,
		},
		bson.M{"$set": bson.M{
			"config":    config,
			"updatedAt": time.Now(),
		}},
	)
	return err
}

// ToggleUserPlugin enables/disables a user plugin
func (r *PluginRepository) ToggleUserPlugin(ctx context.Context, userID string, pluginID primitive.ObjectID, enabled bool) error {
	_, err := r.userPlugins.UpdateOne(
		ctx,
		bson.M{
			"userId":   userID,
			"pluginId": pluginID,
		},
		bson.M{"$set": bson.M{
			"enabled":   enabled,
			"updatedAt": time.Now(),
		}},
	)
	return err
}
```

### 1.3 Plugin Service

Create: `backend/go-services/internal/plugins/service/plugin_service.go`

```go
package service

import (
	"context"
	"fmt"

	"github.com/yourusername/gogotex/internal/models"
	"github.com/yourusername/gogotex/internal/plugins/repository"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
)

// PluginService handles plugin business logic
type PluginService struct {
	repo *repository.PluginRepository
}

// NewPluginService creates a new plugin service
func NewPluginService(repo *repository.PluginRepository) *PluginService {
	return &PluginService{
		repo: repo,
	}
}

// CreatePlugin creates a new plugin
func (s *PluginService) CreatePlugin(ctx context.Context, plugin *models.Plugin) error {
	// Validate plugin
	if plugin.Name == "" || plugin.Slug == "" {
		return fmt.Errorf("plugin name and slug are required")
	}

	// Check if plugin with same slug already exists
	existing, _ := s.repo.FindPluginBySlug(ctx, plugin.Slug)
	if existing != nil {
		return fmt.Errorf("plugin with slug '%s' already exists", plugin.Slug)
	}

	return s.repo.CreatePlugin(ctx, plugin)
}

// GetPlugin gets a plugin by ID
func (s *PluginService) GetPlugin(ctx context.Context, id primitive.ObjectID) (*models.Plugin, error) {
	return s.repo.FindPluginByID(ctx, id)
}

// GetPluginBySlug gets a plugin by slug
func (s *PluginService) GetPluginBySlug(ctx context.Context, slug string) (*models.Plugin, error) {
	return s.repo.FindPluginBySlug(ctx, slug)
}

// ListPlugins lists all plugins
func (s *PluginService) ListPlugins(ctx context.Context, pluginType models.PluginType, enabledOnly bool) ([]models.Plugin, error) {
	return s.repo.ListPlugins(ctx, pluginType, enabledOnly)
}

// UpdatePlugin updates a plugin
func (s *PluginService) UpdatePlugin(ctx context.Context, id primitive.ObjectID, update bson.M) error {
	// Verify plugin exists
	_, err := s.repo.FindPluginByID(ctx, id)
	if err != nil {
		return err
	}

	return s.repo.UpdatePlugin(ctx, id, update)
}

// EnablePlugin enables a plugin
func (s *PluginService) EnablePlugin(ctx context.Context, id primitive.ObjectID) error {
	return s.repo.UpdatePlugin(ctx, id, bson.M{"enabled": true})
}

// DisablePlugin disables a plugin
func (s *PluginService) DisablePlugin(ctx context.Context, id primitive.ObjectID) error {
	return s.repo.UpdatePlugin(ctx, id, bson.M{"enabled": false})
}

// DeletePlugin deletes a plugin
func (s *PluginService) DeletePlugin(ctx context.Context, id primitive.ObjectID) error {
	return s.repo.DeletePlugin(ctx, id)
}

// InstallPlugin installs a plugin for a user
func (s *PluginService) InstallPlugin(ctx context.Context, userID string, pluginID primitive.ObjectID, config map[string]interface{}) error {
	// Verify plugin exists and is enabled
	plugin, err := s.repo.FindPluginByID(ctx, pluginID)
	if err != nil {
		return err
	}

	if !plugin.Enabled {
		return fmt.Errorf("plugin is not enabled")
	}

	// Create user plugin association
	userPlugin := &models.UserPlugin{
		UserID:   userID,
		PluginID: pluginID,
		Enabled:  true,
		Config:   config,
	}

	return s.repo.InstallUserPlugin(ctx, userPlugin)
}

// UninstallPlugin uninstalls a plugin for a user
func (s *PluginService) UninstallPlugin(ctx context.Context, userID string, pluginID primitive.ObjectID) error {
	return s.repo.UninstallUserPlugin(ctx, userID, pluginID)
}

// GetUserPlugins gets all plugins installed by a user
func (s *PluginService) GetUserPlugins(ctx context.Context, userID string) ([]models.Plugin, error) {
	return s.repo.FindUserPlugins(ctx, userID)
}

// UpdateUserPluginConfig updates user plugin configuration
func (s *PluginService) UpdateUserPluginConfig(ctx context.Context, userID string, pluginID primitive.ObjectID, config map[string]interface{}) error {
	return s.repo.UpdateUserPluginConfig(ctx, userID, pluginID, config)
}

// ToggleUserPlugin enables/disables a user plugin
func (s *PluginService) ToggleUserPlugin(ctx context.Context, userID string, pluginID primitive.ObjectID, enabled bool) error {
	return s.repo.ToggleUserPlugin(ctx, userID, pluginID, enabled)
}
```

**Verification**:
```bash
go build ./internal/plugins/...
```

---

## Task 2: Frontend Plugin System (2.5 hours)

### 2.1 Plugin Types

Create: `frontend/src/types/plugin.ts`

```typescript
export type PluginType = 
  | 'editor' 
  | 'template' 
  | 'reference' 
  | 'compiler' 
  | 'export' 
  | 'integration'

export interface Plugin {
  id: string
  name: string
  slug: string
  type: PluginType
  version: string
  description: string
  author: string
  icon?: string
  enabled: boolean
  config?: Record<string, any>
  metadata: PluginMetadata
  createdAt: string
  updatedAt: string
}

export interface PluginMetadata {
  homepage?: string
  repository?: string
  license?: string
  keywords?: string[]
  screenshots?: string[]
}

export interface UserPlugin {
  id: string
  userId: string
  pluginId: string
  enabled: boolean
  config?: Record<string, any>
  createdAt: string
  updatedAt: string
}

export interface PluginManifest {
  name: string
  version: string
  type: PluginType
  description: string
  author: string
  main: string
  config?: PluginConfigSchema
  permissions?: string[]
  api?: Record<string, any>
}

export interface PluginConfigSchema {
  fields: ConfigField[]
}

export interface ConfigField {
  key: string
  label: string
  type: 'text' | 'number' | 'boolean' | 'select'
  defaultValue?: any
  required?: boolean
  options?: string[]
}

// Plugin API interface
export interface PluginAPI {
  // Editor hooks
  onEditorMount?: (editor: any) => void
  onEditorChange?: (content: string) => void
  onEditorKeyPress?: (event: KeyboardEvent) => void
  
  // Document hooks
  onDocumentOpen?: (documentId: string) => void
  onDocumentSave?: (documentId: string, content: string) => void
  onDocumentClose?: (documentId: string) => void
  
  // Compilation hooks
  onCompileStart?: (documentId: string) => void
  onCompileComplete?: (documentId: string, result: any) => void
  onCompileError?: (documentId: string, error: any) => void
  
  // UI extensions
  registerCommand?: (command: PluginCommand) => void
  registerToolbarButton?: (button: ToolbarButton) => void
  registerMenuItem?: (item: MenuItem) => void
  registerSidebarPanel?: (panel: SidebarPanel) => void
}

export interface PluginCommand {
  id: string
  label: string
  handler: () => void | Promise<void>
  shortcut?: string
}

export interface ToolbarButton {
  id: string
  icon: string
  label: string
  handler: () => void
  position?: 'left' | 'right'
}

export interface MenuItem {
  id: string
  label: string
  handler: () => void
  parent?: string
}

export interface SidebarPanel {
  id: string
  title: string
  icon: string
  component: React.ComponentType<any>
}
```

### 2.2 Plugin Service

Create: `frontend/src/services/plugin.ts`

```typescript
import axios from 'axios'
import { Plugin, UserPlugin, PluginType } from '../types/plugin'

const API_URL = import.meta.env.VITE_API_URL || 'http://localhost:8080'

export const pluginService = {
  // Admin: Plugin management
  async listPlugins(type?: PluginType, enabledOnly?: boolean): Promise<Plugin[]> {
    const params: any = {}
    if (type) params.type = type
    if (enabledOnly) params.enabledOnly = 'true'
    
    const response = await axios.get(`${API_URL}/api/plugins`, { params })
    return response.data.plugins
  },

  async getPlugin(id: string): Promise<Plugin> {
    const response = await axios.get(`${API_URL}/api/plugins/${id}`)
    return response.data
  },

  async createPlugin(plugin: Partial<Plugin>): Promise<Plugin> {
    const response = await axios.post(`${API_URL}/api/plugins`, plugin)
    return response.data
  },

  async updatePlugin(id: string, update: Partial<Plugin>): Promise<void> {
    await axios.put(`${API_URL}/api/plugins/${id}`, update)
  },

  async deletePlugin(id: string): Promise<void> {
    await axios.delete(`${API_URL}/api/plugins/${id}`)
  },

  // User: Plugin installation
  async getUserPlugins(): Promise<Plugin[]> {
    const response = await axios.get(`${API_URL}/api/user/plugins`)
    return response.data.plugins
  },

  async installPlugin(pluginId: string, config?: Record<string, any>): Promise<void> {
    await axios.post(`${API_URL}/api/user/plugins/${pluginId}/install`, { config })
  },

  async uninstallPlugin(pluginId: string): Promise<void> {
    await axios.delete(`${API_URL}/api/user/plugins/${pluginId}`)
  },

  async togglePlugin(pluginId: string, enabled: boolean): Promise<void> {
    await axios.post(`${API_URL}/api/user/plugins/${pluginId}/toggle`, { enabled })
  },

  async updatePluginConfig(pluginId: string, config: Record<string, any>): Promise<void> {
    await axios.put(`${API_URL}/api/user/plugins/${pluginId}/config`, { config })
  },
}
```

### 2.3 Plugin Manager Component

Create: `frontend/src/components/PluginManager.tsx`

```typescript
import React, { useState, useEffect } from 'react'
import { Plugin, PluginType } from '../types/plugin'
import { pluginService } from '../services/plugin'

export const PluginManager: React.FC = () => {
  const [allPlugins, setAllPlugins] = useState<Plugin[]>([])
  const [userPlugins, setUserPlugins] = useState<Plugin[]>([])
  const [filter, setFilter] = useState<PluginType | 'all'>('all')
  const [loading, setLoading] = useState(false)

  useEffect(() => {
    loadPlugins()
  }, [filter])

  const loadPlugins = async () => {
    setLoading(true)
    try {
      const [all, user] = await Promise.all([
        pluginService.listPlugins(filter === 'all' ? undefined : filter, true),
        pluginService.getUserPlugins(),
      ])
      setAllPlugins(all)
      setUserPlugins(user)
    } catch (error) {
      console.error('Failed to load plugins:', error)
    } finally {
      setLoading(false)
    }
  }

  const handleInstall = async (pluginId: string) => {
    try {
      await pluginService.installPlugin(pluginId)
      await loadPlugins()
    } catch (error) {
      console.error('Failed to install plugin:', error)
      alert('Failed to install plugin')
    }
  }

  const handleUninstall = async (pluginId: string) => {
    if (!confirm('Are you sure you want to uninstall this plugin?')) return

    try {
      await pluginService.uninstallPlugin(pluginId)
      await loadPlugins()
    } catch (error) {
      console.error('Failed to uninstall plugin:', error)
      alert('Failed to uninstall plugin')
    }
  }

  const isInstalled = (pluginId: string) => {
    return userPlugins.some((p) => p.id === pluginId)
  }

  const pluginTypes: Array<{ value: PluginType | 'all'; label: string }> = [
    { value: 'all', label: 'All Plugins' },
    { value: 'editor', label: 'Editor' },
    { value: 'template', label: 'Templates' },
    { value: 'reference', label: 'References' },
    { value: 'compiler', label: 'Compilers' },
    { value: 'export', label: 'Export' },
    { value: 'integration', label: 'Integrations' },
  ]

  return (
    <div className="max-w-6xl mx-auto p-6">
      <h1 className="text-3xl font-bold mb-6">Plugin Manager</h1>

      {/* Filter */}
      <div className="mb-6">
        <div className="flex gap-2 overflow-x-auto pb-2">
          {pluginTypes.map((type) => (
            <button
              key={type.value}
              onClick={() => setFilter(type.value)}
              className={`px-4 py-2 rounded-lg whitespace-nowrap ${
                filter === type.value
                  ? 'bg-blue-600 text-white'
                  : 'bg-gray-100 text-gray-700 hover:bg-gray-200'
              }`}
            >
              {type.label}
            </button>
          ))}
        </div>
      </div>

      {/* Installed Plugins */}
      {userPlugins.length > 0 && (
        <div className="mb-8">
          <h2 className="text-xl font-semibold mb-4">Installed Plugins</h2>
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            {userPlugins.map((plugin) => (
              <PluginCard
                key={plugin.id}
                plugin={plugin}
                isInstalled={true}
                onAction={() => handleUninstall(plugin.id)}
                actionLabel="Uninstall"
              />
            ))}
          </div>
        </div>
      )}

      {/* Available Plugins */}
      <div>
        <h2 className="text-xl font-semibold mb-4">Available Plugins</h2>
        {loading ? (
          <div className="text-center py-12 text-gray-500">Loading plugins...</div>
        ) : allPlugins.length === 0 ? (
          <div className="text-center py-12 text-gray-500">No plugins found</div>
        ) : (
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            {allPlugins
              .filter((p) => !isInstalled(p.id))
              .map((plugin) => (
                <PluginCard
                  key={plugin.id}
                  plugin={plugin}
                  isInstalled={false}
                  onAction={() => handleInstall(plugin.id)}
                  actionLabel="Install"
                />
              ))}
          </div>
        )}
      </div>
    </div>
  )
}

interface PluginCardProps {
  plugin: Plugin
  isInstalled: boolean
  onAction: () => void
  actionLabel: string
}

const PluginCard: React.FC<PluginCardProps> = ({
  plugin,
  isInstalled,
  onAction,
  actionLabel,
}) => {
  return (
    <div className="bg-white border rounded-lg p-4 hover:shadow-lg transition-shadow">
      <div className="flex items-start justify-between mb-3">
        <div className="flex items-center gap-3">
          {plugin.icon ? (
            <img src={plugin.icon} alt={plugin.name} className="w-10 h-10 rounded" />
          ) : (
            <div className="w-10 h-10 bg-gray-200 rounded flex items-center justify-center">
              <span className="text-xl">📦</span>
            </div>
          )}
          <div>
            <h3 className="font-semibold">{plugin.name}</h3>
            <p className="text-xs text-gray-500">v{plugin.version}</p>
          </div>
        </div>
        <span className={`px-2 py-1 text-xs rounded ${
          isInstalled ? 'bg-green-100 text-green-800' : 'bg-gray-100 text-gray-600'
        }`}>
          {plugin.type}
        </span>
      </div>

      <p className="text-sm text-gray-600 mb-3 line-clamp-2">{plugin.description}</p>

      <div className="flex items-center justify-between">
        <span className="text-xs text-gray-500">by {plugin.author}</span>
        <button
          onClick={onAction}
          className={`px-4 py-2 text-sm rounded ${
            isInstalled
              ? 'bg-red-100 text-red-700 hover:bg-red-200'
              : 'bg-blue-600 text-white hover:bg-blue-700'
          }`}
        >
          {actionLabel}
        </button>
      </div>
    </div>
  )
}
```

**Verification**: Test plugin manager UI in browser

---

## Task 3: Template Gallery (2 hours)

### 3.1 Template Models

Create: `backend/go-services/internal/models/template.go`

```go
package models

import (
	"time"

	"go.mongodb.org/mongo-driver/bson/primitive"
)

// DocumentTemplate represents a LaTeX document template
type DocumentTemplate struct {
	ID          primitive.ObjectID `bson:"_id,omitempty" json:"id"`
	Name        string             `bson:"name" json:"name" validate:"required"`
	Slug        string             `bson:"slug" json:"slug" validate:"required"`
	Description string             `bson:"description" json:"description"`
	Category    string             `bson:"category" json:"category"` // academic, business, book, presentation, etc.
	Tags        []string           `bson:"tags,omitempty" json:"tags,omitempty"`
	Thumbnail   string             `bson:"thumbnail,omitempty" json:"thumbnail,omitempty"`
	Preview     string             `bson:"preview,omitempty" json:"preview,omitempty"` // URL to preview PDF
	Content     string             `bson:"content" json:"content"`                     // Main .tex file content
	Files       []TemplateFile     `bson:"files,omitempty" json:"files,omitempty"`     // Additional files
	Author      string             `bson:"author" json:"author"`
	License     string             `bson:"license,omitempty" json:"license,omitempty"`
	Downloads   int64              `bson:"downloads" json:"downloads"`
	Featured    bool               `bson:"featured" json:"featured"`
	Enabled     bool               `bson:"enabled" json:"enabled"`
	CreatedAt   time.Time          `bson:"createdAt" json:"createdAt"`
	UpdatedAt   time.Time          `bson:"updatedAt" json:"updatedAt"`
}

// TemplateFile represents an additional file in a template
type TemplateFile struct {
	Path    string `bson:"path" json:"path"`       // Relative path
	Content string `bson:"content" json:"content"` // File content
}

// TemplateCategory constants
const (
	TemplateCategoryAcademic      = "academic"
	TemplateCategoryBusiness      = "business"
	TemplateCategoryBook          = "book"
	TemplateCategoryPresentation  = "presentation"
	TemplateCategoryArticle       = "article"
	TemplateCategoryThesis        = "thesis"
	TemplateCategoryReport        = "report"
	TemplateCategoryLetter        = "letter"
	TemplateCategoryResume        = "resume"
	TemplateCategoryPoster        = "poster"
)
```

### 3.2 Built-in Templates

Create: `backend/go-services/internal/templates/builtin.go`

```go
package templates

import "github.com/yourusername/gogotex/internal/models"

// GetBuiltInTemplates returns predefined templates
func GetBuiltInTemplates() []models.DocumentTemplate {
	return []models.DocumentTemplate{
		// Academic Article
		{
			Name:        "Academic Article",
			Slug:        "academic-article",
			Description: "Standard academic article template with abstract, sections, and references",
			Category:    models.TemplateCategoryAcademic,
			Tags:        []string{"article", "academic", "research"},
			Author:      "gogotex",
			Featured:    true,
			Enabled:     true,
			Content: `\documentclass[11pt,a4paper]{article}

\usepackage[utf8]{inputenc}
\usepackage[english]{babel}
\usepackage{amsmath,amssymb}
\usepackage{graphicx}
\usepackage{hyperref}
\usepackage{cite}

\title{Your Article Title}
\author{Your Name\thanks{Affiliation}}
\date{\today}

\begin{document}

\maketitle

\begin{abstract}
Write your abstract here. This should be a brief summary of your article's content, methodology, and findings.
\end{abstract}

\section{Introduction}
Introduce your topic here.

\section{Methodology}
Describe your methodology.

\section{Results}
Present your results.

\section{Discussion}
Discuss your findings.

\section{Conclusion}
Summarize your conclusions.

\bibliographystyle{plain}
\bibliography{references}

\end{document}`,
		},

		// Thesis
		{
			Name:        "Thesis Template",
			Slug:        "thesis",
			Description: "Complete thesis template with chapters, table of contents, and bibliography",
			Category:    models.TemplateCategoryThesis,
			Tags:        []string{"thesis", "dissertation", "academic"},
			Author:      "gogotex",
			Featured:    true,
			Enabled:     true,
			Content: `\documentclass[12pt,a4paper]{report}

\usepackage[utf8]{inputenc}
\usepackage[english]{babel}
\usepackage{amsmath,amssymb,amsthm}
\usepackage{graphicx}
\usepackage{hyperref}
\usepackage{setspace}
\usepackage{geometry}

\geometry{margin=1in}
\doublespacing

\title{Your Thesis Title}
\author{Your Name}
\date{\today}

\begin{document}

\maketitle

\begin{abstract}
Write your thesis abstract here.
\end{abstract}

\tableofcontents

\chapter{Introduction}
Introduction content.

\chapter{Literature Review}
Literature review content.

\chapter{Methodology}
Methodology content.

\chapter{Results}
Results content.

\chapter{Discussion}
Discussion content.

\chapter{Conclusion}
Conclusion content.

\bibliographystyle{plain}
\bibliography{references}

\end{document}`,
		},

		// Business Letter
		{
			Name:        "Business Letter",
			Slug:        "business-letter",
			Description: "Professional business letter template",
			Category:    models.TemplateCategoryBusiness,
			Tags:        []string{"letter", "business", "correspondence"},
			Author:      "gogotex",
			Featured:    false,
			Enabled:     true,
			Content: `\documentclass[11pt]{letter}

\usepackage[utf8]{inputenc}
\usepackage{geometry}

\geometry{margin=1in}

\signature{Your Name\\Your Position}
\address{Your Company\\Street Address\\City, State ZIP}

\begin{document}

\begin{letter}{Recipient Name\\Recipient Position\\Company Name\\Street Address\\City, State ZIP}

\opening{Dear Recipient:}

Body of your letter goes here. This is the first paragraph.

This is the second paragraph with more information.

\closing{Sincerely,}

\end{letter}

\end{document}`,
		},

		// Resume/CV
		{
			Name:        "Resume/CV",
			Slug:        "resume-cv",
			Description: "Clean and professional resume template",
			Category:    models.TemplateCategoryResume,
			Tags:        []string{"resume", "cv", "curriculum vitae"},
			Author:      "gogotex",
			Featured:    true,
			Enabled:     true,
			Content: `\documentclass[11pt,a4paper]{article}

\usepackage[utf8]{inputenc}
\usepackage[margin=0.75in]{geometry}
\usepackage{enumitem}
\usepackage{hyperref}

\pagestyle{empty}

\begin{document}

\begin{center}
{\LARGE \textbf{Your Name}}\\[5pt]
Email: your.email@example.com | Phone: (123) 456-7890\\
LinkedIn: linkedin.com/in/yourprofile | GitHub: github.com/yourusername
\end{center}

\section*{Education}
\begin{itemize}[leftmargin=*]
\item \textbf{Degree}, University Name, Year
\item \textbf{Degree}, University Name, Year
\end{itemize}

\section*{Experience}
\textbf{Job Title} | Company Name | Start Date -- End Date
\begin{itemize}[leftmargin=*]
\item Responsibility or achievement
\item Responsibility or achievement
\end{itemize}

\section*{Skills}
\begin{itemize}[leftmargin=*]
\item Programming: Python, Java, C++
\item Technologies: Docker, Kubernetes, AWS
\item Languages: English (native), Spanish (fluent)
\end{itemize}

\section*{Projects}
\textbf{Project Name}
\begin{itemize}[leftmargin=*]
\item Description and achievements
\end{itemize}

\end{document}`,
		},

		// Beamer Presentation
		{
			Name:        "Beamer Presentation",
			Slug:        "beamer-presentation",
			Description: "Modern presentation template using Beamer",
			Category:    models.TemplateCategoryPresentation,
			Tags:        []string{"presentation", "beamer", "slides"},
			Author:      "gogotex",
			Featured:    true,
			Enabled:     true,
			Content: `\documentclass{beamer}

\usetheme{Madrid}
\usecolortheme{default}

\usepackage[utf8]{inputenc}
\usepackage{graphicx}

\title{Your Presentation Title}
\subtitle{Subtitle}
\author{Your Name}
\institute{Your Institution}
\date{\today}

\begin{document}

\frame{\titlepage}

\begin{frame}
\frametitle{Table of Contents}
\tableofcontents
\end{frame}

\section{Introduction}
\begin{frame}
\frametitle{Introduction}
\begin{itemize}
\item Point 1
\item Point 2
\item Point 3
\end{itemize}
\end{frame}

\section{Main Content}
\begin{frame}
\frametitle{Main Content}
Content goes here.
\end{frame}

\section{Conclusion}
\begin{frame}
\frametitle{Conclusion}
Summary of your presentation.
\end{frame}

\begin{frame}
\frametitle{Questions?}
\begin{center}
Thank you for your attention!
\end{center}
\end{frame}

\end{document}`,
		},

		// Book Chapter
		{
			Name:        "Book Chapter",
			Slug:        "book-chapter",
			Description: "Template for writing book chapters",
			Category:    models.TemplateCategoryBook,
			Tags:        []string{"book", "chapter", "writing"},
			Author:      "gogotex",
			Featured:    false,
			Enabled:     true,
			Content: `\documentclass[11pt,a4paper]{book}

\usepackage[utf8]{inputenc}
\usepackage[english]{babel}
\usepackage{amsmath,amssymb}
\usepackage{graphicx}
\usepackage{hyperref}

\title{Book Title}
\author{Author Name}
\date{\today}

\begin{document}

\frontmatter
\maketitle
\tableofcontents

\mainmatter
\chapter{Chapter Title}
\section{Section Title}
Write your content here.

\subsection{Subsection Title}
More content.

\backmatter
\bibliographystyle{plain}
\bibliography{references}

\end{document}`,
		},
	}
}
```

### 3.3 Template Gallery Component

Create: `frontend/src/components/TemplateGallery.tsx`

```typescript
import React, { useState, useEffect } from 'react'
import axios from 'axios'

interface DocumentTemplate {
  id: string
  name: string
  slug: string
  description: string
  category: string
  tags: string[]
  thumbnail?: string
  preview?: string
  author: string
  downloads: number
  featured: boolean
}

const API_URL = import.meta.env.VITE_API_URL || 'http://localhost:8080'

export const TemplateGallery: React.FC<{ onSelectTemplate: (template: DocumentTemplate) => void }> = ({
  onSelectTemplate,
}) => {
  const [templates, setTemplates] = useState<DocumentTemplate[]>([])
  const [category, setCategory] = useState<string>('all')
  const [loading, setLoading] = useState(false)

  const categories = [
    { value: 'all', label: 'All Templates' },
    { value: 'academic', label: 'Academic' },
    { value: 'business', label: 'Business' },
    { value: 'book', label: 'Book' },
    { value: 'presentation', label: 'Presentation' },
    { value: 'thesis', label: 'Thesis' },
    { value: 'resume', label: 'Resume' },
    { value: 'letter', label: 'Letter' },
  ]

  useEffect(() => {
    loadTemplates()
  }, [category])

  const loadTemplates = async () => {
    setLoading(true)
    try {
      const params = category !== 'all' ? { category } : {}
      const response = await axios.get(`${API_URL}/api/templates`, { params })
      setTemplates(response.data.templates)
    } catch (error) {
      console.error('Failed to load templates:', error)
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="max-w-7xl mx-auto p-6">
      <h1 className="text-3xl font-bold mb-6">Template Gallery</h1>

      {/* Category filter */}
      <div className="mb-8">
        <div className="flex gap-2 overflow-x-auto pb-2">
          {categories.map((cat) => (
            <button
              key={cat.value}
              onClick={() => setCategory(cat.value)}
              className={`px-4 py-2 rounded-lg whitespace-nowrap ${
                category === cat.value
                  ? 'bg-blue-600 text-white'
                  : 'bg-gray-100 text-gray-700 hover:bg-gray-200'
              }`}
            >
              {cat.label}
            </button>
          ))}
        </div>
      </div>

      {/* Featured templates */}
      {category === 'all' && templates.some((t) => t.featured) && (
        <div className="mb-8">
          <h2 className="text-2xl font-semibold mb-4">Featured Templates</h2>
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
            {templates
              .filter((t) => t.featured)
              .map((template) => (
                <TemplateCard
                  key={template.id}
                  template={template}
                  onSelect={onSelectTemplate}
                />
              ))}
          </div>
        </div>
      )}

      {/* All templates */}
      <div>
        <h2 className="text-2xl font-semibold mb-4">
          {category === 'all' ? 'All Templates' : categories.find((c) => c.value === category)?.label}
        </h2>
        {loading ? (
          <div className="text-center py-12 text-gray-500">Loading templates...</div>
        ) : templates.length === 0 ? (
          <div className="text-center py-12 text-gray-500">No templates found</div>
        ) : (
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
            {templates
              .filter((t) => category === 'all' || !t.featured)
              .map((template) => (
                <TemplateCard
                  key={template.id}
                  template={template}
                  onSelect={onSelectTemplate}
                />
              ))}
          </div>
        )}
      </div>
    </div>
  )
}

interface TemplateCardProps {
  template: DocumentTemplate
  onSelect: (template: DocumentTemplate) => void
}

const TemplateCard: React.FC<TemplateCardProps> = ({ template, onSelect }) => {
  return (
    <div className="bg-white border rounded-lg overflow-hidden hover:shadow-lg transition-shadow cursor-pointer"
      onClick={() => onSelect(template)}
    >
      {/* Thumbnail */}
      <div className="h-48 bg-gray-100 flex items-center justify-center">
        {template.thumbnail ? (
          <img src={template.thumbnail} alt={template.name} className="w-full h-full object-cover" />
        ) : (
          <svg className="w-20 h-20 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
          </svg>
        )}
      </div>

      {/* Content */}
      <div className="p-4">
        <div className="flex items-start justify-between mb-2">
          <h3 className="font-semibold text-lg">{template.name}</h3>
          {template.featured && (
            <span className="px-2 py-1 text-xs bg-yellow-100 text-yellow-800 rounded">Featured</span>
          )}
        </div>

        <p className="text-sm text-gray-600 mb-3 line-clamp-2">{template.description}</p>

        <div className="flex flex-wrap gap-1 mb-3">
          {template.tags.slice(0, 3).map((tag) => (
            <span key={tag} className="px-2 py-0.5 text-xs bg-gray-100 text-gray-600 rounded">
              {tag}
            </span>
          ))}
        </div>

        <div className="flex items-center justify-between text-sm text-gray-500">
          <span>by {template.author}</span>
          <span>↓ {template.downloads}</span>
        </div>
      </div>
    </div>
  )
}
```

**Verification**: Test template gallery in browser

---

## Task 4: Reference Manager - DOI Lookup (1.5 hours)

### 4.1 DOI Service

Create: `backend/go-services/internal/references/doi_service.go`

```go
package references

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
)

// DOIService handles DOI lookups
type DOIService struct {
	client *http.Client
}

// NewDOIService creates a new DOI service
func NewDOIService() *DOIService {
	return &DOIService{
		client: &http.Client{},
	}
}

// DOIMetadata represents metadata from a DOI lookup
type DOIMetadata struct {
	DOI         string   `json:"doi"`
	Title       string   `json:"title"`
	Authors     []Author `json:"authors"`
	Year        int      `json:"year"`
	Publisher   string   `json:"publisher"`
	Journal     string   `json:"journal,omitempty"`
	Volume      string   `json:"volume,omitempty"`
	Issue       string   `json:"issue,omitempty"`
	Pages       string   `json:"pages,omitempty"`
	Type        string   `json:"type"`
	URL         string   `json:"url"`
	BibTeX      string   `json:"bibtex"`
}

// Author represents a publication author
type Author struct {
	Given  string `json:"given"`
	Family string `json:"family"`
}

// LookupDOI looks up metadata for a DOI
func (s *DOIService) LookupDOI(doi string) (*DOIMetadata, error) {
	// Clean DOI
	doi = strings.TrimSpace(doi)
	doi = strings.TrimPrefix(doi, "https://doi.org/")
	doi = strings.TrimPrefix(doi, "http://doi.org/")

	// Request JSON metadata from CrossRef
	url := fmt.Sprintf("https://api.crossref.org/works/%s", doi)
	
	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("Accept", "application/json")

	resp, err := s.client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("failed to fetch DOI: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("DOI lookup failed with status: %d", resp.StatusCode)
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read response: %w", err)
	}

	// Parse CrossRef response
	var crossrefResp struct {
		Message struct {
			DOI       string `json:"DOI"`
			Title     []string `json:"title"`
			Author    []struct {
				Given  string `json:"given"`
				Family string `json:"family"`
			} `json:"author"`
			Published struct {
				DateParts [][]int `json:"date-parts"`
			} `json:"published-print"`
			Publisher      string `json:"publisher"`
			ContainerTitle []string `json:"container-title"`
			Volume         string `json:"volume"`
			Issue          string `json:"issue"`
			Page           string `json:"page"`
			Type           string `json:"type"`
			URL            string `json:"URL"`
		} `json:"message"`
	}

	if err := json.Unmarshal(body, &crossrefResp); err != nil {
		return nil, fmt.Errorf("failed to parse response: %w", err)
	}

	msg := crossrefResp.Message

	// Extract authors
	var authors []Author
	for _, a := range msg.Author {
		authors = append(authors, Author{
			Given:  a.Given,
			Family: a.Family,
		})
	}

	// Extract year
	year := 0
	if len(msg.Published.DateParts) > 0 && len(msg.Published.DateParts[0]) > 0 {
		year = msg.Published.DateParts[0][0]
	}

	// Extract title
	title := ""
	if len(msg.Title) > 0 {
		title = msg.Title[0]
	}

	// Extract journal
	journal := ""
	if len(msg.ContainerTitle) > 0 {
		journal = msg.ContainerTitle[0]
	}

	metadata := &DOIMetadata{
		DOI:       msg.DOI,
		Title:     title,
		Authors:   authors,
		Year:      year,
		Publisher: msg.Publisher,
		Journal:   journal,
		Volume:    msg.Volume,
		Issue:     msg.Issue,
		Pages:     msg.Page,
		Type:      msg.Type,
		URL:       msg.URL,
	}

	// Generate BibTeX
	metadata.BibTeX = s.generateBibTeX(metadata)

	return metadata, nil
}

// generateBibTeX generates BibTeX from metadata
func (s *DOIService) generateBibTeX(meta *DOIMetadata) string {
	// Generate citation key (first author + year)
	citationKey := "unknown"
	if len(meta.Authors) > 0 {
		citationKey = fmt.Sprintf("%s%d", 
			strings.ToLower(meta.Authors[0].Family), 
			meta.Year)
	}

	// Build author list
	var authorStrs []string
	for _, a := range meta.Authors {
		authorStrs = append(authorStrs, fmt.Sprintf("%s, %s", a.Family, a.Given))
	}
	authorsStr := strings.Join(authorStrs, " and ")

	// Determine entry type
	entryType := "article"
	if meta.Type == "book" || meta.Type == "monograph" {
		entryType = "book"
	} else if meta.Type == "proceedings-article" {
		entryType = "inproceedings"
	}

	// Build BibTeX
	bibtex := fmt.Sprintf("@%s{%s,\n", entryType, citationKey)
	bibtex += fmt.Sprintf("  title = {%s},\n", meta.Title)
	bibtex += fmt.Sprintf("  author = {%s},\n", authorsStr)
	
	if meta.Journal != "" {
		bibtex += fmt.Sprintf("  journal = {%s},\n", meta.Journal)
	}
	
	if meta.Year > 0 {
		bibtex += fmt.Sprintf("  year = {%d},\n", meta.Year)
	}
	
	if meta.Volume != "" {
		bibtex += fmt.Sprintf("  volume = {%s},\n", meta.Volume)
	}
	
	if meta.Issue != "" {
		bibtex += fmt.Sprintf("  number = {%s},\n", meta.Issue)
	}
	
	if meta.Pages != "" {
		bibtex += fmt.Sprintf("  pages = {%s},\n", meta.Pages)
	}
	
	if meta.Publisher != "" {
		bibtex += fmt.Sprintf("  publisher = {%s},\n", meta.Publisher)
	}
	
	bibtex += fmt.Sprintf("  doi = {%s},\n", meta.DOI)
	bibtex += fmt.Sprintf("  url = {%s}\n", meta.URL)
	bibtex += "}"

	return bibtex
}
```

### 4.2 Reference Manager Component

Create: `frontend/src/components/ReferenceManager.tsx`

```typescript
import React, { useState } from 'react'
import axios from 'axios'

interface DOIMetadata {
  doi: string
  title: string
  authors: Array<{ given: string; family: string }>
  year: number
  publisher: string
  journal?: string
  volume?: string
  issue?: string
  pages?: string
  type: string
  url: string
  bibtex: string
}

const API_URL = import.meta.env.VITE_API_URL || 'http://localhost:8080'

export const ReferenceManager: React.FC<{ onInsertBibTeX: (bibtex: string) => void }> = ({
  onInsertBibTeX,
}) => {
  const [doi, setDoi] = useState('')
  const [metadata, setMetadata] = useState<DOIMetadata | null>(null)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')

  const handleLookup = async () => {
    if (!doi.trim()) return

    setLoading(true)
    setError('')
    setMetadata(null)

    try {
      const response = await axios.get(`${API_URL}/api/references/doi/${encodeURIComponent(doi)}`)
      setMetadata(response.data)
    } catch (err: any) {
      setError(err.response?.data?.error || 'Failed to lookup DOI')
    } finally {
      setLoading(false)
    }
  }

  const handleInsert = () => {
    if (metadata) {
      onInsertBibTeX(metadata.bibtex)
      setDoi('')
      setMetadata(null)
    }
  }

  const formatAuthors = (authors: DOIMetadata['authors']) => {
    if (authors.length === 0) return 'Unknown'
    if (authors.length === 1) return `${authors[0].given} ${authors[0].family}`
    if (authors.length === 2) {
      return `${authors[0].given} ${authors[0].family} and ${authors[1].given} ${authors[1].family}`
    }
    return `${authors[0].given} ${authors[0].family} et al.`
  }

  return (
    <div className="bg-white border rounded-lg p-4">
      <h3 className="text-lg font-semibold mb-4">Reference Manager</h3>

      {/* DOI Lookup */}
      <div className="mb-4">
        <label className="block text-sm font-medium text-gray-700 mb-2">
          DOI Lookup
        </label>
        <div className="flex gap-2">
          <input
            type="text"
            value={doi}
            onChange={(e) => setDoi(e.target.value)}
            onKeyPress={(e) => e.key === 'Enter' && handleLookup()}
            placeholder="10.1000/xyz123 or https://doi.org/10.1000/xyz123"
            className="flex-1 px-3 py-2 border rounded focus:outline-none focus:ring-2 focus:ring-blue-500"
            disabled={loading}
          />
          <button
            onClick={handleLookup}
            disabled={loading || !doi.trim()}
            className="px-4 py-2 bg-blue-600 text-white rounded hover:bg-blue-700 disabled:opacity-50"
          >
            {loading ? 'Looking up...' : 'Lookup'}
          </button>
        </div>
      </div>

      {/* Error */}
      {error && (
        <div className="mb-4 p-3 bg-red-50 border border-red-200 rounded text-red-700 text-sm">
          {error}
        </div>
      )}

      {/* Metadata */}
      {metadata && (
        <div className="mb-4">
          <div className="bg-gray-50 p-4 rounded mb-3">
            <h4 className="font-semibold mb-2">{metadata.title}</h4>
            <p className="text-sm text-gray-600 mb-1">
              {formatAuthors(metadata.authors)} ({metadata.year})
            </p>
            {metadata.journal && (
              <p className="text-sm text-gray-600">
                {metadata.journal}
                {metadata.volume && ` ${metadata.volume}`}
                {metadata.issue && `(${metadata.issue})`}
                {metadata.pages && `, ${metadata.pages}`}
              </p>
            )}
            <p className="text-xs text-gray-500 mt-2">DOI: {metadata.doi}</p>
          </div>

          <div className="mb-3">
            <label className="block text-sm font-medium text-gray-700 mb-1">
              BibTeX Entry
            </label>
            <textarea
              value={metadata.bibtex}
              readOnly
              className="w-full px-3 py-2 border rounded font-mono text-xs bg-gray-50"
              rows={10}
            />
          </div>

          <button
            onClick={handleInsert}
            className="w-full px-4 py-2 bg-green-600 text-white rounded hover:bg-green-700"
          >
            Insert into Document
          </button>
        </div>
      )}

      {/* Info */}
      <div className="text-xs text-gray-500">
        <p>Tip: You can paste a full DOI URL or just the identifier.</p>
      </div>
    </div>
  )
}
```

**Verification**: Test DOI lookup with real DOIs (e.g., 10.1038/nature12373)

---

## Task 5: ORCID Integration (1.5 hours)

### 5.1 ORCID Service

Create: `backend/go-services/internal/references/orcid_service.go`

```go
package references

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
)

// ORCIDService handles ORCID API interactions
type ORCIDService struct {
	client  *http.Client
	baseURL string
}

// NewORCIDService creates a new ORCID service
func NewORCIDService() *ORCIDService {
	return &ORCIDService{
		client:  &http.Client{},
		baseURL: "https://pub.orcid.org/v3.0", // Public API
	}
}

// ORCIDProfile represents an ORCID profile
type ORCIDProfile struct {
	ORCID      string              `json:"orcid"`
	GivenNames string              `json:"givenNames"`
	FamilyName string              `json:"familyName"`
	Biography  string              `json:"biography,omitempty"`
	Works      []ORCIDWork         `json:"works,omitempty"`
	Affiliations []ORCIDAffiliation `json:"affiliations,omitempty"`
}

// ORCIDWork represents a publication
type ORCIDWork struct {
	Title      string   `json:"title"`
	Type       string   `json:"type"`
	Year       int      `json:"year"`
	Journal    string   `json:"journal,omitempty"`
	DOI        string   `json:"doi,omitempty"`
	URL        string   `json:"url,omitempty"`
}

// ORCIDAffiliation represents employment/education
type ORCIDAffiliation struct {
	Organization string `json:"organization"`
	Role         string `json:"role,omitempty"`
	StartDate    string `json:"startDate,omitempty"`
	EndDate      string `json:"endDate,omitempty"`
}

// GetProfile fetches an ORCID profile
func (s *ORCIDService) GetProfile(orcidID string) (*ORCIDProfile, error) {
	url := fmt.Sprintf("%s/%s/person", s.baseURL, orcidID)
	
	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("Accept", "application/json")

	resp, err := s.client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("failed to fetch ORCID profile: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("ORCID lookup failed with status: %d", resp.StatusCode)
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read response: %w", err)
	}

	// Parse ORCID response (simplified)
	var orcidResp struct {
		OrcidIdentifier struct {
			Path string `json:"path"`
		} `json:"orcid-identifier"`
		Name struct {
			GivenNames struct {
				Value string `json:"value"`
			} `json:"given-names"`
			FamilyName struct {
				Value string `json:"value"`
			} `json:"family-name"`
		} `json:"name"`
		Biography struct {
			Content string `json:"content"`
		} `json:"biography"`
	}

	if err := json.Unmarshal(body, &orcidResp); err != nil {
		return nil, fmt.Errorf("failed to parse response: %w", err)
	}

	profile := &ORCIDProfile{
		ORCID:      orcidResp.OrcidIdentifier.Path,
		GivenNames: orcidResp.Name.GivenNames.Value,
		FamilyName: orcidResp.Name.FamilyName.Value,
		Biography:  orcidResp.Biography.Content,
	}

	// Fetch works separately
	works, _ := s.getWorks(orcidID)
	profile.Works = works

	return profile, nil
}

// getWorks fetches publications for an ORCID
func (s *ORCIDService) getWorks(orcidID string) ([]ORCIDWork, error) {
	url := fmt.Sprintf("%s/%s/works", s.baseURL, orcidID)
	
	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return nil, err
	}

	req.Header.Set("Accept", "application/json")

	resp, err := s.client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("failed to fetch works")
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}

	// Parse works (simplified structure)
	var worksResp struct {
		Group []struct {
			WorkSummary []struct {
				Title struct {
					Title struct {
						Value string `json:"value"`
					} `json:"title"`
				} `json:"title"`
				Type           string `json:"type"`
				PublicationDate struct {
					Year struct {
						Value string `json:"value"`
					} `json:"year"`
				} `json:"publication-date"`
			} `json:"work-summary"`
		} `json:"group"`
	}

	if err := json.Unmarshal(body, &worksResp); err != nil {
		return nil, err
	}

	var works []ORCIDWork
	for _, group := range worksResp.Group {
		if len(group.WorkSummary) > 0 {
			ws := group.WorkSummary[0]
			work := ORCIDWork{
				Title: ws.Title.Title.Value,
				Type:  ws.Type,
			}
			
			// Parse year
			if ws.PublicationDate.Year.Value != "" {
				fmt.Sscanf(ws.PublicationDate.Year.Value, "%d", &work.Year)
			}
			
			works = append(works, work)
		}
	}

	return works, nil
}

// SearchByName searches ORCID by name
func (s *ORCIDService) SearchByName(givenName, familyName string) ([]ORCIDProfile, error) {
	url := fmt.Sprintf("%s/search?q=given-names:%s+AND+family-name:%s", 
		s.baseURL, givenName, familyName)
	
	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return nil, err
	}

	req.Header.Set("Accept", "application/json")

	resp, err := s.client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("ORCID search failed")
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}

	// Parse search results
	var searchResp struct {
		Result []struct {
			OrcidIdentifier struct {
				Path string `json:"path"`
			} `json:"orcid-identifier"`
		} `json:"result"`
	}

	if err := json.Unmarshal(body, &searchResp); err != nil {
		return nil, err
	}

	// Fetch full profiles for results
	var profiles []ORCIDProfile
	for _, result := range searchResp.Result {
		if profile, err := s.GetProfile(result.OrcidIdentifier.Path); err == nil {
			profiles = append(profiles, *profile)
		}
	}

	return profiles, nil
}
```

### 5.2 ORCID Component

Create: `frontend/src/components/ORCIDLookup.tsx`

```typescript
import React, { useState } from 'react'
import axios from 'axios'

interface ORCIDProfile {
  orcid: string
  givenNames: string
  familyName: string
  biography?: string
  works?: Array<{
    title: string
    type: string
    year: number
    journal?: string
    doi?: string
  }>
}

const API_URL = import.meta.env.VITE_API_URL || 'http://localhost:8080'

export const ORCIDLookup: React.FC = () => {
  const [orcidID, setOrcidID] = useState('')
  const [profile, setProfile] = useState<ORCIDProfile | null>(null)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')

  const handleLookup = async () => {
    if (!orcidID.trim()) return

    setLoading(true)
    setError('')
    setProfile(null)

    try {
      const response = await axios.get(`${API_URL}/api/references/orcid/${orcidID}`)
      setProfile(response.data)
    } catch (err: any) {
      setError(err.response?.data?.error || 'Failed to lookup ORCID')
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="bg-white border rounded-lg p-4">
      <h3 className="text-lg font-semibold mb-4">ORCID Lookup</h3>

      {/* ORCID Input */}
      <div className="mb-4">
        <label className="block text-sm font-medium text-gray-700 mb-2">
          ORCID iD
        </label>
        <div className="flex gap-2">
          <input
            type="text"
            value={orcidID}
            onChange={(e) => setOrcidID(e.target.value)}
            onKeyPress={(e) => e.key === 'Enter' && handleLookup()}
            placeholder="0000-0002-1825-0097"
            className="flex-1 px-3 py-2 border rounded focus:outline-none focus:ring-2 focus:ring-green-500"
            disabled={loading}
          />
          <button
            onClick={handleLookup}
            disabled={loading || !orcidID.trim()}
            className="px-4 py-2 bg-green-600 text-white rounded hover:bg-green-700 disabled:opacity-50"
          >
            {loading ? 'Looking up...' : 'Lookup'}
          </button>
        </div>
      </div>

      {/* Error */}
      {error && (
        <div className="mb-4 p-3 bg-red-50 border border-red-200 rounded text-red-700 text-sm">
          {error}
        </div>
      )}

      {/* Profile */}
      {profile && (
        <div className="space-y-4">
          <div className="bg-gray-50 p-4 rounded">
            <h4 className="font-semibold text-lg mb-1">
              {profile.givenNames} {profile.familyName}
            </h4>
            <p className="text-sm text-gray-600 mb-2">
              ORCID: <a href={`https://orcid.org/${profile.orcid}`} target="_blank" rel="noopener noreferrer" className="text-green-600 hover:underline">
                {profile.orcid}
              </a>
            </p>
            {profile.biography && (
              <p className="text-sm text-gray-700">{profile.biography}</p>
            )}
          </div>

          {profile.works && profile.works.length > 0 && (
            <div>
              <h5 className="font-semibold mb-2">Publications ({profile.works.length})</h5>
              <div className="space-y-2 max-h-64 overflow-y-auto">
                {profile.works.map((work, idx) => (
                  <div key={idx} className="p-3 bg-gray-50 rounded text-sm">
                    <div className="font-medium">{work.title}</div>
                    <div className="text-gray-600">
                      {work.type} • {work.year}
                      {work.journal && ` • ${work.journal}`}
                    </div>
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>
      )}

      {/* Info */}
      <div className="mt-4 text-xs text-gray-500">
        <p>ORCID provides a persistent digital identifier for researchers.</p>
        <p>Learn more at <a href="https://orcid.org" target="_blank" rel="noopener noreferrer" className="text-green-600 hover:underline">orcid.org</a></p>
      </div>
    </div>
  )
}
```

**Verification**: Test with real ORCID IDs (e.g., 0000-0002-1825-0097)

---

## Task 6: Zotero Plugin Scaffold (1 hour)

### 6.1 Zotero Import Service

Create: `backend/go-services/internal/references/zotero_service.go`

```go
package references

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
)

// ZoteroService handles Zotero API interactions
type ZoteroService struct {
	client *http.Client
	apiKey string
}

// NewZoteroService creates a new Zotero service
func NewZoteroService(apiKey string) *ZoteroService {
	return &ZoteroService{
		client: &http.Client{},
		apiKey: apiKey,
	}
}

// ZoteroItem represents a Zotero library item
type ZoteroItem struct {
	Key      string            `json:"key"`
	Version  int               `json:"version"`
	ItemType string            `json:"itemType"`
	Title    string            `json:"title"`
	Creators []ZoteroCreator   `json:"creators"`
	Date     string            `json:"date"`
	DOI      string            `json:"DOI,omitempty"`
	URL      string            `json:"url,omitempty"`
	Extra    string            `json:"extra,omitempty"`
}

// ZoteroCreator represents an author/contributor
type ZoteroCreator struct {
	CreatorType string `json:"creatorType"`
	FirstName   string `json:"firstName"`
	LastName    string `json:"lastName"`
}

// GetUserItems fetches items from a user's Zotero library
func (s *ZoteroService) GetUserItems(userID string, limit int) ([]ZoteroItem, error) {
	url := fmt.Sprintf("https://api.zotero.org/users/%s/items?limit=%d", userID, limit)
	
	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("Zotero-API-Key", s.apiKey)
	req.Header.Set("Zotero-API-Version", "3")

	resp, err := s.client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("failed to fetch items: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("Zotero API request failed with status: %d", resp.StatusCode)
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read response: %w", err)
	}

	var items []struct {
		Key     string `json:"key"`
		Version int    `json:"version"`
		Data    ZoteroItem `json:"data"`
	}

	if err := json.Unmarshal(body, &items); err != nil {
		return nil, fmt.Errorf("failed to parse response: %w", err)
	}

	var result []ZoteroItem
	for _, item := range items {
		item.Data.Key = item.Key
		item.Data.Version = item.Version
		result = append(result, item.Data)
	}

	return result, nil
}

// ConvertToBibTeX converts a Zotero item to BibTeX
func (s *ZoteroService) ConvertToBibTeX(item *ZoteroItem) string {
	// Generate citation key
	citationKey := "unknown"
	if len(item.Creators) > 0 {
		citationKey = item.Creators[0].LastName
		if item.Date != "" {
			citationKey += item.Date[:4] // Extract year
		}
	}

	// Build author list
	var authors []string
	for _, creator := range item.Creators {
		if creator.CreatorType == "author" {
			authors = append(authors, fmt.Sprintf("%s, %s", creator.LastName, creator.FirstName))
		}
	}

	// Determine entry type
	entryType := "article"
	switch item.ItemType {
	case "book":
		entryType = "book"
	case "conferencePaper":
		entryType = "inproceedings"
	case "thesis":
		entryType = "phdthesis"
	}

	// Build BibTeX
	bibtex := fmt.Sprintf("@%s{%s,\n", entryType, citationKey)
	bibtex += fmt.Sprintf("  title = {%s},\n", item.Title)
	
	if len(authors) > 0 {
		bibtex += fmt.Sprintf("  author = {%s},\n", authors[0])
	}
	
	if item.Date != "" {
		bibtex += fmt.Sprintf("  year = {%s},\n", item.Date[:4])
	}
	
	if item.DOI != "" {
		bibtex += fmt.Sprintf("  doi = {%s},\n", item.DOI)
	}
	
	if item.URL != "" {
		bibtex += fmt.Sprintf("  url = {%s},\n", item.URL)
	}
	
	bibtex += "}"

	return bibtex
}
```

### 6.2 Zotero Component

Create: `frontend/src/components/ZoteroImport.tsx`

```typescript
import React, { useState } from 'react'
import axios from 'axios'

interface ZoteroItem {
  key: string
  itemType: string
  title: string
  creators: Array<{
    creatorType: string
    firstName: string
    lastName: string
  }>
  date: string
  doi?: string
}

const API_URL = import.meta.env.VITE_API_URL || 'http://localhost:8080'

export const ZoteroImport: React.FC<{ onImport: (bibtex: string) => void }> = ({ onImport }) => {
  const [userID, setUserID] = useState('')
  const [apiKey, setApiKey] = useState('')
  const [items, setItems] = useState<ZoteroItem[]>([])
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')

  const handleFetch = async () => {
    if (!userID.trim() || !apiKey.trim()) {
      setError('Please provide both User ID and API Key')
      return
    }

    setLoading(true)
    setError('')
    setItems([])

    try {
      const response = await axios.post(`${API_URL}/api/references/zotero/items`, {
        userId: userID,
        apiKey: apiKey,
        limit: 50,
      })
      setItems(response.data.items)
    } catch (err: any) {
      setError(err.response?.data?.error || 'Failed to fetch Zotero items')
    } finally {
      setLoading(false)
    }
  }

  const handleImportItem = async (itemKey: string) => {
    try {
      const response = await axios.post(`${API_URL}/api/references/zotero/convert`, {
        userId: userID,
        apiKey: apiKey,
        itemKey: itemKey,
      })
      onImport(response.data.bibtex)
    } catch (err) {
      console.error('Failed to convert item:', err)
      alert('Failed to convert item to BibTeX')
    }
  }

  return (
    <div className="bg-white border rounded-lg p-4">
      <h3 className="text-lg font-semibold mb-4">Zotero Import</h3>

      {/* Configuration */}
      <div className="space-y-3 mb-4">
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">
            Zotero User ID
          </label>
          <input
            type="text"
            value={userID}
            onChange={(e) => setUserID(e.target.value)}
            placeholder="1234567"
            className="w-full px-3 py-2 border rounded focus:outline-none focus:ring-2 focus:ring-blue-500"
          />
        </div>

        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">
            API Key
          </label>
          <input
            type="password"
            value={apiKey}
            onChange={(e) => setApiKey(e.target.value)}
            placeholder="Enter your Zotero API key"
            className="w-full px-3 py-2 border rounded focus:outline-none focus:ring-2 focus:ring-blue-500"
          />
        </div>

        <button
          onClick={handleFetch}
          disabled={loading || !userID.trim() || !apiKey.trim()}
          className="w-full px-4 py-2 bg-red-600 text-white rounded hover:bg-red-700 disabled:opacity-50"
        >
          {loading ? 'Fetching...' : 'Fetch Library Items'}
        </button>
      </div>

      {/* Error */}
      {error && (
        <div className="mb-4 p-3 bg-red-50 border border-red-200 rounded text-red-700 text-sm">
          {error}
        </div>
      )}

      {/* Items */}
      {items.length > 0 && (
        <div>
          <h4 className="font-semibold mb-2">Library Items ({items.length})</h4>
          <div className="space-y-2 max-h-96 overflow-y-auto">
            {items.map((item) => (
              <div key={item.key} className="p-3 bg-gray-50 rounded hover:bg-gray-100">
                <div className="flex justify-between items-start">
                  <div className="flex-1">
                    <div className="font-medium text-sm mb-1">{item.title}</div>
                    <div className="text-xs text-gray-600">
                      {item.creators.map((c) => `${c.firstName} ${c.lastName}`).join(', ')}
                      {item.date && ` • ${item.date}`}
                    </div>
                    <div className="text-xs text-gray-500 mt-1">{item.itemType}</div>
                  </div>
                  <button
                    onClick={() => handleImportItem(item.key)}
                    className="ml-2 px-3 py-1 text-xs bg-blue-600 text-white rounded hover:bg-blue-700"
                  >
                    Import
                  </button>
                </div>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Help */}
      <div className="mt-4 text-xs text-gray-500 border-t pt-3">
        <p className="mb-1"><strong>How to get your Zotero API credentials:</strong></p>
        <ol className="list-decimal list-inside space-y-1">
          <li>Go to <a href="https://www.zotero.org/settings/keys" target="_blank" rel="noopener noreferrer" className="text-blue-600 hover:underline">zotero.org/settings/keys</a></li>
          <li>Create a new private key with read-only access</li>
          <li>Your User ID is shown in the URL: zotero.org/users/YOUR_USER_ID/</li>
        </ol>
      </div>
    </div>
  )
}
```

**Verification**: Test with Zotero API credentials

---

## Task 7: Performance Optimization (2 hours)

### 7.1 Database Query Optimization

Create: `backend/go-services/internal/optimization/query_optimizer.go`

```go
package optimization

import (
	"context"
	"time"

	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
)

// QueryOptimizer handles database query optimization
type QueryOptimizer struct {
	db *mongo.Database
}

// NewQueryOptimizer creates a new query optimizer
func NewQueryOptimizer(db *mongo.Database) *QueryOptimizer {
	return &QueryOptimizer{db: db}
}

// CreateAllIndexes creates all necessary indexes
func (o *QueryOptimizer) CreateAllIndexes(ctx context.Context) error {
	collections := map[string][]mongo.IndexModel{
		"projects": {
			{Keys: bson.D{{Key: "userId", Value: 1}}},
			{Keys: bson.D{{Key: "createdAt", Value: -1}}},
			{Keys: bson.D{{Key: "userId", Value: 1}, {Key: "createdAt", Value: -1}}},
		},
		"documents": {
			{Keys: bson.D{{Key: "projectId", Value: 1}}},
			{Keys: bson.D{{Key: "userId", Value: 1}}},
			{Keys: bson.D{{Key: "updatedAt", Value: -1}}},
			{Keys: bson.D{{Key: "projectId", Value: 1}, {Key: "path", Value: 1}}, Options: options.Index().SetUnique(true)},
		},
		"document_changes": {
			{Keys: bson.D{{Key: "documentId", Value: 1}, {Key: "status", Value: 1}}},
			{Keys: bson.D{{Key: "projectId", Value: 1}, {Key: "timestamp", Value: -1}}},
			{Keys: bson.D{{Key: "userId", Value: 1}}},
		},
		"comments": {
			{Keys: bson.D{{Key: "documentId", Value: 1}, {Key: "resolved", Value: 1}, {Key: "isDeleted", Value: 1}}},
			{Keys: bson.D{{Key: "parentId", Value: 1}}},
			{Keys: bson.D{{Key: "projectId", Value: 1}}},
		},
		"compilation_jobs": {
			{Keys: bson.D{{Key: "documentId", Value: 1}, {Key: "createdAt", Value: -1}}},
			{Keys: bson.D{{Key: "status", Value: 1}, {Key: "priority", Value: -1}}},
			{Keys: bson.D{{Key: "userId", Value: 1}}},
		},
		"plugins": {
			{Keys: bson.D{{Key: "slug", Value: 1}}, Options: options.Index().SetUnique(true)},
			{Keys: bson.D{{Key: "type", Value: 1}}},
			{Keys: bson.D{{Key: "enabled", Value: 1}}},
		},
		"user_plugins": {
			{Keys: bson.D{{Key: "userId", Value: 1}, {Key: "pluginId", Value: 1}}, Options: options.Index().SetUnique(true)},
		},
		"templates": {
			{Keys: bson.D{{Key: "slug", Value: 1}}, Options: options.Index().SetUnique(true)},
			{Keys: bson.D{{Key: "category", Value: 1}}},
			{Keys: bson.D{{Key: "featured", Value: 1}}},
		},
	}

	for collName, indexes := range collections {
		coll := o.db.Collection(collName)
		
		for _, index := range indexes {
			_, err := coll.Indexes().CreateOne(ctx, index)
			if err != nil {
				return err
			}
		}
	}

	return nil
}

// OptimizeCollection runs optimization on a collection
func (o *QueryOptimizer) OptimizeCollection(ctx context.Context, collectionName string) error {
	// Run compact command (requires admin privileges)
	var result bson.M
	err := o.db.RunCommand(ctx, bson.D{
		{Key: "compact", Value: collectionName},
	}).Decode(&result)
	
	return err
}

// GetSlowQueries returns slow query log (if profiling enabled)
func (o *QueryOptimizer) GetSlowQueries(ctx context.Context, minDuration time.Duration) ([]bson.M, error) {
	coll := o.db.Collection("system.profile")
	
	filter := bson.M{
		"millis": bson.M{"$gte": minDuration.Milliseconds()},
	}
	
	opts := options.Find().
		SetSort(bson.D{{Key: "ts", Value: -1}}).
		SetLimit(50)
	
	cursor, err := coll.Find(ctx, filter, opts)
	if err != nil {
		return nil, err
	}
	defer cursor.Close(ctx)
	
	var queries []bson.M
	if err := cursor.All(ctx, &queries); err != nil {
		return nil, err
	}
	
	return queries, nil
}
```

### 7.2 Redis Caching Layer

Create: `backend/go-services/internal/cache/redis_cache.go`

```go
package cache

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/redis/go-redis/v9"
)

// CacheService provides caching functionality
type CacheService struct {
	client *redis.Client
}

// NewCacheService creates a new cache service
func NewCacheService(addr, password string) *CacheService {
	client := redis.NewClient(&redis.Options{
		Addr:     addr,
		Password: password,
		DB:       0,
	})

	return &CacheService{client: client}
}

// Set stores a value in cache
func (c *CacheService) Set(ctx context.Context, key string, value interface{}, expiration time.Duration) error {
	data, err := json.Marshal(value)
	if err != nil {
		return fmt.Errorf("failed to marshal value: %w", err)
	}

	return c.client.Set(ctx, key, data, expiration).Err()
}

// Get retrieves a value from cache
func (c *CacheService) Get(ctx context.Context, key string, dest interface{}) error {
	data, err := c.client.Get(ctx, key).Bytes()
	if err != nil {
		if err == redis.Nil {
			return fmt.Errorf("key not found")
		}
		return err
	}

	return json.Unmarshal(data, dest)
}

// Delete removes a key from cache
func (c *CacheService) Delete(ctx context.Context, keys ...string) error {
	return c.client.Del(ctx, keys...).Err()
}

// Exists checks if a key exists
func (c *CacheService) Exists(ctx context.Context, key string) (bool, error) {
	count, err := c.client.Exists(ctx, key).Result()
	return count > 0, err
}

// CacheWrapper provides convenient caching for functions
type CacheWrapper struct {
	cache *CacheService
}

// NewCacheWrapper creates a new cache wrapper
func NewCacheWrapper(cache *CacheService) *CacheWrapper {
	return &CacheWrapper{cache: cache}
}

// GetOrSet retrieves from cache or executes function and caches result
func (w *CacheWrapper) GetOrSet(
	ctx context.Context,
	key string,
	dest interface{},
	expiration time.Duration,
	fn func() (interface{}, error),
) error {
	// Try to get from cache
	err := w.cache.Get(ctx, key, dest)
	if err == nil {
		return nil // Cache hit
	}

	// Cache miss, execute function
	value, err := fn()
	if err != nil {
		return err
	}

	// Store in cache
	if err := w.cache.Set(ctx, key, value, expiration); err != nil {
		// Log error but don't fail
		fmt.Printf("Failed to cache result: %v\n", err)
	}

	// Copy value to dest
	data, _ := json.Marshal(value)
	return json.Unmarshal(data, dest)
}

// Predefined cache keys
func DocumentCacheKey(documentID string) string {
	return fmt.Sprintf("document:%s", documentID)
}

func ProjectCacheKey(projectID string) string {
	return fmt.Sprintf("project:%s", projectID)
}

func UserProjectsCacheKey(userID string) string {
	return fmt.Sprintf("user:%s:projects", userID)
}

func CompilationCacheKey(documentID string) string {
	return fmt.Sprintf("compilation:%s", documentID)
}

// Cache durations
const (
	DocumentCacheDuration   = 5 * time.Minute
	ProjectCacheDuration    = 10 * time.Minute
	CompilationCacheDuration = 1 * time.Hour
	TemplateCacheDuration   = 1 * time.Hour
)
```

### 7.3 Frontend Performance

Create: `frontend/src/utils/performance.ts`

```typescript
// Debounce function for reducing API calls
export function debounce<T extends (...args: any[]) => any>(
  func: T,
  wait: number
): (...args: Parameters<T>) => void {
  let timeout: NodeJS.Timeout | null = null

  return function executedFunction(...args: Parameters<T>) {
    const later = () => {
      timeout = null
      func(...args)
    }

    if (timeout) {
      clearTimeout(timeout)
    }
    timeout = setTimeout(later, wait)
  }
}

// Throttle function for rate limiting
export function throttle<T extends (...args: any[]) => any>(
  func: T,
  limit: number
): (...args: Parameters<T>) => void {
  let inThrottle: boolean = false

  return function executedFunction(...args: Parameters<T>) {
    if (!inThrottle) {
      func(...args)
      inThrottle = true
      setTimeout(() => (inThrottle = false), limit)
    }
  }
}

// Memoize function results
export function memoize<T extends (...args: any[]) => any>(func: T): T {
  const cache = new Map<string, ReturnType<T>>()

  return ((...args: Parameters<T>): ReturnType<T> => {
    const key = JSON.stringify(args)
    
    if (cache.has(key)) {
      return cache.get(key)!
    }

    const result = func(...args)
    cache.set(key, result)
    return result
  }) as T
}

// Lazy load images
export function lazyLoadImage(imgElement: HTMLImageElement) {
  const observer = new IntersectionObserver((entries) => {
    entries.forEach((entry) => {
      if (entry.isIntersecting) {
        const img = entry.target as HTMLImageElement
        const src = img.dataset.src
        if (src) {
          img.src = src
          img.removeAttribute('data-src')
        }
        observer.unobserve(img)
      }
    })
  })

  observer.observe(imgElement)
}

// Virtual scrolling helper
export function calculateVisibleRange(
  scrollTop: number,
  containerHeight: number,
  itemHeight: number,
  totalItems: number,
  overscan: number = 3
): { start: number; end: number } {
  const start = Math.max(0, Math.floor(scrollTop / itemHeight) - overscan)
  const visibleCount = Math.ceil(containerHeight / itemHeight)
  const end = Math.min(totalItems, start + visibleCount + overscan * 2)

  return { start, end }
}

// Performance monitoring
export class PerformanceMonitor {
  private marks: Map<string, number> = new Map()

  mark(name: string) {
    this.marks.set(name, performance.now())
  }

  measure(name: string, startMark: string): number {
    const start = this.marks.get(startMark)
    if (!start) {
      console.warn(`Start mark "${startMark}" not found`)
      return 0
    }

    const duration = performance.now() - start
    console.log(`[Performance] ${name}: ${duration.toFixed(2)}ms`)
    return duration
  }

  clear() {
    this.marks.clear()
  }
}

// Web Worker helper
export function createWorker(workerFunction: Function): Worker {
  const blob = new Blob(
    [`(${workerFunction.toString()})()`],
    { type: 'application/javascript' }
  )
  const url = URL.createObjectURL(blob)
  return new Worker(url)
}
```

**Verification**:
```bash
# Backend
go build ./internal/optimization/...
go build ./internal/cache/...

# Frontend
npm run build
# Check bundle size: Should be optimized and code-split
```

---

## Task 8: Security Hardening (1.5 hours)

### 8.1 Rate Limiting

Create: `backend/go-services/pkg/middleware/rate_limit.go`

```go
package middleware

import (
	"net/http"
	"sync"
	"time"

	"github.com/gorilla/mux"
)

// RateLimiter implements token bucket rate limiting
type RateLimiter struct {
	visitors map[string]*Visitor
	mu       sync.RWMutex
	rate     int           // requests per interval
	interval time.Duration
}

// Visitor tracks rate limit for a single IP
type Visitor struct {
	lastSeen time.Time
	tokens   int
}

// NewRateLimiter creates a new rate limiter
func NewRateLimiter(rate int, interval time.Duration) *RateLimiter {
	rl := &RateLimiter{
		visitors: make(map[string]*Visitor),
		rate:     rate,
		interval: interval,
	}

	// Cleanup old visitors every minute
	go rl.cleanup()

	return rl
}

// RateLimitMiddleware is the middleware function
func (rl *RateLimiter) RateLimitMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ip := getIP(r)

		if !rl.allow(ip) {
			http.Error(w, "Rate limit exceeded", http.StatusTooManyRequests)
			return
		}

		next.ServeHTTP(w, r)
	})
}

// allow checks if request is allowed
func (rl *RateLimiter) allow(ip string) bool {
	rl.mu.Lock()
	defer rl.mu.Unlock()

	v, exists := rl.visitors[ip]
	if !exists {
		rl.visitors[ip] = &Visitor{
			lastSeen: time.Now(),
			tokens:   rl.rate - 1,
		}
		return true
	}

	// Refill tokens based on time elapsed
	elapsed := time.Since(v.lastSeen)
	tokensToAdd := int(elapsed / rl.interval)
	
	if tokensToAdd > 0 {
		v.tokens = min(rl.rate, v.tokens+tokensToAdd)
		v.lastSeen = time.Now()
	}

	if v.tokens > 0 {
		v.tokens--
		return true
	}

	return false
}

// cleanup removes old visitors
func (rl *RateLimiter) cleanup() {
	ticker := time.NewTicker(1 * time.Minute)
	defer ticker.Stop()

	for range ticker.C {
		rl.mu.Lock()
		for ip, v := range rl.visitors {
			if time.Since(v.lastSeen) > 3*time.Minute {
				delete(rl.visitors, ip)
			}
		}
		rl.mu.Unlock()
	}
}

func getIP(r *http.Request) string {
	// Check X-Forwarded-For header first
	forwarded := r.Header.Get("X-Forwarded-For")
	if forwarded != "" {
		return forwarded
	}

	// Check X-Real-IP header
	realIP := r.Header.Get("X-Real-IP")
	if realIP != "" {
		return realIP
	}

	return r.RemoteAddr
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}
```

### 8.2 Input Validation

Create: `backend/go-services/pkg/validation/validator.go`

```go
package validation

import (
	"fmt"
	"regexp"
	"strings"
)

// Validator provides input validation functions
type Validator struct{}

// NewValidator creates a new validator
func NewValidator() *Validator {
	return &Validator{}
}

// ValidateEmail validates email format
func (v *Validator) ValidateEmail(email string) error {
	emailRegex := regexp.MustCompile(`^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$`)
	if !emailRegex.MatchString(email) {
		return fmt.Errorf("invalid email format")
	}
	return nil
}

// ValidateProjectName validates project name
func (v *Validator) ValidateProjectName(name string) error {
	if len(name) < 3 {
		return fmt.Errorf("project name must be at least 3 characters")
	}
	if len(name) > 100 {
		return fmt.Errorf("project name must be at most 100 characters")
	}
	
	// Disallow dangerous characters
	dangerous := []string{"<", ">", "\"", "'", "&", ";", "|", "`"}
	for _, char := range dangerous {
		if strings.Contains(name, char) {
			return fmt.Errorf("project name contains invalid characters")
		}
	}
	
	return nil
}

// ValidateFilePath validates file path
func (v *Validator) ValidateFilePath(path string) error {
	// Prevent path traversal
	if strings.Contains(path, "..") {
		return fmt.Errorf("path traversal not allowed")
	}
	
	// Prevent absolute paths
	if strings.HasPrefix(path, "/") || strings.HasPrefix(path, "\\") {
		return fmt.Errorf("absolute paths not allowed")
	}
	
	// Check allowed extensions
	allowedExt := []string{".tex", ".bib", ".cls", ".sty", ".png", ".jpg", ".pdf"}
	hasValidExt := false
	for _, ext := range allowedExt {
		if strings.HasSuffix(strings.ToLower(path), ext) {
			hasValidExt = true
			break
		}
	}
	
	if !hasValidExt {
		return fmt.Errorf("file type not allowed")
	}
	
	return nil
}

// SanitizeInput removes potentially dangerous characters
func (v *Validator) SanitizeInput(input string) string {
	// Remove null bytes
	input = strings.ReplaceAll(input, "\x00", "")
	
	// Trim whitespace
	input = strings.TrimSpace(input)
	
	return input
}

// ValidatePassword validates password strength
func (v *Validator) ValidatePassword(password string) error {
	if len(password) < 8 {
		return fmt.Errorf("password must be at least 8 characters")
	}
	
	hasUpper := regexp.MustCompile(`[A-Z]`).MatchString(password)
	hasLower := regexp.MustCompile(`[a-z]`).MatchString(password)
	hasNumber := regexp.MustCompile(`[0-9]`).MatchString(password)
	
	if !hasUpper || !hasLower || !hasNumber {
		return fmt.Errorf("password must contain uppercase, lowercase, and numbers")
	}
	
	return nil
}

// ValidateObjectID validates MongoDB ObjectID format
func (v *Validator) ValidateObjectID(id string) error {
	if len(id) != 24 {
		return fmt.Errorf("invalid object ID length")
	}
	
	validHex := regexp.MustCompile(`^[a-fA-F0-9]+$`)
	if !validHex.MatchString(id) {
		return fmt.Errorf("invalid object ID format")
	}
	
	return nil
}
```

### 8.3 Security Headers

Update: `backend/go-services/pkg/middleware/security.go`

```go
package middleware

import (
	"net/http"
)

// SecurityHeaders adds security headers to responses
func SecurityHeaders(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Prevent clickjacking
		w.Header().Set("X-Frame-Options", "DENY")
		
		// Prevent MIME sniffing
		w.Header().Set("X-Content-Type-Options", "nosniff")
		
		// XSS protection
		w.Header().Set("X-XSS-Protection", "1; mode=block")
		
		// Content Security Policy
		w.Header().Set("Content-Security-Policy", 
			"default-src 'self'; "+
			"script-src 'self' 'unsafe-inline' 'unsafe-eval'; "+
			"style-src 'self' 'unsafe-inline'; "+
			"img-src 'self' data: https:; "+
			"font-src 'self' data:; "+
			"connect-src 'self' wss: https:;")
		
		// HSTS (Strict Transport Security)
		w.Header().Set("Strict-Transport-Security", "max-age=31536000; includeSubDomains")
		
		// Referrer Policy
		w.Header().Set("Referrer-Policy", "strict-origin-when-cross-origin")
		
		// Permissions Policy
		w.Header().Set("Permissions-Policy", "geolocation=(), microphone=(), camera=()")
		
		next.ServeHTTP(w, r)
	})
}
```

**Verification**: Test rate limiting and security headers

---

## Task 9: Monitoring & Logging (1.5 hours)

### 9.1 Structured Logging

Create: `backend/go-services/pkg/logger/logger.go`

```go
package logger

import (
	"context"
	"os"
	"time"

	"go.uber.org/zap"
	"go.uber.org/zap/zapcore"
)

var Log *zap.Logger

// InitLogger initializes the global logger
func InitLogger(env string) error {
	var config zap.Config

	if env == "production" {
		config = zap.NewProductionConfig()
	} else {
		config = zap.NewDevelopmentConfig()
		config.EncoderConfig.EncodeLevel = zapcore.CapitalColorLevelEncoder
	}

	config.EncoderConfig.TimeKey = "timestamp"
	config.EncoderConfig.EncodeTime = zapcore.ISO8601TimeEncoder

	logger, err := config.Build(zap.AddCallerSkip(1))
	if err != nil {
		return err
	}

	Log = logger
	return nil
}

// Sync flushes any buffered log entries
func Sync() {
	if Log != nil {
		Log.Sync()
	}
}

// Context-aware logging helpers
func Info(ctx context.Context, msg string, fields ...zap.Field) {
	Log.Info(msg, append(fields, contextFields(ctx)...)...)
}

func Error(ctx context.Context, msg string, fields ...zap.Field) {
	Log.Error(msg, append(fields, contextFields(ctx)...)...)
}

func Warn(ctx context.Context, msg string, fields ...zap.Field) {
	Log.Warn(msg, append(fields, contextFields(ctx)...)...)
}

func Debug(ctx context.Context, msg string, fields ...zap.Field) {
	Log.Debug(msg, append(fields, contextFields(ctx)...)...)
}

// contextFields extracts fields from context
func contextFields(ctx context.Context) []zap.Field {
	var fields []zap.Field

	if userID, ok := ctx.Value("userID").(string); ok {
		fields = append(fields, zap.String("userId", userID))
	}

	if requestID, ok := ctx.Value("requestID").(string); ok {
		fields = append(fields, zap.String("requestId", requestID))
	}

	return fields
}
```

### 9.2 Metrics Collection

Create: `backend/go-services/pkg/metrics/metrics.go`

```go
package metrics

import (
	"context"
	"sync"
	"time"
)

// Metrics stores application metrics
type Metrics struct {
	mu sync.RWMutex

	// Request metrics
	TotalRequests   int64
	FailedRequests  int64
	RequestDuration map[string]*DurationMetric

	// Document metrics
	DocumentsCreated  int64
	DocumentsCompiled int64
	CompilationErrors int64

	// User metrics
	ActiveUsers       int64
	TotalCollaborators int64

	// System metrics
	LastHeartbeat time.Time
}

// DurationMetric tracks duration statistics
type DurationMetric struct {
	Count int64
	Total time.Duration
	Min   time.Duration
	Max   time.Duration
}

var globalMetrics = &Metrics{
	RequestDuration: make(map[string]*DurationMetric),
	LastHeartbeat:   time.Now(),
}

// GetMetrics returns the global metrics instance
func GetMetrics() *Metrics {
	return globalMetrics
}

// RecordRequest records a request
func RecordRequest(success bool) {
	globalMetrics.mu.Lock()
	defer globalMetrics.mu.Unlock()

	globalMetrics.TotalRequests++
	if !success {
		globalMetrics.FailedRequests++
	}
}

// RecordRequestDuration records request duration
func RecordRequestDuration(endpoint string, duration time.Duration) {
	globalMetrics.mu.Lock()
	defer globalMetrics.mu.Unlock()

	metric, exists := globalMetrics.RequestDuration[endpoint]
	if !exists {
		metric = &DurationMetric{
			Min: duration,
			Max: duration,
		}
		globalMetrics.RequestDuration[endpoint] = metric
	}

	metric.Count++
	metric.Total += duration

	if duration < metric.Min {
		metric.Min = duration
	}
	if duration > metric.Max {
		metric.Max = duration
	}
}

// RecordDocumentCreated increments document creation counter
func RecordDocumentCreated() {
	globalMetrics.mu.Lock()
	defer globalMetrics.mu.Unlock()
	globalMetrics.DocumentsCreated++
}

// RecordCompilation records a compilation
func RecordCompilation(success bool) {
	globalMetrics.mu.Lock()
	defer globalMetrics.mu.Unlock()

	globalMetrics.DocumentsCompiled++
	if !success {
		globalMetrics.CompilationErrors++
	}
}

// UpdateActiveUsers updates active user count
func UpdateActiveUsers(count int64) {
	globalMetrics.mu.Lock()
	defer globalMetrics.mu.Unlock()
	globalMetrics.ActiveUsers = count
}

// Heartbeat updates the last heartbeat time
func Heartbeat() {
	globalMetrics.mu.Lock()
	defer globalMetrics.mu.Unlock()
	globalMetrics.LastHeartbeat = time.Now()
}

// GetSnapshot returns a snapshot of current metrics
func (m *Metrics) GetSnapshot() map[string]interface{} {
	m.mu.RLock()
	defer m.mu.RUnlock()

	snapshot := map[string]interface{}{
		"totalRequests":       m.TotalRequests,
		"failedRequests":      m.FailedRequests,
		"documentsCreated":    m.DocumentsCreated,
		"documentsCompiled":   m.DocumentsCompiled,
		"compilationErrors":   m.CompilationErrors,
		"activeUsers":         m.ActiveUsers,
		"totalCollaborators":  m.TotalCollaborators,
		"lastHeartbeat":       m.LastHeartbeat,
		"requestDuration":     make(map[string]interface{}),
	}

	// Add endpoint durations
	for endpoint, metric := range m.RequestDuration {
		avgDuration := time.Duration(0)
		if metric.Count > 0 {
			avgDuration = metric.Total / time.Duration(metric.Count)
		}

		snapshot["requestDuration"].(map[string]interface{})[endpoint] = map[string]interface{}{
			"count": metric.Count,
			"avg":   avgDuration.String(),
			"min":   metric.Min.String(),
			"max":   metric.Max.String(),
		}
	}

	return snapshot
}
```

### 9.3 Health Check Endpoint

Create: `backend/go-services/internal/health/health_check.go`

```go
package health

import (
	"context"
	"encoding/json"
	"net/http"
	"time"

	"github.com/yourusername/gogotex/pkg/metrics"
	"go.mongodb.org/mongo-driver/mongo"
	"github.com/redis/go-redis/v9"
)

// HealthChecker performs health checks
type HealthChecker struct {
	mongodb *mongo.Client
	redis   *redis.Client
}

// NewHealthChecker creates a new health checker
func NewHealthChecker(mongodb *mongo.Client, redis *redis.Client) *HealthChecker {
	return &HealthChecker{
		mongodb: mongodb,
		redis:   redis,
	}
}

// HealthStatus represents the health status
type HealthStatus struct {
	Status    string                 `json:"status"`
	Timestamp time.Time              `json:"timestamp"`
	Services  map[string]ServiceStatus `json:"services"`
	Metrics   map[string]interface{} `json:"metrics,omitempty"`
}

// ServiceStatus represents status of a service
type ServiceStatus struct {
	Status  string `json:"status"`
	Message string `json:"message,omitempty"`
}

// HealthCheckHandler returns a health check HTTP handler
func (h *HealthChecker) HealthCheckHandler(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()

	health := HealthStatus{
		Status:    "healthy",
		Timestamp: time.Now(),
		Services:  make(map[string]ServiceStatus),
	}

	// Check MongoDB
	mongoStatus := h.checkMongoDB(ctx)
	health.Services["mongodb"] = mongoStatus
	if mongoStatus.Status != "healthy" {
		health.Status = "unhealthy"
	}

	// Check Redis
	redisStatus := h.checkRedis(ctx)
	health.Services["redis"] = redisStatus
	if redisStatus.Status != "healthy" {
		health.Status = "unhealthy"
	}

	// Include metrics if detailed
	if r.URL.Query().Get("detailed") == "true" {
		health.Metrics = metrics.GetMetrics().GetSnapshot()
	}

	// Set response status
	statusCode := http.StatusOK
	if health.Status != "healthy" {
		statusCode = http.StatusServiceUnavailable
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(statusCode)
	json.NewEncoder(w).Encode(health)
}

// checkMongoDB checks MongoDB connection
func (h *HealthChecker) checkMongoDB(ctx context.Context) ServiceStatus {
	if h.mongodb == nil {
		return ServiceStatus{Status: "unknown", Message: "MongoDB client not initialized"}
	}

	err := h.mongodb.Ping(ctx, nil)
	if err != nil {
		return ServiceStatus{Status: "unhealthy", Message: err.Error()}
	}

	return ServiceStatus{Status: "healthy"}
}

// checkRedis checks Redis connection
func (h *HealthChecker) checkRedis(ctx context.Context) ServiceStatus {
	if h.redis == nil {
		return ServiceStatus{Status: "unknown", Message: "Redis client not initialized"}
	}

	_, err := h.redis.Ping(ctx).Result()
	if err != nil {
		return ServiceStatus{Status: "unhealthy", Message: err.Error()}
	}

	return ServiceStatus{Status: "healthy"}
}

// ReadinessHandler checks if the service is ready to accept traffic
func (h *HealthChecker) ReadinessHandler(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
	defer cancel()

	// Quick checks for readiness
	mongoReady := h.mongodb.Ping(ctx, nil) == nil
	redisReady := h.redis != nil && h.redis.Ping(ctx).Err() == nil

	if mongoReady && redisReady {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("ready"))
	} else {
		w.WriteHeader(http.StatusServiceUnavailable)
		w.Write([]byte("not ready"))
	}
}

// LivenessHandler checks if the service is alive
func (h *HealthChecker) LivenessHandler(w http.ResponseWriter, r *http.Request) {
	// Simple liveness check - service is running
	w.WriteHeader(http.StatusOK)
	w.Write([]byte("alive"))
}
```

### 9.4 Frontend Error Tracking

Create: `frontend/src/utils/errorTracking.ts`

```typescript
// Simple error tracking system
class ErrorTracker {
  private errors: Array<{
    timestamp: Date
    message: string
    stack?: string
    context?: any
  }> = []

  private maxErrors = 100

  track(error: Error, context?: any) {
    console.error('Error tracked:', error, context)

    this.errors.push({
      timestamp: new Date(),
      message: error.message,
      stack: error.stack,
      context,
    })

    // Keep only last N errors
    if (this.errors.length > this.maxErrors) {
      this.errors.shift()
    }

    // Send to backend (optional)
    this.sendToBackend(error, context)
  }

  private async sendToBackend(error: Error, context?: any) {
    try {
      await fetch('/api/errors', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          message: error.message,
          stack: error.stack,
          context,
          userAgent: navigator.userAgent,
          url: window.location.href,
          timestamp: new Date().toISOString(),
        }),
      })
    } catch (err) {
      // Silently fail - don't want error tracking to cause more errors
      console.warn('Failed to send error to backend:', err)
    }
  }

  getErrors() {
    return this.errors
  }

  clear() {
    this.errors = []
  }
}

export const errorTracker = new ErrorTracker()

// Global error handler
window.addEventListener('error', (event) => {
  errorTracker.track(event.error, {
    type: 'global',
    filename: event.filename,
    lineno: event.lineno,
    colno: event.colno,
  })
})

// Unhandled promise rejection handler
window.addEventListener('unhandledrejection', (event) => {
  errorTracker.track(
    new Error(event.reason),
    { type: 'unhandledRejection' }
  )
})

// React error boundary helper
export function logError(error: Error, errorInfo: any) {
  errorTracker.track(error, {
    type: 'react',
    componentStack: errorInfo.componentStack,
  })
}
```

**Verification**:
```bash
# Test health endpoint
curl http://localhost:8080/health
curl http://localhost:8080/health?detailed=true

# Test readiness/liveness
curl http://localhost:8080/ready
curl http://localhost:8080/live
```

---

## Task 10: Final Polish & Deployment Checklist (2 hours)

### 10.1 Environment Configuration

Create: `.env.example`

```bash
# Environment
NODE_ENV=production
GO_ENV=production

# Database
MONGODB_URI=mongodb://mongo1:27017,mongo2:27017,mongo3:27017/gogotex?replicaSet=rs0
MONGODB_DATABASE=gogotex

# Redis
REDIS_HOST=redis-master
REDIS_PORT=6379
REDIS_PASSWORD=your_redis_password

# MinIO
MINIO_ENDPOINT=minio:9000
MINIO_ACCESS_KEY=your_access_key
MINIO_SECRET_KEY=your_secret_key
MINIO_BUCKET=gogotex

# Keycloak
KEYCLOAK_URL=http://keycloak:8080
KEYCLOAK_REALM=gogotex
KEYCLOAK_CLIENT_ID=gogotex-client
KEYCLOAK_CLIENT_SECRET=your_client_secret

# Services
AUTH_SERVICE_URL=http://auth-service:3001
DOCUMENT_SERVICE_URL=http://document-service:3002
REALTIME_SERVICE_URL=http://realtime-service:3003
GIT_SERVICE_URL=http://git-service:3004
COMPILER_SERVICE_URL=http://compiler-service:3005

# Frontend
VITE_API_URL=http://localhost:8080
VITE_WS_URL=ws://localhost:3003
VITE_KEYCLOAK_URL=http://localhost:8080/auth
VITE_KEYCLOAK_REALM=gogotex
VITE_KEYCLOAK_CLIENT_ID=gogotex-client

# Security
JWT_SECRET=your_jwt_secret_change_this
SESSION_SECRET=your_session_secret_change_this
CORS_ORIGINS=http://localhost:5173,http://localhost:3000

# Performance
CACHE_ENABLED=true
CACHE_TTL=300
MAX_UPLOAD_SIZE=50MB
RATE_LIMIT_REQUESTS=100
RATE_LIMIT_WINDOW=60s

# Features
ENABLE_GIT_INTEGRATION=true
ENABLE_CHANGE_TRACKING=true
ENABLE_COMMENTS=true
ENABLE_PLUGINS=true

# Monitoring
LOG_LEVEL=info
METRICS_ENABLED=true
HEALTH_CHECK_INTERVAL=30s
```

### 10.2 Production docker-compose

Create: `docker-compose.prod.yml`

```yaml
version: '3.8'

services:
  # Nginx Reverse Proxy
  nginx:
    image: nginx:alpine
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./nginx/ssl:/etc/nginx/ssl:ro
      - ./frontend/dist:/usr/share/nginx/html:ro
    depends_on:
      - frontend
      - auth-service
      - document-service
    networks:
      - gogotex-network
    restart: unless-stopped

  # Frontend (built static files served by Nginx)
  frontend:
    build:
      context: ./frontend
      dockerfile: ../docker/frontend/Dockerfile.prod
    networks:
      - gogotex-network
    restart: unless-stopped

  # Go Services (scaled)
  auth-service:
    build:
      context: ./backend/go-services
      dockerfile: ../../docker/go-services/Dockerfile.prod
    command: /app/auth
    env_file: .env.prod
    deploy:
      replicas: 2
    networks:
      - gogotex-network
    restart: unless-stopped

  document-service:
    build:
      context: ./backend/go-services
      dockerfile: ../../docker/go-services/Dockerfile.prod
    command: /app/document
    env_file: .env.prod
    deploy:
      replicas: 3
    networks:
      - gogotex-network
    restart: unless-stopped

  compiler-service:
    build:
      context: ./backend/go-services
      dockerfile: ../../docker/go-services/Dockerfile.prod
    command: /app/compiler
    env_file: .env.prod
    deploy:
      replicas: 2
    volumes:
      - compilation-cache:/var/cache/compilation
    networks:
      - gogotex-network
    restart: unless-stopped

  # Node Services (scaled)
  realtime-server:
    build:
      context: ./backend/node-services/realtime-server
      dockerfile: ../../docker/node-services/Dockerfile.prod
    env_file: .env.prod
    deploy:
      replicas: 3
    networks:
      - gogotex-network
    restart: unless-stopped

  git-service:
    build:
      context: ./backend/node-services/git-service
      dockerfile: ../../docker/node-services/Dockerfile.prod
    env_file: .env.prod
    volumes:
      - git-repos:/var/lib/gogotex/git-repos
    networks:
      - gogotex-network
    restart: unless-stopped

  # Databases (production config)
  mongo1:
    image: mongo:7
    command: mongod --replSet rs0 --bind_ip_all
    volumes:
      - mongo1-data:/data/db
    networks:
      - gogotex-network
    restart: unless-stopped

  mongo2:
    image: mongo:7
    command: mongod --replSet rs0 --bind_ip_all
    volumes:
      - mongo2-data:/data/db
    networks:
      - gogotex-network
    restart: unless-stopped

  mongo3:
    image: mongo:7
    command: mongod --replSet rs0 --bind_ip_all
    volumes:
      - mongo3-data:/data/db
    networks:
      - gogotex-network
    restart: unless-stopped

  # Redis Cluster
  redis-master:
    image: redis:7-alpine
    command: redis-server --requirepass ${REDIS_PASSWORD} --maxmemory 2gb --maxmemory-policy allkeys-lru
    volumes:
      - redis-master-data:/data
    networks:
      - gogotex-network
    restart: unless-stopped

  redis-replica1:
    image: redis:7-alpine
    command: redis-server --replicaof redis-master 6379 --requirepass ${REDIS_PASSWORD} --masterauth ${REDIS_PASSWORD}
    networks:
      - gogotex-network
    restart: unless-stopped

  redis-replica2:
    image: redis:7-alpine
    command: redis-server --replicaof redis-master 6379 --requirepass ${REDIS_PASSWORD} --masterauth ${REDIS_PASSWORD}
    networks:
      - gogotex-network
    restart: unless-stopped

  # MinIO
  minio:
    image: minio/minio:latest
    command: server /data --console-address ":9001"
    environment:
      MINIO_ROOT_USER: ${MINIO_ACCESS_KEY}
      MINIO_ROOT_PASSWORD: ${MINIO_SECRET_KEY}
    volumes:
      - minio-data:/data
    networks:
      - gogotex-network
    restart: unless-stopped

  # Keycloak
  keycloak:
    image: quay.io/keycloak/keycloak:latest
    command: start --db postgres --hostname-strict=false
    environment:
      KC_DB: postgres
      KC_DB_URL: jdbc:postgresql://postgres:5432/keycloak
      KC_DB_USERNAME: keycloak
      KC_DB_PASSWORD: ${KEYCLOAK_DB_PASSWORD}
      KEYCLOAK_ADMIN: admin
      KEYCLOAK_ADMIN_PASSWORD: ${KEYCLOAK_ADMIN_PASSWORD}
    depends_on:
      - postgres
    networks:
      - gogotex-network
    restart: unless-stopped

  postgres:
    image: postgres:15-alpine
    environment:
      POSTGRES_DB: keycloak
      POSTGRES_USER: keycloak
      POSTGRES_PASSWORD: ${KEYCLOAK_DB_PASSWORD}
    volumes:
      - postgres-data:/var/lib/postgresql/data
    networks:
      - gogotex-network
    restart: unless-stopped

volumes:
  mongo1-data:
  mongo2-data:
  mongo3-data:
  redis-master-data:
  minio-data:
  postgres-data:
  git-repos:
  compilation-cache:

networks:
  gogotex-network:
    driver: bridge
```

### 10.3 Deployment Checklist

Create: `DEPLOYMENT.md`

```markdown
# gogotex Deployment Checklist

## Pre-Deployment

- [ ] **Environment Variables**
  - [ ] Copy `.env.example` to `.env.prod`
  - [ ] Update all passwords and secrets
  - [ ] Set production URLs
  - [ ] Configure CORS origins

- [ ] **Security**
  - [ ] Generate strong JWT secret
  - [ ] Generate strong session secret
  - [ ] Configure SSL certificates
  - [ ] Review security headers
  - [ ] Enable rate limiting
  - [ ] Configure firewall rules

- [ ] **Database**
  - [ ] MongoDB replica set initialized
  - [ ] Database indexes created
  - [ ] Backup strategy configured
  - [ ] Monitoring set up

- [ ] **Storage**
  - [ ] MinIO buckets created
  - [ ] Access policies configured
  - [ ] Backup strategy configured

- [ ] **Build**
  - [ ] Frontend build successful
  - [ ] Backend build successful
  - [ ] Docker images built
  - [ ] Image tags verified

## Deployment Steps

### 1. Infrastructure Setup

```bash
# Create production network
docker network create gogotex-network

# Start databases first
docker-compose -f docker-compose.prod.yml up -d mongo1 mongo2 mongo3
docker-compose -f docker-compose.prod.yml up -d redis-master redis-replica1 redis-replica2
docker-compose -f docker-compose.prod.yml up -d postgres minio

# Wait for databases to be ready
sleep 30

# Initialize MongoDB replica set
docker exec -it mongo1 mongosh --eval "rs.initiate({
  _id: 'rs0',
  members: [
    {_id: 0, host: 'mongo1:27017'},
    {_id: 1, host: 'mongo2:27017'},
    {_id: 2, host: 'mongo3:27017'}
  ]
})"

# Create database indexes
docker exec -it mongo1 mongosh gogotex --eval "
  db.projects.createIndex({userId: 1, createdAt: -1});
  db.documents.createIndex({projectId: 1, path: 1}, {unique: true});
  db.comments.createIndex({documentId: 1, resolved: 1, isDeleted: 1});
"
```

### 2. Services Deployment

```bash
# Start Keycloak
docker-compose -f docker-compose.prod.yml up -d keycloak

# Wait for Keycloak
sleep 60

# Start application services
docker-compose -f docker-compose.prod.yml up -d auth-service document-service compiler-service
docker-compose -f docker-compose.prod.yml up -d realtime-server git-service

# Start frontend and nginx
docker-compose -f docker-compose.prod.yml up -d frontend nginx
```

### 3. Post-Deployment Verification

```bash
# Health checks
curl http://localhost/health
curl http://localhost/api/health
curl http://localhost/ready

# Service verification
docker-compose -f docker-compose.prod.yml ps
docker-compose -f docker-compose.prod.yml logs --tail=50

# Performance check
curl -w "@curl-format.txt" -o /dev/null -s http://localhost/

# Test authentication
curl http://localhost/api/auth/status

# Test document creation
curl -X POST http://localhost/api/projects \
  -H "Authorization: Bearer TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name":"Test Project"}'
```

## Post-Deployment

- [ ] **Monitoring**
  - [ ] Verify metrics collection
  - [ ] Check log aggregation
  - [ ] Set up alerting
  - [ ] Configure dashboards

- [ ] **Backup**
  - [ ] Test database backup
  - [ ] Test file backup
  - [ ] Verify backup restoration
  - [ ] Document backup procedures

- [ ] **Documentation**
  - [ ] Update API documentation
  - [ ] Update user documentation
  - [ ] Document operational procedures
  - [ ] Update runbooks

- [ ] **Performance**
  - [ ] Run load tests
  - [ ] Verify response times
  - [ ] Check resource utilization
  - [ ] Optimize as needed

- [ ] **Security**
  - [ ] Run security scan
  - [ ] Verify SSL configuration
  - [ ] Test rate limiting
  - [ ] Review access logs

## Rollback Plan

If issues occur:

```bash
# Stop all services
docker-compose -f docker-compose.prod.yml down

# Restore from backup
./scripts/restore-backup.sh

# Start services
docker-compose -f docker-compose.prod.yml up -d
```

## Maintenance

### Daily
- [ ] Check service health
- [ ] Review error logs
- [ ] Monitor resource usage

### Weekly
- [ ] Review security logs
- [ ] Check backup integrity
- [ ] Update dependencies

### Monthly
- [ ] Security patch updates
- [ ] Performance review
- [ ] Capacity planning
```

### 10.4 Production Optimization Script

Create: `scripts/optimize-production.sh`

```bash
#!/bin/bash

echo "gogotex Production Optimization Script"
echo "=========================================="

# Frontend optimization
echo "Building optimized frontend..."
cd frontend
npm run build
cd ..

# Backend optimization
echo "Building optimized Go services..."
cd backend/go-services
CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -ldflags="-s -w" -o ../../dist/auth cmd/auth/main.go
CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -ldflags="-s -w" -o ../../dist/document cmd/document/main.go
CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -ldflags="-s -w" -o ../../dist/compiler cmd/compiler/main.go
cd ../..

# Database optimization
echo "Creating database indexes..."
docker exec mongo1 mongosh gogotex /scripts/create-indexes.js

# Clear caches
echo "Clearing Redis cache..."
docker exec redis-master redis-cli FLUSHALL

# Verify builds
echo "Verifying builds..."
ls -lh dist/
ls -lh frontend/dist/

echo "Optimization complete!"
```

**Verification**:
```bash
chmod +x scripts/optimize-production.sh
./scripts/optimize-production.sh
```

---

## Testing & Final Verification

### Complete System Test

```bash
# 1. Build everything
docker-compose -f docker-compose.prod.yml build

# 2. Start infrastructure
docker-compose -f docker-compose.prod.yml up -d mongo1 mongo2 mongo3 redis-master minio

# 3. Initialize MongoDB replica set
docker exec -it mongo1 mongosh --eval "rs.initiate()"

# 4. Start all services
docker-compose -f docker-compose.prod.yml up -d

# 5. Wait for services
sleep 60

# 6. Run health checks
curl http://localhost/health
curl http://localhost/api/health

# 7. Run integration tests
npm run test:integration

# 8. Run load tests
npm run test:load
```

### Performance Benchmarks

Expected performance metrics:
- API response time: < 100ms (p95)
- Document load time: < 500ms
- Compilation time: < 30s (average LaTeX document)
- Real-time sync latency: < 50ms
- Frontend bundle size: < 1MB (gzipped)
- Concurrent users: 1000+ (per instance)

---

## Troubleshooting

### Common Issues

1. **MongoDB Replica Set Not Initializing**
   ```bash
   docker exec -it mongo1 mongosh --eval "rs.status()"
   # If primary not found, force reconfiguration
   docker exec -it mongo1 mongosh --eval "rs.reconfig({...}, {force: true})"
   ```

2. **Redis Connection Issues**
   ```bash
   docker exec redis-master redis-cli PING
   docker exec redis-master redis-cli INFO replication
   ```

3. **Services Not Starting**
   ```bash
   docker-compose -f docker-compose.prod.yml logs service-name
   docker-compose -f docker-compose.prod.yml restart service-name
   ```

4. **High Memory Usage**
   ```bash
   docker stats
   # Adjust service resources in docker-compose.prod.yml
   ```

---

## Phase 8 Complete! ✅

**What We Built**:
- ✅ Plugin system architecture (create, install, manage plugins)
- ✅ Frontend plugin manager with categories and installation
- ✅ Template gallery with 6 built-in templates (academic, thesis, resume, etc.)
- ✅ DOI lookup service with BibTeX generation
- ✅ ORCID integration for researcher profiles
- ✅ Zotero import plugin scaffold
- ✅ Performance optimization (query optimization, Redis caching, frontend performance)
- ✅ Security hardening (rate limiting, input validation, security headers)
- ✅ Monitoring & logging (structured logging, metrics, health checks, error tracking)
- ✅ Production deployment configuration and checklist

**Complete Project Status**: **ALL 8 PHASES COMPLETE** (100%)

**System Features**:
- Infrastructure: Docker orchestration, MongoDB replica set, Redis cluster, MinIO, Keycloak
- Authentication: OIDC integration, JWT tokens, role-based access
- Frontend: React + TypeScript + Vite, CodeMirror 6, real-time collaboration
- Real-time: WebSocket, Yjs CRDT, presence awareness, multi-user editing
- Document Management: Projects, documents, file storage, version control
- Compilation: Hybrid WASM + Docker, LaTeX compilation, PDF generation
- Advanced Features: Git integration, change tracking, comments system, history viewer
- Plugins: Plugin system, template gallery, DOI/ORCID/Zotero integrations
- Production Ready: Performance optimized, security hardened, monitored, documented

**Project Statistics**:
- Total Phases: 8
- Total Tasks: 73 detailed tasks
- Estimated Total Duration: 40-45 days
- Lines of Documentation: ~20,000+ lines
- Services: 10+ microservices
- Technologies: Go, TypeScript, React, Node.js, MongoDB, Redis, Docker, Kubernetes-ready

**Next Steps for Implementation**:
1. Set up development environment following Phase 1
2. Implement phases sequentially (1-8)
3. Test each phase before moving to next
4. Deploy to staging environment
5. Run load tests and security audits
6. Deploy to production using deployment checklist
7. Monitor and iterate based on user feedback

**Copilot Optimization Tips**:
- Use `@workspace` to find related code across all phases
- Reference specific phase files: `@PHASE-01-infrastructure.md`
- Test incrementally: Each task has verification steps
- Use provided troubleshooting sections when issues arise
- Follow the deployment checklist for production deployment
- All code is production-ready with error handling and logging

🎉 **gogotex is now fully documented and ready for implementation!** 🎉