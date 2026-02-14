package compile

import (
	"context"
	"testing"
	"time"
)

func TestSaveLoadNoopWhenMongoURIEmpty(t *testing.T) {
	pc := &PersistedCompile{JobID: "j1", DocID: "d1", Status: "ready", CreatedAt: time.Now(), UpdatedAt: time.Now()}
	// should be noop and not error when mongoURI empty
	if err := Save(context.Background(), "", "", pc); err != nil {
		t.Fatalf("expected no error for empty mongoURI, got %v", err)
	}
	// Load should return nil, nil when mongoURI empty
	if got, err := Load(context.Background(), "", "", "j1"); err != nil || got != nil {
		t.Fatalf("expected nil result for empty mongoURI, got %v err=%v", got, err)
	}
}
