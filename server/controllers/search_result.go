package controllers

import (
	"net/http"
	"strconv"
	"strings"
	"time"
	"voxarena_server/config"
	"voxarena_server/models"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

type SearchResult struct {
	Users []UserSearchResult `json:"users"`
	Rooms []RoomSearchResult `json:"rooms"`
}

type UserSearchResult struct {
	ID             uint   `json:"id"`
	Username       string `json:"username"`
	FullName       string `json:"full_name"`
	ProfilePic     string `json:"profile_pic"`
	Bio            string `json:"bio"`
	IsVerified     bool   `json:"is_verified"`
	FollowersCount int    `json:"followers_count"`
	TotalAudios    int    `json:"total_audios"`
	TotalListeners int    `json:"total_listeners"`
	IsFollowing    bool   `json:"is_following"`
}

type RoomSearchResult struct {
	ID                 uint   `json:"id"`
	Title              string `json:"title"`
	Description        string `json:"description"`
	Topic              string `json:"topic"`
	AudioURL           string `json:"audio_url"`
	ThumbnailURL       string `json:"thumbnail_url"`
	Duration           int    `json:"duration"`
	HostID             uint   `json:"host_id"`
	HostName           string `json:"host_name"`
	HostAvatar         string `json:"host_avatar"`
	HostFollowersCount int    `json:"host_followers_count"`
	IsLive             bool   `json:"is_live"`
	IsPrivate          bool   `json:"is_private"`
	ListenerCount      int    `json:"listener_count"`
	TotalListens       int    `json:"total_listens"`
	LikesCount         int    `json:"likes_count"`
	CreatedAt          string `json:"created_at"`
}

func GlobalSearch(c *gin.Context) {
	db := config.DB

	query := strings.TrimSpace(c.Query("q"))
	if query == "" {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "Search query is required",
			"message": "Please provide a search query using the 'q' parameter",
		})
		return
	}

	if len(query) < 2 {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "Query too short",
			"message": "Search query must be at least 2 characters long",
		})
		return
	}

	if len(query) > 100 {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "Query too long",
			"message": "Search query must be less than 100 characters",
		})
		return
	}

	searchType := c.Query("type")
	limit := 20
	if limitParam := c.Query("limit"); limitParam != "" {
		if l, err := strconv.Atoi(limitParam); err == nil && l > 0 && l <= 100 {
			limit = l
		}
	}

	var currentUserID uint
	if userIDValue, exists := c.Get("user_id"); exists {
		switch v := userIDValue.(type) {
		case uint:
			currentUserID = v
		case int:
			currentUserID = uint(v)
		case int64:
			currentUserID = uint(v)
		case float64:
			currentUserID = uint(v)
		}
	}

	result := SearchResult{
		Users: []UserSearchResult{},
		Rooms: []RoomSearchResult{},
	}

	if searchType == "" || searchType == "all" || searchType == "users" {
		users, err := searchUsers(db, query, currentUserID, limit)
		if err != nil {
			println("Error searching users:", err.Error())
		} else {
			result.Users = users
		}
	}

	if searchType == "" || searchType == "all" || searchType == "rooms" {
		rooms, err := searchRooms(db, query, currentUserID, limit)
		if err != nil {
			println("Error searching rooms:", err.Error())
		} else {
			result.Rooms = rooms
		}
	}

	c.JSON(http.StatusOK, result)
}

func searchUsers(
	db *gorm.DB,
	query string,
	currentUserID uint,
	limit int,
) ([]UserSearchResult, error) {

	var users []models.User
	searchPattern := "%" + strings.ToLower(query) + "%"

	q := db.
		Where(
			"LOWER(username) LIKE ? OR LOWER(full_name) LIKE ?",
			searchPattern,
			searchPattern,
		).
		Where("is_active = ?", true)

	if currentUserID > 0 {
		q = q.Where(`
			id NOT IN (
				SELECT user_id
				FROM hidden_users
				WHERE hidden_user_id = ?
			)
		`, currentUserID)
	}

	err := q.
		Order("followers_count DESC, created_at DESC").
		Limit(limit).
		Find(&users).Error

	if err != nil {
		return nil, err
	}

	results := make([]UserSearchResult, 0, len(users))

	for _, user := range users {

		var totalAudios int64
		db.Model(&models.Room{}).
			Where("host_id = ? AND is_private = ?", user.ID, false).
			Count(&totalAudios)

		var totalListeners int64
		db.Model(&models.Room{}).
			Where("host_id = ? AND is_private = ?", user.ID, false).
			Select("COALESCE(SUM(total_listens), 0)").
			Scan(&totalListeners)

		isFollowing := false
		if currentUserID > 0 && currentUserID != user.ID {
			var follow models.Follow
			err := db.
				Where(
					"follower_id = ? AND following_id = ?",
					currentUserID,
					user.ID,
				).
				First(&follow).Error
			isFollowing = err == nil
		}

		results = append(results, UserSearchResult{
			ID:             user.ID,
			Username:       user.Username,
			FullName:       user.FullName,
			ProfilePic:     user.ProfilePic,
			Bio:            user.Bio,
			IsVerified:     user.IsVerified,
			FollowersCount: user.FollowersCount,
			TotalAudios:    int(totalAudios),
			TotalListeners: int(totalListeners),
			IsFollowing:    isFollowing,
		})
	}

	return results, nil
}

func searchRooms(
	db *gorm.DB,
	query string,
	currentUserID uint,
	limit int,
) ([]RoomSearchResult, error) {

	var rooms []models.Room
	searchPattern := "%" + strings.ToLower(query) + "%"

	q := db.
		Preload("Host").
		Where("is_private = ?", false).
		Where("is_hidden = ?", false).
		Where(
			"LOWER(title) LIKE ? OR LOWER(description) LIKE ? OR LOWER(topic) LIKE ?",
			searchPattern,
			searchPattern,
			searchPattern,
		)

	if currentUserID > 0 {
		q = q.Where(`
			host_id NOT IN (
				SELECT user_id
				FROM hidden_users
				WHERE hidden_user_id = ?
			)
		`, currentUserID)
	}

	err := q.
		Order("total_listens DESC, created_at DESC").
		Limit(limit).
		Find(&rooms).Error

	if err != nil {
		return nil, err
	}

	results := make([]RoomSearchResult, 0, len(rooms))

	for _, room := range rooms {
		results = append(results, RoomSearchResult{
			ID:                 room.ID,
			Title:              room.Title,
			Description:        room.Description,
			Topic:              room.Topic,
			AudioURL:           room.AudioURL,
			ThumbnailURL:       room.ThumbnailURL,
			Duration:           room.Duration,
			HostID:             room.HostID,
			HostName:           room.Host.FullName,
			HostAvatar:         room.Host.ProfilePic,
			HostFollowersCount: room.Host.FollowersCount,
			IsLive:             room.IsLive,
			IsPrivate:          room.IsPrivate,
			ListenerCount:      room.ListenerCount,
			TotalListens:       room.TotalListens,
			LikesCount:         room.LikesCount,
			CreatedAt:          room.CreatedAt.Format(time.RFC3339),
		})
	}

	return results, nil
}
