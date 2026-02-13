package repository

import (
	"context"
	"time"

	"github.com/gogotex/gogotex/backend/go-services/internal/document"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
)

// MongoRepo implements a MongoDB-backed repository for documents.
// The repo stores documents with an "id" string field (keeps compatibility
// with Phase‑03 prototype IDs). In Phase‑05 we may switch to ObjectIDs.
type MongoRepo struct {
	col *mongo.Collection
}

func NewMongoRepo(col *mongo.Collection) *MongoRepo {
	// ensure an index on "id" for fast lookups (id is expected unique)
	idxModel := mongo.IndexModel{Keys: bson.D{{Key: "id", Value: 1}}, Options: options.Index().SetUnique(true)}
	col.Indexes().CreateOne(context.Background(), idxModel)
	return &MongoRepo{col: col}
}

func (m *MongoRepo) Create(doc *document.Document) (string, error) {
	now := time.Now()
	doc.CreatedAt = now
	doc.UpdatedAt = now
	_, err := m.col.InsertOne(context.Background(), doc)
	if err != nil {
		return "", err
	}
	return doc.ID, nil
}

func (m *MongoRepo) Get(id string) (*document.Document, error) {
	var d document.Document
	err := m.col.FindOne(context.Background(), bson.M{"id": id}).Decode(&d)
	if err != nil {
		if err == mongo.ErrNoDocuments {
			return nil, ErrNotFound
		}
		return nil, err
	}
	return &d, nil
}

func (m *MongoRepo) List() ([]*document.Document, error) {
	cur, err := m.col.Find(context.Background(), bson.M{})
	if err != nil {
		return nil, err
	}
	defer cur.Close(context.Background())
	out := []*document.Document{}
	for cur.Next(context.Background()) {
		var d document.Document
		if err := cur.Decode(&d); err != nil {
			return nil, err
		}
		out = append(out, &d)
	}
	return out, nil
}

func (m *MongoRepo) Update(id string, content string, name *string) error {
	set := bson.M{"content": content, "updatedAt": time.Now()}
	if name != nil {
		set["name"] = *name
	}
	res, err := m.col.UpdateOne(context.Background(), bson.M{"id": id}, bson.M{"$set": set})
	if err != nil {
		return err
	}
	if res.MatchedCount == 0 {
		return ErrNotFound
	}
	return nil
}

func (m *MongoRepo) Delete(id string) error {
	res, err := m.col.DeleteOne(context.Background(), bson.M{"id": id})
	if err != nil {
		return err
	}
	if res.DeletedCount == 0 {
		return ErrNotFound
	}
	return nil
}
