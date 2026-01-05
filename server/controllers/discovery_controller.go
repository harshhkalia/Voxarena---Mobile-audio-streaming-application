package controllers

import (
	"net/http"
	"strconv"
	"voxarena_server/config"
	"voxarena_server/models"

	"github.com/gin-gonic/gin"
)

func GetDiscoveryFeed(c *gin.Context) {
	userIDValue, _ := c.Get("user_id")

	var viewerID uint
	switch v := userIDValue.(type) {
	case uint:
		viewerID = v
	case int:
		viewerID = uint(v)
	case int64:
		viewerID = uint(v)
	case float64:
		viewerID = uint(v)
	}

	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "20"))
	topic := c.Query("topic")

	if page < 1 {
		page = 1
	}
	if limit <= 0 || limit > 100 {
		limit = 20
	}

	offset := (page - 1) * limit

	db := config.DB
	var rooms []models.Room

	var hiddenByUserIDs []uint
	if viewerID > 0 {
		var err error
		hiddenByUserIDs, err = GetUsersWhoHidMe(db, viewerID)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{
				"success": false,
				"error":   "Failed to load discovery feed",
			})
			return
		}
	}

	query := db.
		Preload("Host").
		Where("is_private = ?", false).
		Where("is_live = ?", false).
		Where("is_hidden = ?", false)

	if len(hiddenByUserIDs) > 0 {
		query = query.Where("host_id NOT IN ?", hiddenByUserIDs)
	}

	if topic != "" && topic != "All" {
		query = query.Where("topic = ?", topic)
	}

	if err := query.
		Order("total_listens DESC, created_at DESC").
		Limit(limit).
		Offset(offset).
		Find(&rooms).Error; err != nil {

		c.JSON(http.StatusInternalServerError, gin.H{
			"success": false,
			"error":   "Failed to load discovery feed",
		})
		return
	}

	hasMore := len(rooms) == limit

	c.JSON(http.StatusOK, gin.H{
		"success":  true,
		"rooms":    rooms,
		"page":     page,
		"limit":    limit,
		"has_more": hasMore,
	})
}

func GetTopics(c *gin.Context) {
	topics := []string{
		"All",
		"Technology",
		"Business",
		"Gaming",
		"Music",
		"Education",
		"Health",
		"Entertainment",
		"Sports",
		"News",
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"topics":  topics,
	})
}
