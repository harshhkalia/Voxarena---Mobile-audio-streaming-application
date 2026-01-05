package controllers

import (
	"net/http"
	"strconv"
	"voxarena_server/config"
	"voxarena_server/models"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

func ToggleHideUser(c *gin.Context) {
	db := config.DB

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

	targetUserIDStr := c.Param("id")
	if targetUserIDStr == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "User ID is required"})
		return
	}

	targetUserID, err := strconv.Atoi(targetUserIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid user ID"})
		return
	}

	if userID == uint(targetUserID) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Cannot hide yourself"})
		return
	}

	var targetUser models.User
	if err := db.First(&targetUser, targetUserID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "User not found"})
		return
	}

	var hiddenUser models.HiddenUser
	err = db.Where("user_id = ? AND hidden_user_id = ?", userID, targetUserID).First(&hiddenUser).Error

	if err == gorm.ErrRecordNotFound {
		newHiddenUser := models.HiddenUser{
			UserID:       userID,
			HiddenUserID: uint(targetUserID),
		}

		if err := db.Create(&newHiddenUser).Error; err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to hide user"})
			return
		}

		c.JSON(http.StatusOK, gin.H{
			"message":   "User hidden successfully",
			"is_hidden": true,
		})
	} else if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Database error"})
		return
	} else {
		if err := db.Delete(&hiddenUser).Error; err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to unhide user"})
			return
		}

		c.JSON(http.StatusOK, gin.H{
			"message":   "User unhidden successfully",
			"is_hidden": false,
		})
	}
}

func CheckHiddenStatus(c *gin.Context) {
	db := config.DB

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

	targetUserIDStr := c.Param("id")
	targetUserID, err := strconv.Atoi(targetUserIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid user ID"})
		return
	}

	var hiddenUser models.HiddenUser
	err = db.Where("user_id = ? AND hidden_user_id = ?", userID, targetUserID).First(&hiddenUser).Error

	c.JSON(http.StatusOK, gin.H{
		"is_hidden": err == nil,
	})
}

func GetHiddenUsers(c *gin.Context) {
	db := config.DB

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
	offset := (page - 1) * limit

	var total int64
	db.Model(&models.HiddenUser{}).
		Where("user_id = ?", userID).
		Count(&total)

	var hiddenUsers []models.HiddenUser
	if err := db.
		Preload("HiddenUser").
		Where("user_id = ?", userID).
		Order("created_at DESC").
		Limit(limit).
		Offset(offset).
		Find(&hiddenUsers).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch hidden users"})
		return
	}

	users := make([]map[string]interface{}, len(hiddenUsers))
	for i, hu := range hiddenUsers {
		users[i] = map[string]interface{}{
			"id":          hu.HiddenUser.ID,
			"username":    hu.HiddenUser.Username,
			"full_name":   hu.HiddenUser.FullName,
			"profile_pic": hu.HiddenUser.ProfilePic,
			"hidden_at":   hu.CreatedAt,
		}
	}

	c.JSON(http.StatusOK, gin.H{
		"hidden_users": users,
		"page":         page,
		"limit":        limit,
		"total":        total,
		"has_more":     offset+len(users) < int(total),
	})
}

func GetHiddenUserIDs(db *gorm.DB, userID uint) ([]uint, error) {
	var hiddenUsers []models.HiddenUser
	if err := db.Select("hidden_user_id").
		Where("user_id = ?", userID).
		Find(&hiddenUsers).Error; err != nil {
		return nil, err
	}

	hiddenUserIDs := make([]uint, len(hiddenUsers))
	for i, hu := range hiddenUsers {
		hiddenUserIDs[i] = hu.HiddenUserID
	}

	return hiddenUserIDs, nil
}

func GetUsersWhoHidMe(db *gorm.DB, viewerID uint) ([]uint, error) {
	var hiddenUsers []models.HiddenUser

	if err := db.
		Select("user_id").
		Where("hidden_user_id = ?", viewerID).
		Find(&hiddenUsers).Error; err != nil {
		return nil, err
	}

	blockedBy := make([]uint, len(hiddenUsers))
	for i, hu := range hiddenUsers {
		blockedBy[i] = hu.UserID
	}

	return blockedBy, nil
}
