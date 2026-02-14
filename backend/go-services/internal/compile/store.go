package compile

import (
	"context"
	"time"
	"fmt"

	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"

	"github.com/gogotex/gogotex/backend/go-services/internal/database"
)

// PersistedCompile is the Mongo representation for a compile job metadata.
type PersistedCompile struct {
	JobID      string                 `bson:"jobId" json:"jobId"`
	DocID      string                 `bson:"docId" json:"docId"`
	Status     string                 `bson:"status" json:"status"`
	CreatedAt  time.Time              `bson:"createdAt" json:"createdAt"`
	UpdatedAt  time.Time              `bson:"updatedAt" json:"updatedAt"`
	PDFKey     string                 `bson:"pdfKey,omitempty" json:"pdfKey,omitempty"`
	SynctexKey string                 `bson:"synctexKey,omitempty" json:"synctexKey,omitempty"`
	SynctexMap map[string][]map[string]any `bson:"synctexMap,omitempty" json:"synctexMap,omitempty"`
}

// Save persists (upsert) compile metadata into the provided Mongo URI/db.
// If mongoURI is empty the function is a no-op.
func Save(ctx context.Context, mongoURI, databaseName string, pc *PersistedCompile) error {
	if mongoURI == "" {
		return nil
	}
	client, err := database.ConnectMongo(ctx, mongoURI, 5*time.Second)
	if err != nil {
		return fmt.Errorf("connect mongo: %w", err)
	}
	defer client.Disconnect(ctx)

	col := client.Database(databaseName).Collection("compile_jobs")
	filter := bson.M{"jobId": pc.JobID}
	opts := options.Update().SetUpsert(true)
	rec := bson.M{"$set": pc}
	if _, err := col.UpdateOne(ctx, filter, rec, opts); err != nil {
		return fmt.Errorf("save compile job: %w", err)
	}
	return nil
}

// Load fetches a persisted compile job by jobId. Returns nil when not found.
func Load(ctx context.Context, mongoURI, databaseName, jobID string) (*PersistedCompile, error) {
	if mongoURI == "" {
		return nil, nil
	}
	client, err := database.ConnectMongo(ctx, mongoURI, 5*time.Second)
	if err != nil {
		return nil, fmt.Errorf("connect mongo: %w", err)
	}
	defer client.Disconnect(ctx)
	col := client.Database(databaseName).Collection("compile_jobs")
	var pc PersistedCompile
	if err := col.FindOne(ctx, bson.M{"jobId": jobID}).Decode(&pc); err != nil {
		if err == mongo.ErrNoDocuments {
			return nil, nil
		}
		return nil, err
	}
	return &pc, nil
}
