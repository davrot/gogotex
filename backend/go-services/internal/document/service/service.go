package service

import (
	"errors"

	"github.com/gogotex/gogotex/backend/go-services/internal/document"
	"github.com/gogotex/gogotex/backend/go-services/internal/document/repository"
	"go.mongodb.org/mongo-driver/mongo"
)

var (
	ErrNotFound = errors.New("not found")
)

// Service defines the document business operations used by the handler layer.
type Service interface {
	Create(d *document.Document) (string, error)
	Get(id string) (*document.Document, error)
	List() ([]*document.Document, error)
	Update(id string, content string, name *string) error
	Delete(id string) error
}

// NewMemoryService returns a Service backed by the in-memory repository.
func NewMemoryService() Service {
	repo := repository.NewMemoryRepo()
	return &memoryService{repo: repo}
}

// NewMongoService returns a Service backed by a MongoDB collection.
// Caller is responsible for creating the collection (and client) and passing it in.
func NewMongoService(col *mongo.Collection) Service {
	repo := repository.NewMongoRepo(col)
	return &memoryService{repo: nil, mongoRepo: repo}
}

type memoryService struct {
	repo      *repository.MemoryRepo
	mongoRepo *repository.MongoRepo
}

func (m *memoryService) Create(d *document.Document) (string, error) {
	if m.mongoRepo != nil {
		return m.mongoRepo.Create(d)
	}
	return m.repo.Create(d)
}

func (m *memoryService) Get(id string) (*document.Document, error) {
	if m.mongoRepo != nil {
		d, err := m.mongoRepo.Get(id)
		if err != nil {
			return nil, ErrNotFound
		}
		return d, nil
	}
	d, err := m.repo.Get(id)
	if err != nil {
		return nil, ErrNotFound
	}
	return d, nil
}

func (m *memoryService) List() ([]*document.Document, error) {
	if m.mongoRepo != nil {
		return m.mongoRepo.List()
	}
	return m.repo.List()
}

func (m *memoryService) Update(id string, content string, name *string) error {
	if m.mongoRepo != nil {
		return m.mongoRepo.Update(id, content, name)
	}
	return m.repo.Update(id, content, name)
}

func (m *memoryService) Delete(id string) error {
	if m.mongoRepo != nil {
		return m.mongoRepo.Delete(id)
	}
	return m.repo.Delete(id)
}
