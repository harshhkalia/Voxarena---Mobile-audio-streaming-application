package controllers

import (
	"fmt"
	"net/http"
	"voxarena_server/config"
	"voxarena_server/models"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

func ToggleLike(c *gin.Context) {
	userID, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}

	roomIDStr := c.Param("id")

	var roomID uint
	if _, err := fmt.Sscanf(roomIDStr, "%d", &roomID); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid room ID"})
		return
	}

	var room models.Room
	if err := config.DB.First(&room, roomID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Room not found"})
		return
	}

	var existingLike models.RoomLike
	err := config.DB.Where("user_id = ? AND room_id = ?", userID, roomID).First(&existingLike).Error

	if err == nil {
		if err := config.DB.Delete(&existingLike).Error; err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to unlike"})
			return
		}

		config.DB.Model(&room).Update("likes_count", gorm.Expr("GREATEST(likes_count - 1, 0)"))
		config.DB.First(&room, roomID)

		c.JSON(http.StatusOK, gin.H{
			"success":     true,
			"action":      "unliked",
			"is_liked":    false,
			"likes_count": room.LikesCount,
		})
		return
	}

	newLike := models.RoomLike{
		UserID: userID.(uint),
		RoomID: roomID, 
	}

	if err := config.DB.Create(&newLike).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to like"})
		return
	}

	config.DB.Model(&room).Update("likes_count", gorm.Expr("likes_count + 1"))
	config.DB.First(&room, roomID)

	c.JSON(http.StatusOK, gin.H{
		"success":     true,
		"action":      "liked",
		"is_liked":    true,
		"likes_count": room.LikesCount,
	})
}

func CheckIfLiked(c *gin.Context) {
	userID, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}

	roomID := c.Param("id")

	var like models.RoomLike
	err := config.DB.Where("user_id = ? AND room_id = ?", userID, roomID).First(&like).Error

	isLiked := err == nil

	var room models.Room
	if err := config.DB.First(&room, roomID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Room not found"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success":     true,
		"is_liked":    isLiked,
		"likes_count": room.LikesCount,
	})
}