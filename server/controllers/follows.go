package controllers

import (
	"log"
	"net/http"
	"strconv"
	"voxarena_server/config"
	"voxarena_server/models"
	"voxarena_server/websocket"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

func ToggleFollow(c *gin.Context) {
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
		c.JSON(http.StatusBadRequest, gin.H{"error": "Cannot follow yourself"})
		return
	}

	var targetUser models.User
	if err := db.First(&targetUser, targetUserID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "User not found"})
		return
	}

	var follower models.User
	db.First(&follower, userID)

	var follow models.Follow
	err = db.Where("follower_id = ? AND following_id = ?", userID, targetUserID).First(&follow).Error

	if err == gorm.ErrRecordNotFound {
		newFollow := models.Follow{
			FollowerID:  userID,
			FollowingID: uint(targetUserID),
		}

		if err := db.Create(&newFollow).Error; err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to follow user"})
			return
		}

		db.Model(&models.User{}).Where("id = ?", userID).Update("following_count", gorm.Expr("following_count + ?", 1))
		db.Model(&models.User{}).Where("id = ?", targetUserID).Update("followers_count", gorm.Expr("followers_count + ?", 1))

		notification := models.Notification{
			UserID:        uint(targetUserID),
			ActorID:       userID,
			Type:          models.NotificationTypeFollow,
			Title:         "@" + follower.Username + " started following you",
			Message:       follower.FullName,
			ReferenceID:   &userID,
			ReferenceType: "user",
			ImageURL:      follower.ProfilePic,
			ActionURL:     "/profile/" + strconv.Itoa(int(userID)),
			IsRead:        false,
		}

		if err := db.Create(&notification).Error; err == nil {
			if websocket.GlobalHub != nil {
				payload := map[string]interface{}{
					"type": "notification",
					"data": map[string]interface{}{
						"id":             notification.ID,
						"type":           notification.Type,
						"title":          notification.Title,
						"message":        notification.Message,
						"image_url":      notification.ImageURL,
						"action_url":     notification.ActionURL,
						"reference_id":   notification.ReferenceID,
						"reference_type": notification.ReferenceType,
						"is_read":        notification.IsRead,
						"created_at":     notification.CreatedAt,
						"actor": map[string]interface{}{
							"id":          follower.ID,
							"full_name":   follower.FullName,
							"username":    follower.Username,
							"profile_pic": follower.ProfilePic,
						},
					},
				}
				websocket.GlobalHub.SendToUsers([]uint{uint(targetUserID)}, payload)
				log.Printf("✓ Sent follow notification to user %d", targetUserID)
			}
		}

		c.JSON(http.StatusOK, gin.H{
			"message":      "User followed successfully",
			"is_following": true,
		})
	} else if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Database error"})
		return
	} else {
		// UNFOLLOW
		if err := db.Delete(&follow).Error; err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to unfollow user"})
			return
		}

		db.Model(&models.User{}).Where("id = ? AND following_count > 0", userID).Update("following_count", gorm.Expr("following_count - ?", 1))
		db.Model(&models.User{}).Where("id = ? AND followers_count > 0", targetUserID).Update("followers_count", gorm.Expr("followers_count - ?", 1))

		db.Where("user_id = ? AND actor_id = ? AND type = ?",
			targetUserID, userID, models.NotificationTypeFollow).
			Delete(&models.Notification{})

		if websocket.GlobalHub != nil {
			payload := map[string]interface{}{
				"type": "remove_follow_notification",
				"data": map[string]interface{}{
					"actor_id": userID,
				},
			}
			websocket.GlobalHub.SendToUsers([]uint{uint(targetUserID)}, payload)
			log.Printf("✓ Sent remove_follow_notification to user %d", targetUserID)
		}

		c.JSON(http.StatusOK, gin.H{
			"message":      "User unfollowed successfully",
			"is_following": false,
		})
	}
}

func CheckFollowStatus(c *gin.Context) {
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

	var follow models.Follow
	err = db.Where("follower_id = ? AND following_id = ?", userID, targetUserID).First(&follow).Error

	c.JSON(http.StatusOK, gin.H{
		"is_following": err == nil,
	})
}

func GetFollowers(c *gin.Context) {
	db := config.DB

	targetUserIDStr := c.Param("id")
	targetUserID, err := strconv.Atoi(targetUserIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid user ID"})
		return
	}

	currentUserIDValue, _ := c.Get("user_id")
	var currentUserID uint
	switch v := currentUserIDValue.(type) {
	case uint:
		currentUserID = v
	case int:
		currentUserID = uint(v)
	case int64:
		currentUserID = uint(v)
	case float64:
		currentUserID = uint(v)
	}

	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "20"))
	offset := (page - 1) * limit

	if currentUserID > 0 {
		var hidden models.HiddenUser
		err := db.Where(
			"user_id = ? AND hidden_user_id = ?",
			targetUserID,
			currentUserID,
		).First(&hidden).Error

		if err == nil {
			c.JSON(http.StatusForbidden, gin.H{
				"error":         "This content is not available",
				"is_restricted": true,
			})
			return
		}
	}

	var hiddenByUserIDs []uint
	if currentUserID > 0 {
		hiddenByUserIDs, err = GetUsersWhoHidMe(db, currentUserID)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{
				"error": "Failed to fetch followers",
			})
			return
		}
	}

	var total int64
	db.Model(&models.Follow{}).
		Where("following_id = ?", targetUserID).
		Count(&total)

	var followers []models.Follow
	followersQuery := db.
		Preload("Follower").
		Where("following_id = ?", targetUserID)

	if len(hiddenByUserIDs) > 0 {
		followersQuery = followersQuery.Where("follower_id NOT IN ?", hiddenByUserIDs)
	}

	if err := followersQuery.
		Order("created_at DESC").
		Limit(limit).
		Offset(offset).
		Find(&followers).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error": "Failed to fetch followers",
		})
		return
	}

	users := make([]map[string]interface{}, len(followers))
	for i, follow := range followers {
		users[i] = map[string]interface{}{
			"id":              follow.Follower.ID,
			"username":        follow.Follower.Username,
			"full_name":       follow.Follower.FullName,
			"profile_pic":     follow.Follower.ProfilePic,
			"followers_count": follow.Follower.FollowersCount,
			"followed_at":     follow.CreatedAt,
		}
	}

	c.JSON(http.StatusOK, gin.H{
		"followers": users,
		"page":      page,
		"limit":     limit,
		"total":     total,
		"has_more":  offset+len(users) < int(total),
	})
}

func GetFollowing(c *gin.Context) {
	db := config.DB

	targetUserID, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid user ID"})
		return
	}

	currentUserIDValue, _ := c.Get("user_id")
	var currentUserID uint
	switch v := currentUserIDValue.(type) {
	case uint:
		currentUserID = v
	case int:
		currentUserID = uint(v)
	case int64:
		currentUserID = uint(v)
	case float64:
		currentUserID = uint(v)
	}

	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "20"))
	offset := (page - 1) * limit

	if currentUserID > 0 {
		var hidden models.HiddenUser
		err := db.Where(
			"user_id = ? AND hidden_user_id = ?",
			targetUserID,
			currentUserID,
		).First(&hidden).Error

		if err == nil {
			c.JSON(http.StatusForbidden, gin.H{
				"error":         "This content is not available",
				"is_restricted": true,
			})
			return
		}
	}

	var hiddenByUserIDs []uint
	if currentUserID > 0 {
		hiddenByUserIDs, err = GetUsersWhoHidMe(db, currentUserID)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{
				"error": "Failed to fetch following",
			})
			return
		}
	}

	var total int64
	db.Model(&models.Follow{}).
		Where("follower_id = ?", targetUserID).
		Count(&total)

	var following []models.Follow
	followingQuery := db.
		Preload("Following").
		Where("follower_id = ?", targetUserID)

	if len(hiddenByUserIDs) > 0 {
		followingQuery = followingQuery.Where("following_id NOT IN ?", hiddenByUserIDs)
	}

	if err := followingQuery.
		Order("created_at DESC").
		Limit(limit).
		Offset(offset).
		Find(&following).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error": "Failed to fetch following",
		})
		return
	}

	users := make([]map[string]interface{}, len(following))
	for i, follow := range following {
		users[i] = map[string]interface{}{
			"id":              follow.Following.ID,
			"username":        follow.Following.Username,
			"full_name":       follow.Following.FullName,
			"profile_pic":     follow.Following.ProfilePic,
			"followers_count": follow.Following.FollowersCount,
			"followed_at":     follow.CreatedAt,
		}
	}

	c.JSON(http.StatusOK, gin.H{
		"following": users,
		"page":      page,
		"limit":     limit,
		"total":     total,
		"has_more":  offset+len(users) < int(total),
	})
}

func GetFollowingRooms(c *gin.Context) {
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

	var follows []models.Follow
	if err := db.
		Where("follower_id = ?", userID).
		Find(&follows).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error": "Failed to fetch following",
		})
		return
	}

	if len(follows) == 0 {
		c.JSON(http.StatusOK, gin.H{
			"rooms":    []models.Room{},
			"total":    0,
			"has_more": false,
		})
		return
	}

	followingIDs := make([]uint, 0, len(follows))
	for _, follow := range follows {
		followingIDs = append(followingIDs, follow.FollowingID)
	}

	blockedBy, err := GetUsersWhoHidMe(db, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error": "Failed to fetch hidden relations",
		})
		return
	}

	if len(blockedBy) > 0 {
		filtered := make([]uint, 0, len(followingIDs))
		blockedSet := make(map[uint]struct{}, len(blockedBy))
		for _, id := range blockedBy {
			blockedSet[id] = struct{}{}
		}

		for _, id := range followingIDs {
			if _, blocked := blockedSet[id]; !blocked {
				filtered = append(filtered, id)
			}
		}

		followingIDs = filtered
	}

	if len(followingIDs) == 0 {
		c.JSON(http.StatusOK, gin.H{
			"rooms":    []models.Room{},
			"total":    0,
			"has_more": false,
		})
		return
	}

	query := db.Model(&models.Room{}).
		Where("host_id IN ?", followingIDs).
		Where("is_private = ? OR host_id = ?", false, userID).
		Where("is_hidden = ?", false)

	var total int64
	query.Count(&total)

	var rooms []models.Room
	if err := query.
		Preload("Host").
		Order("created_at DESC").
		Limit(limit).
		Offset(offset).
		Find(&rooms).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error": "Failed to fetch rooms",
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"rooms":    rooms,
		"page":     page,
		"limit":    limit,
		"total":    total,
		"has_more": offset+len(rooms) < int(total),
	})
}

func RemoveFollower(c *gin.Context) {
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

	targetUserID, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid user ID"})
		return
	}

	var follow models.Follow
	err = db.Where(
		"follower_id = ? AND following_id = ?",
		targetUserID,
		userID,
	).First(&follow).Error

	if err == gorm.ErrRecordNotFound {
		c.JSON(http.StatusNotFound, gin.H{"error": "Follower not found"})
		return
	} else if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Database error"})
		return
	}

	if err := db.Delete(&follow).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to remove follower"})
		return
	}

	db.Model(&models.User{}).
		Where("id = ? AND followers_count > 0", userID).
		Update("followers_count", gorm.Expr("followers_count - 1"))

	db.Model(&models.User{}).
		Where("id = ? AND following_count > 0", targetUserID).
		Update("following_count", gorm.Expr("following_count - 1"))

	var stillFollowing models.Follow
	isFollowing := db.Where(
		"follower_id = ? AND following_id = ?",
		userID,
		targetUserID,
	).First(&stillFollowing).Error == nil

	c.JSON(http.StatusOK, gin.H{
		"success":      true,
		"message":      "Follower removed",
		"is_following": isFollowing,
	})
}
