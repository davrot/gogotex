package sessions

import (
	"context"
	"time"

	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/mongo"
)

// Repository provides session persistence operations
type Repository interface {
	Create(ctx context.Context, s *Session) error
	GetByRefresh(ctx context.Context, refresh string) (*Session, error)
	DeleteByRefresh(ctx context.Context, refresh string) error
}

// MongoRepository implements Repository using a Mongo collection
type MongoRepository struct {
	col *mongo.Collection
}

func NewMongoRepository(col *mongo.Collection) *MongoRepository {
	return &MongoRepository{col: col}
}

func (r *MongoRepository) Create(ctx context.Context, s *Session) error {
	now := time.Now().UTC()
	if s.CreatedAt.IsZero() {
		s.CreatedAt = now
	}
	if s.ExpiresAt.IsZero() {
		s.ExpiresAt = now.Add(7 * 24 * time.Hour)
	}
	_, err := r.col.InsertOne(ctx, s)
	return err
}

func (r *MongoRepository) GetByRefresh(ctx context.Context, refresh string) (*Session, error) {
	var s Session
	if err := r.col.FindOne(ctx, bson.M{"refreshToken": refresh}).Decode(&s); err != nil {
		if err == mongo.ErrNoDocuments {
			return nil, nil
		}
		return nil, err
	}
	return &s, nil
}

func (r *MongoRepository) DeleteByRefresh(ctx context.Context, refresh string) error {
	_, err := r.col.DeleteOne(ctx, bson.M{"refreshToken": refresh})
	return err
}
