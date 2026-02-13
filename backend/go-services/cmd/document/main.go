package main

import (
	"context"
	"log"
	"os"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/gogotex/gogotex/backend/go-services/internal/database"
	"github.com/gogotex/gogotex/backend/go-services/internal/document/handler"
	"github.com/gogotex/gogotex/backend/go-services/internal/document/service"
)

func main() {
	port := os.Getenv("DOC_SERVICE_PORT")
	if port == "" {
		port = "5010"
	}

	r := gin.New()
	r.Use(gin.Recovery())

	// Prefer Mongo-backed service when MONGODB_URI is provided (Phase‑05).
	var svc service.Service
	mongoURI := os.Getenv("MONGODB_URI")
	if mongoURI != "" {
		// attempt a connection with a short timeout; fall back to memory on failure
		timeout := 10
		if v := os.Getenv("MONGODB_TIMEOUT"); v != "" {
			// ignore parse errors and use default
		}
		client, err := database.ConnectMongo(context.Background(), mongoURI, 10*time.Second)
		if err != nil {
			log.Printf("warning: cannot connect to MongoDB (%v) — using memory-backed repo", err)
			svc = service.NewMemoryService()
		} else {
			col := client.Database(os.Getenv("MONGODB_DATABASE")).Collection("documents")
			svc = service.NewMongoService(col)
		}
	} else {
		svc = service.NewMemoryService()
	}

	handler.RegisterDocumentRoutes(r, svc)

	log.Printf("go-document service listening on :%s", port)
	if err := r.Run(":" + port); err != nil {
		log.Fatal(err)
	}
}
