package repository

import (
	"errors"
	"sync"
	"time"

	"github.com/gogotex/gogotex/backend/go-services/internal/document"
)

var (
	ErrNotFound = errors.New("document not found")
)

// MemoryRepo is a simple in-memory repository used for initial implementation
// and unit tests. It will be replaced by a Mongo-backed repository in Phase-05.
type MemoryRepo struct {
	mu    sync.RWMutex
	store map[string]*document.Document
}

func NewMemoryRepo() *MemoryRepo {
	return &MemoryRepo{store: make(map[string]*document.Document)}
}

func (m *MemoryRepo) Create(doc *document.Document) (string, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if doc.ID == "" {
		doc.ID = "doc_" + time.Now().Format("20060102T150405.000000000")
	}
	doc.CreatedAt = time.Now()
	doc.UpdatedAt = doc.CreatedAt
	m.store[doc.ID] = doc
	return doc.ID, nil
}

func (m *MemoryRepo) Get(id string) (*document.Document, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	if d, ok := m.store[id]; ok {
		return d, nil
	}
	return nil, ErrNotFound
}

func (m *MemoryRepo) List() ([]*document.Document, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	out := make([]*document.Document, 0, len(m.store))
	for _, d := range m.store {
		out = append(out, d)
	}
	return out, nil
}

func (m *MemoryRepo) Update(id string, content string, name *string) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	d, ok := m.store[id]
	if !ok {
		return ErrNotFound
	}
	if name != nil {
		d.Name = *name
	}
	d.Content = content
	d.UpdatedAt = time.Now()
	return nil
}

func (m *MemoryRepo) Delete(id string) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if _, ok := m.store[id]; !ok {
		return ErrNotFound
	}
	delete(m.store, id)
	return nil
}
