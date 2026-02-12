package users

import (
	"context"
	"time"

	"github.com/gogotex/gogotex/backend/go-services/internal/models"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
)

// UserRepository defines persistence operations for users
type UserRepository interface {
	UpsertBySub(ctx context.Context, u *models.User) (*models.User, error)
	GetBySub(ctx context.Context, sub string) (*models.User, error)
}

// MongoUserRepository implements UserRepository using MongoDB
type MongoUserRepository struct {
	col *mongo.Collection
}

// NewMongoUserRepository creates a new repository for the given collection
func NewMongoUserRepository(col *mongo.Collection) *MongoUserRepository {
	return &MongoUserRepository{col: col}
}

func (r *MongoUserRepository) UpsertBySub(ctx context.Context, u *models.User) (*models.User, error) {
	now := time.Now().UTC()
	if u.CreatedAt.IsZero() {
		u.CreatedAt = now
	}
	u.UpdatedAt = now

	filter := bson.M{"sub": u.Sub}
	repl := bson.M{"$set": bson.M{
		"email":     u.Email,
		"name":      u.Name,
		"updatedAt": u.UpdatedAt,
		"createdAt": u.CreatedAt,
	}}
	opts := options.FindOneAndUpdate().SetUpsert(true).SetReturnDocument(options.After)
	var updated models.User
	if err := r.col.FindOneAndUpdate(ctx, filter, repl, opts).Decode(&updated); err != nil {
		if err == mongo.ErrNoDocuments {
			// Shouldn't happen because of upsert, but handle gracefully
			return u, nil
		}
		return nil, err
	}
	return &updated, nil
}

func (r *MongoUserRepository) GetBySub(ctx context.Context, sub string) (*models.User, error) {
	var u models.User
	if err := r.col.FindOne(ctx, bson.M{"sub": sub}).Decode(&u); err != nil {
		if err == mongo.ErrNoDocuments {
			return nil, nil
		}
		return nil, err
	}
	return &u, nil
}
