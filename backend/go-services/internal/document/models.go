package document

import "time"

// Document is the minimal persistent document model for the go-document service.
// This mirrors the Phase‑03 prototype model but is designed for future Mongo
// persistence (Phase‑05).
type Document struct {
	ID        string    `json:"id" bson:"_id,omitempty"`
	Name      string    `json:"name" bson:"name"`
	Content   string    `json:"content,omitempty" bson:"content,omitempty"`
	CreatedAt time.Time `json:"createdAt" bson:"createdAt"`
	UpdatedAt time.Time `json:"updatedAt" bson:"updatedAt"`
}
