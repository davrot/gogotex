package handler

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/gogotex/gogotex/backend/go-services/internal/document"
	"github.com/gogotex/gogotex/backend/go-services/internal/document/service"
)

func RegisterDocumentRoutes(r *gin.Engine, svc service.Service) {
	r.GET("/api/documents", func(c *gin.Context) {
		list, _ := svc.List()
		out := make([]map[string]interface{}, 0, len(list))
		for _, d := range list {
			out = append(out, map[string]interface{}{"id": d.ID, "name": d.Name, "updatedAt": d.UpdatedAt})
		}
		c.JSON(http.StatusOK, out)
	})

	r.POST("/api/documents", func(c *gin.Context) {
		var req struct{
			Name string `json:"name"`
			Content string `json:"content"`
		}
		if err := c.ShouldBindJSON(&req); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}
		d := &document.Document{Name: req.Name, Content: req.Content}
		id, _ := svc.Create(d)
		c.JSON(http.StatusCreated, gin.H{"id": id, "name": d.Name})
	})

	r.GET("/api/documents/:id", func(c *gin.Context) {
		id := c.Param("id")
		d, err := svc.Get(id)
		if err != nil {
			c.JSON(http.StatusNotFound, gin.H{"error": "not found"})
			return
		}
		c.JSON(http.StatusOK, gin.H{"id": d.ID, "name": d.Name, "content": d.Content, "createdAt": d.CreatedAt, "updatedAt": d.UpdatedAt})
	})

	r.PATCH("/api/documents/:id", func(c *gin.Context) {
		id := c.Param("id")
		var req struct{
			Name *string `json:"name,omitempty"`
			Content string `json:"content"`
		}
		if err := c.ShouldBindJSON(&req); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}
		if err := svc.Update(id, req.Content, req.Name); err != nil {
			c.JSON(http.StatusNotFound, gin.H{"error": "not found"})
			return
		}
		c.JSON(http.StatusOK, gin.H{"id": id})
	})

	r.DELETE("/api/documents/:id", func(c *gin.Context) {
		id := c.Param("id")
		if err := svc.Delete(id); err != nil {
			c.JSON(http.StatusNotFound, gin.H{"error": "not found"})
			return
		}
		c.Status(http.StatusNoContent)
	})
}
