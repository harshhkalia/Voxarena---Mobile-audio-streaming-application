package controllers

import (
	"net/http"
	"voxarena_server/config"

	"github.com/gin-gonic/gin"
)

func GetStatus(c *gin.Context) {
	sqlDB, err := config.DB.DB()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"status":  "error",
			"message": "Database connection failed",
			"error":   err.Error(),
		})
		return
	}

	if err := sqlDB.Ping(); err != nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{
			"status":  "error",
			"message": "Database ping failed",
			"error":   err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"status":   "ok",
		"message":  "VoxArena Server is running",
		"database": "connected",
	})
}