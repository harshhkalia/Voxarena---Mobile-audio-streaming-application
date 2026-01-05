package controllers

import (
	"net/http"
	"voxarena_server/config"
	"voxarena_server/models"

	"github.com/gin-gonic/gin"
)

type QueueRequest struct {
	CurrentRoomID uint   `json:"current_room_id" binding:"required"`
	Topic         string `json:"topic"`
	Limit         int    `json:"limit"`
}

type QueueResponse struct {
	Queue []models.Room `json:"queue"`
	Total int           `json:"total"`
}

func GetSmartQueue(c *gin.Context) {
	userID := c.GetUint("user_id")

	var req QueueRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if req.Limit == 0 {
		req.Limit = 20
	}

	db := config.DB

	hiddenByUserIDs, err := GetUsersWhoHidMe(db, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch hidden users"})
		return
	}

	var reportedRoomIDs []uint
	db.Model(&models.RoomReport{}).
		Where("user_id = ?", userID).
		Pluck("room_id", &reportedRoomIDs)

	var listenedRoomIDs []uint
	db.Model(&models.ListenHistory{}).
		Where("user_id = ?", userID).
		Order("listened_at DESC").
		Limit(50).
		Pluck("room_id", &listenedRoomIDs)

	var listenedTopics []string
	if len(listenedRoomIDs) > 0 {
		db.Model(&models.Room{}).
			Where("id IN ?", listenedRoomIDs).
			Distinct("topic").
			Pluck("topic", &listenedTopics)
	}

	var queue []models.Room

	if req.Topic != "" {
		var topicRooms []models.Room
		topicQuery := db.Model(&models.Room{}).
			Preload("Host").
			Where("topic = ?", req.Topic).
			Where("id != ?", req.CurrentRoomID).
			Where("is_private = ?", false).
			Where("is_hidden = ?", false).
			Where("id NOT IN ?", append(listenedRoomIDs, req.CurrentRoomID))

		if len(hiddenByUserIDs) > 0 {
			topicQuery = topicQuery.Where("host_id NOT IN ?", hiddenByUserIDs)
		}

		if len(reportedRoomIDs) > 0 {
			topicQuery = topicQuery.Where("id NOT IN ?", reportedRoomIDs)
		}

		topicQuery.Order("likes_count DESC, total_listens DESC").
			Limit(req.Limit / 2).
			Find(&topicRooms)

		queue = append(queue, topicRooms...)
	}

	remainingSlots := req.Limit - len(queue)
	if remainingSlots > 0 {
		var recommendedRooms []models.Room

		excludeIDs := []uint{req.CurrentRoomID}
		for _, room := range queue {
			excludeIDs = append(excludeIDs, room.ID)
		}
		excludeIDs = append(excludeIDs, listenedRoomIDs...)

		recQuery := db.Model(&models.Room{}).
			Preload("Host").
			Where("id NOT IN ?", excludeIDs).
			Where("is_private = ?", false).
			Where("is_hidden = ?", false)

		if len(hiddenByUserIDs) > 0 {
			recQuery = recQuery.Where("host_id NOT IN ?", hiddenByUserIDs)
		}

		if len(reportedRoomIDs) > 0 {
			recQuery = recQuery.Where("id NOT IN ?", reportedRoomIDs)
		}

		if len(listenedTopics) > 0 {
			recQuery = recQuery.Where("topic IN ?", listenedTopics)
		}

		recQuery.Order("likes_count DESC, total_listens DESC").
			Limit(remainingSlots).
			Find(&recommendedRooms)

		queue = append(queue, recommendedRooms...)
	}

	if len(queue) < req.Limit {
		remainingSlots := req.Limit - len(queue)
		var popularRooms []models.Room

		excludeIDs := []uint{uint(req.CurrentRoomID)}
		for _, room := range queue {
			excludeIDs = append(excludeIDs, room.ID)
		}

		popularQuery := db.Model(&models.Room{}).
			Preload("Host").
			Where("id NOT IN ?", excludeIDs).
			Where("is_private = ?", false).
			Where("is_hidden = ?", false)

		if len(hiddenByUserIDs) > 0 {
			popularQuery = popularQuery.Where("host_id NOT IN ?", hiddenByUserIDs)
		}

		if len(reportedRoomIDs) > 0 {
			popularQuery = popularQuery.Where("id NOT IN ?", reportedRoomIDs)
		}

		popularQuery.Order("likes_count DESC, total_listens DESC").
			Limit(remainingSlots).
			Find(&popularRooms)

		queue = append(queue, popularRooms...)
	}

	c.JSON(http.StatusOK, QueueResponse{
		Queue: queue,
		Total: len(queue),
	})
}

func GetQueueFromSearch(c *gin.Context) {
	userID := c.GetUint("user_id")
	currentRoomID := c.Query("current_room_id")
	searchQuery := c.Query("query")
	limit := 20

	if currentRoomID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "current_room_id is required"})
		return
	}

	db := config.DB

	hiddenByUserIDs, err := GetUsersWhoHidMe(db, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch hidden users"})
		return
	}

	var reportedRoomIDs []uint
	db.Model(&models.RoomReport{}).
		Where("user_id = ?", userID).
		Pluck("room_id", &reportedRoomIDs)

	var queue []models.Room
	searchPattern := "%" + searchQuery + "%"

	query := db.Model(&models.Room{}).
		Preload("Host").
		Where("(title ILIKE ? OR description ILIKE ? OR topic ILIKE ?)",
			searchPattern, searchPattern, searchPattern).
		Where("id != ?", currentRoomID).
		Where("is_private = ?", false).
		Where("is_hidden = ?", false)

	if len(hiddenByUserIDs) > 0 {
		query = query.Where("host_id NOT IN ?", hiddenByUserIDs)
	}

	if len(reportedRoomIDs) > 0 {
		query = query.Where("id NOT IN ?", reportedRoomIDs)
	}

	var listenedRoomIDs []uint
	db.Model(&models.ListenHistory{}).
		Where("user_id = ?", userID).
		Order("listened_at DESC").
		Limit(50).
		Pluck("room_id", &listenedRoomIDs)

	if len(listenedRoomIDs) > 0 {
		query = query.Where("id NOT IN ?", listenedRoomIDs)
	}

	query.Order("likes_count DESC, total_listens DESC").
		Limit(limit).
		Find(&queue)

	c.JSON(http.StatusOK, QueueResponse{
		Queue: queue,
		Total: len(queue),
	})
}
