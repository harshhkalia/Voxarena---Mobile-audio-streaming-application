package controllers

import (
	"fmt"
	"io"
	"log"
	"net/http"
	"strconv"
	"strings"

	"voxarena_server/config"
	"voxarena_server/models"
	"voxarena_server/services"
	"voxarena_server/utils"
	"voxarena_server/websocket"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

type updatePrivacyBody struct {
	IsPrivate *bool `json:"is_private"`
}

func CreateRoom(c *gin.Context) {
	userID, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}

	title := c.PostForm("title")
	description := c.PostForm("description")
	topic := c.PostForm("topic")
	durationStr := c.PostForm("duration")
	isPrivateStr := c.PostForm("is_private")

	if title == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Title is required"})
		return
	}
	if topic == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Topic is required"})
		return
	}

	audioFile, audioHeader, err := c.Request.FormFile("audio_file")
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Audio file is required"})
		return
	}
	defer audioFile.Close()

	if audioHeader.Size > 50*1024*1024 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Audio file must be less than 50MB"})
		return
	}

	contentType := audioHeader.Header.Get("Content-Type")
	validAudioTypes := []string{"audio/mpeg", "audio/mp3", "audio/wav", "audio/m4a", "audio/x-m4a"}
	isValidType := false
	for _, validType := range validAudioTypes {
		if strings.Contains(contentType, validType) ||
			strings.Contains(strings.ToLower(audioHeader.Filename), ".mp3") ||
			strings.Contains(strings.ToLower(audioHeader.Filename), ".wav") ||
			strings.Contains(strings.ToLower(audioHeader.Filename), ".m4a") {
			isValidType = true
			break
		}
	}
	if !isValidType {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid audio format. Supported: MP3, WAV, M4A"})
		return
	}

	audioData, err := io.ReadAll(audioFile)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to read audio file"})
		return
	}

	audioURL, err := utils.UploadAudioToCloudinary(audioData, fmt.Sprint(userID))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": fmt.Sprintf("Failed to upload audio: %v", err)})
		return
	}

	duration := 0
	if durationStr != "" {
		fmt.Sscanf(durationStr, "%d", &duration)
	}

	isPrivate := false
	if isPrivateStr == "true" || isPrivateStr == "1" {
		isPrivate = true
	}

	var thumbnailURL string
	thumbnailFile, thumbnailHeader, err := c.Request.FormFile("thumbnail")
	if err == nil {
		defer thumbnailFile.Close()

		if thumbnailHeader.Size <= 5*1024*1024 {
			thumbnailData, err := io.ReadAll(thumbnailFile)
			if err == nil {
				thumbnailURL, _ = utils.UploadThumbnailToCloudinary(thumbnailData, fmt.Sprint(userID))
			}
		}
	}

	var user models.User
	if err := config.DB.First(&user, userID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "User not found"})
		return
	}

	room := models.Room{
		Title:         strings.TrimSpace(title),
		Description:   strings.TrimSpace(description),
		Topic:         topic,
		AudioURL:      audioURL,
		ThumbnailURL:  thumbnailURL,
		Duration:      duration,
		HostID:        user.ID,
		IsLive:        false,
		IsPrivate:     isPrivate,
		ListenerCount: 0,
	}

	if err := config.DB.Create(&room).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to create room"})
		return
	}

	config.DB.Preload("Host").First(&room, room.ID)

	notificationService := services.NewNotificationService(config.DB)
go func() {
	if err := notificationService.NotifyNewRoom(&room); err != nil {
		log.Printf("⚠️ Failed to send notifications: %v", err)
	}
}()

	c.JSON(http.StatusCreated, gin.H{
		"success": true,
		"message": "Room created successfully",
		"room": gin.H{
			"id":             room.ID,
			"title":          room.Title,
			"description":    room.Description,
			"topic":          room.Topic,
			"audio_url":      room.AudioURL,
			"thumbnail_url":  room.ThumbnailURL,
			"duration":       room.Duration,
			"is_private":     room.IsPrivate,
			"host_name":      room.Host.FullName,
			"host_avatar":    room.Host.ProfilePic,
			"listener_count": room.ListenerCount,
			"is_live":        room.IsLive,
			"created_at":     room.CreatedAt,
		},
	})
}

func GetRooms(c *gin.Context) {
	db := config.DB
	var rooms []models.Room

	userIDValue, exists := c.Get("user_id")
	var viewerID uint

	if exists {
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
	}

	var blockedBy []uint
	if viewerID > 0 {
		var err error
		blockedBy, err = GetUsersWhoHidMe(db, viewerID)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{
				"error": "Failed to fetch hidden relations",
			})
			return
		}
	}

	query := db.Preload("Host").Order("created_at DESC")

	if len(blockedBy) > 0 {
		query = query.Where("host_id NOT IN ?", blockedBy)
	}

	topic := c.Query("topic")
	if topic != "" && topic != "All" {
		query = query.Where("topic = ?", topic)
	}

	isLive := c.Query("is_live")
	if isLive == "true" {
		query = query.Where("is_live = ?", true)
	}

	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "20"))
	offset := (page - 1) * limit
	countQuery := db.Model(&models.Room{})

	if len(blockedBy) > 0 {
		countQuery = countQuery.Where("host_id NOT IN ?", blockedBy)
	}

	if topic != "" && topic != "All" {
		countQuery = countQuery.Where("topic = ?", topic)
	}

	if isLive == "true" {
		countQuery = countQuery.Where("is_live = ?", true)
	}

	var total int64
	countQuery.Count(&total)

	if err := query.
		Limit(limit).
		Offset(offset).
		Find(&rooms).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error": "Failed to fetch rooms",
		})
		return
	}

	for i := range rooms {
		if rooms[i].HostID > 0 {
			var host models.User
			if err := db.First(&host, rooms[i].HostID).Error; err == nil {
				rooms[i].Host = host
			}
		}
	}

	c.JSON(http.StatusOK, gin.H{
		"success":  true,
		"rooms":    rooms,
		"page":     page,
		"limit":    limit,
		"total":    total,
		"has_more": offset+len(rooms) < int(total),
	})
}

func GetRoomByID(c *gin.Context) {
	roomID := c.Param("id")

	var room models.Room
	if err := config.DB.Preload("Host").First(&room, roomID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Room not found"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"room":    room,
	})
}

func GetMyRooms(c *gin.Context) {
	userID, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
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

	db := config.DB
	var rooms []models.Room
	var total int64

	countQuery := db.Model(&models.Room{}).
		Where("host_id = ?", userID)

	countQuery.Count(&total)

	if err := db.
		Preload("Host").
		Where("host_id = ?", userID).
		Order("created_at DESC").
		Limit(limit).
		Offset(offset).
		Find(&rooms).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch rooms"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success":  true,
		"rooms":    rooms,
		"page":     page,
		"limit":    limit,
		"total":    total,
		"has_more": offset+len(rooms) < int(total),
	})
}

func UpdateRoom(c *gin.Context) {
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
	case string:
		parsed, err := strconv.Atoi(v)
		if err != nil {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid user ID"})
			return
		}
		userID = uint(parsed)
	default:
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid user ID type"})
		return
	}

	roomIDParam := c.Param("id")
	roomID, err := strconv.Atoi(roomIDParam)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid room ID"})
		return
	}

	var room models.Room
	if err := config.DB.Where("id = ? AND host_id = ?", roomID, userID).First(&room).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			c.JSON(http.StatusNotFound, gin.H{"error": "Room not found"})
		} else {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Database error"})
		}
		return
	}

	if err := c.Request.ParseMultipartForm(32 << 20); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Failed to parse form"})
		return
	}

	title := c.PostForm("title")
	description := c.PostForm("description")
	topic := c.PostForm("topic")

	if title == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Title is required"})
		return
	}
	if topic == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Topic is required"})
		return
	}

	room.Title = title
	room.Description = description
	room.Topic = topic

	fileHeader, err := c.FormFile("thumbnail")
	if err == nil && fileHeader != nil {
		file, openErr := fileHeader.Open()
		if openErr != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Failed to open thumbnail file"})
			return
		}
		defer file.Close()

		imageData, readErr := io.ReadAll(file)
		if readErr != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Failed to read thumbnail file"})
			return
		}

		thumbURL, uploadErr := utils.UploadThumbnailToCloudinary(
			imageData,
			fmt.Sprintf("%d", userID),
		)
		if uploadErr != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": uploadErr.Error()})
			return
		}

		room.ThumbnailURL = thumbURL
	}

	if err := config.DB.Save(&room).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to update room"})
		return
	}

	c.JSON(http.StatusOK, room)
}

func UpdateRoomPrivacy(c *gin.Context) {
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
	case string:
		idParsed, err := strconv.Atoi(v)
		if err != nil {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid user ID"})
			return
		}
		userID = uint(idParsed)
	default:
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid user ID type"})
		return
	}

	roomIDParam := c.Param("id")
	roomID, err := strconv.Atoi(roomIDParam)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid room ID"})
		return
	}

	var room models.Room
	if err := config.DB.Where("id = ? AND host_id = ?", roomID, userID).First(&room).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			c.JSON(http.StatusNotFound, gin.H{"error": "Room not found"})
		} else {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Database error"})
		}
		return
	}

	var body updatePrivacyBody
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid JSON"})
		return
	}
	if body.IsPrivate == nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "is_private is required"})
		return
	}

	room.IsPrivate = *body.IsPrivate

	if err := config.DB.Save(&room).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to update room privacy"})
		return
	}

	c.JSON(http.StatusOK, room)
}

func DeleteRoom(c *gin.Context) {
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
	case string:
		idParsed, err := strconv.Atoi(v)
		if err != nil {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid user ID"})
			return
		}
		userID = uint(idParsed)
	default:
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid user ID type"})
		return
	}

	roomIDParam := c.Param("id")
	roomID, err := strconv.Atoi(roomIDParam)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid room ID"})
		return
	}

	var room models.Room
	if err := config.DB.Where("id = ? AND host_id = ?", roomID, userID).First(&room).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			c.JSON(http.StatusNotFound, gin.H{"error": "Room not found"})
		} else {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Database error"})
		}
		return
	}

	if err := config.DB.Delete(&room).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to delete room"})
		return
	}

	var affectedUserIDs []uint
	config.DB.Model(&models.Notification{}).
		Where("reference_type = ? AND reference_id = ?", "room", room.ID).
		Pluck("user_id", &affectedUserIDs)

	config.DB.Where("reference_type = ? AND reference_id = ?", "room", room.ID).
		Delete(&models.Notification{})

	if websocket.GlobalHub != nil && len(affectedUserIDs) > 0 {
		uniqueUserIDs := make(map[uint]bool)
		for _, uid := range affectedUserIDs {
			uniqueUserIDs[uid] = true
		}
		userIDList := make([]uint, 0, len(uniqueUserIDs))
		for uid := range uniqueUserIDs {
			userIDList = append(userIDList, uid)
		}

		payload := map[string]interface{}{
			"type": "remove_notifications",
			"data": map[string]interface{}{
				"reference_type": "room",
				"reference_id":   room.ID,
			},
		}
		websocket.GlobalHub.SendToUsers(userIDList, payload)
		log.Printf("✓ Sent remove_notifications to %d users for room %d", len(userIDList), room.ID)
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "Room deleted successfully",
		"id":      room.ID,
	})
}

func GetUserRooms(c *gin.Context) {
	targetUserID := c.Param("id")
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
	if page < 1 {
		page = 1
	}
	if limit < 1 {
		limit = 20
	}

	offset := (page - 1) * limit

	db := config.DB
	var rooms []models.Room
	var total int64

	if currentUserID > 0 {
		var hidden models.HiddenUser
		err := db.Where(
			"user_id = ? AND hidden_user_id = ?",
			targetUserID,
			currentUserID,
		).First(&hidden).Error

		if err == nil {
			c.JSON(http.StatusOK, gin.H{
				"success":  true,
				"rooms":    []models.Room{},
				"page":     page,
				"limit":    limit,
				"total":    0,
				"has_more": false,
			})
			return
		}
	}

	query := db.Model(&models.Room{}).
		Where("host_id = ?", targetUserID)

	if fmt.Sprint(currentUserID) != targetUserID {
		query = query.Where("is_private = ?", false)
	}

	if fmt.Sprint(currentUserID) != targetUserID {
		query = query.Where("is_hidden = ?", false)
	}

	query.Count(&total)

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
		"success":  true,
		"rooms":    rooms,
		"page":     page,
		"limit":    limit,
		"total":    total,
		"has_more": offset+len(rooms) < int(total),
	})
}

func RecordUniqueListenIfNew(c *gin.Context) {
	roomIDStr := c.Param("id")
	roomID, err := strconv.ParseUint(roomIDStr, 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid room ID"})
		return
	}

	userID := c.GetUint("user_id")

	var room models.Room
	if err := config.DB.First(&room, roomID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Room not found"})
		return
	}

	var existingListen models.UniqueRoomListen
	err = config.DB.Where("room_id = ? AND user_id = ?", roomID, userID).
		First(&existingListen).Error

	isNewListener := err == gorm.ErrRecordNotFound

	if isNewListener {
		uniqueListen := models.UniqueRoomListen{
			RoomID: uint(roomID),
			UserID: userID,
		}

		if err := config.DB.Create(&uniqueListen).Error; err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{
				"error": "Failed to record unique listen",
			})
			return
		}

		if err := config.DB.Model(&room).
			Update("total_listens", gorm.Expr("total_listens + ?", 1)).
			Error; err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{
				"error": "Failed to increment listen count",
			})
			return
		}
	}

	config.DB.First(&room, roomID)

	c.JSON(http.StatusOK, gin.H{
		"is_new_listener": isNewListener,
		"total_listens":   room.TotalListens,
		"message": func() string {
			if isNewListener {
				return "Listen recorded"
			}
			return "Already listened"
		}(),
	})
}
