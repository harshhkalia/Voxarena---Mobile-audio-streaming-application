package controllers

import (
	"net/http"
	"strconv"

	"voxarena_server/config"
	"voxarena_server/models"

	"github.com/gin-gonic/gin"
)

func GetNotifications(c *gin.Context) {
	userIDValue, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}

	var userID uint
	switch v := userIDValue.(type) {
	case uint:
		userID = v
	case int:
		userID = uint(v)
	case int64:
		userID = uint(v)
	case float64:
		userID = uint(v)
	default:
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid user ID type"})
		return
	}

	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "20"))
	if page < 1 {
		page = 1
	}
	if limit < 1 {
		limit = 20
	}
	offset := (page - 1) * limit

	blockedBy, err := GetUsersWhoHidMe(config.DB, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch hidden relations"})
		return
	}

	var notifications []models.Notification
	var total int64

	existsFilter := `
		(type NOT IN ('comment', 'comment_like', 'follow', 'community_post') AND (
			(reference_type != 'room' OR reference_type IS NULL)
			OR (reference_type = 'room' AND reference_id IN (SELECT id FROM rooms WHERE deleted_at IS NULL))
		))
		OR (type = 'comment' AND reference_type = 'room' AND EXISTS (
			SELECT 1 FROM comments 
			WHERE comments.room_id = notifications.reference_id 
			AND comments.user_id = notifications.actor_id 
			AND comments.content = notifications.message 
			AND comments.deleted_at IS NULL
		))
		OR (type = 'comment_like' AND reference_type = 'room' AND EXISTS (
			SELECT 1 FROM comment_likes cl
			INNER JOIN comments c ON c.id = cl.comment_id
			WHERE c.content = notifications.message 
			AND cl.user_id = notifications.actor_id
			AND c.deleted_at IS NULL
		))
		OR (type = 'follow' AND reference_type = 'user' AND EXISTS (
			SELECT 1 FROM follows
			WHERE follows.follower_id = notifications.actor_id
			AND follows.following_id = notifications.user_id
		))
		OR (type = 'community_post' AND reference_type = 'post' AND EXISTS (
			SELECT 1 FROM community_posts
			WHERE community_posts.id = notifications.reference_id
			AND community_posts.deleted_at IS NULL
		))
	`

	baseQuery := config.DB.Model(&models.Notification{}).
		Where("user_id = ?", userID)

	if len(blockedBy) > 0 {
		baseQuery = baseQuery.Where("actor_id NOT IN ?", blockedBy)
	}

	baseQuery = baseQuery.Where(existsFilter)
	baseQuery.Count(&total)

	fetchQuery := config.DB.
		Where("user_id = ?", userID)

	if len(blockedBy) > 0 {
		fetchQuery = fetchQuery.Where("actor_id NOT IN ?", blockedBy)
	}

	fetchQuery = fetchQuery.Where(existsFilter)

	if err := fetchQuery.
		Preload("Actor").
		Order("created_at DESC").
		Limit(limit).
		Offset(offset).
		Find(&notifications).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch notifications"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success":       true,
		"notifications": notifications,
		"page":          page,
		"limit":         limit,
		"total":         total,
		"has_more":      offset+len(notifications) < int(total),
	})
}

func GetUnreadCount(c *gin.Context) {
	userIDValue, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}

	var userID uint
	switch v := userIDValue.(type) {
	case uint:
		userID = v
	case int:
		userID = uint(v)
	case int64:
		userID = uint(v)
	case float64:
		userID = uint(v)
	default:
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid user ID type"})
		return
	}

	blockedBy, err := GetUsersWhoHidMe(config.DB, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch hidden relations"})
		return
	}

	var count int64
	query := config.DB.Model(&models.Notification{}).
		Where("user_id = ? AND is_read = ?", userID, false)

	if len(blockedBy) > 0 {
		query = query.Where("actor_id NOT IN ?", blockedBy)
	}

	if err := query.Count(&count).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to get count"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success":      true,
		"unread_count": count,
	})
}

func MarkAllNotificationsAsRead(c *gin.Context) {
	userID, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}

	var userIDUint uint
	switch v := userID.(type) {
	case uint:
		userIDUint = v
	case int:
		userIDUint = uint(v)
	case int64:
		userIDUint = uint(v)
	case float64:
		userIDUint = uint(v)
	}

	if err := models.MarkAllAsRead(config.DB, userIDUint); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to mark as read"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"message": "All marked as read",
	})
}

func DeleteNotification(c *gin.Context) {
	userIDValue, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}

	var userID uint
	switch v := userIDValue.(type) {
	case uint:
		userID = v
	case int:
		userID = uint(v)
	case int64:
		userID = uint(v)
	case float64:
		userID = uint(v)
	default:
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid user ID type"})
		return
	}

	notificationID, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid notification ID"})
		return
	}

	var notification models.Notification
	if err := config.DB.First(&notification, notificationID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Notification not found"})
		return
	}

	if notification.UserID != userID {
		c.JSON(http.StatusForbidden, gin.H{"error": "You can only delete your own notifications"})
		return
	}

	if err := config.DB.Delete(&notification).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to delete notification"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"message": "Notification deleted",
	})
}