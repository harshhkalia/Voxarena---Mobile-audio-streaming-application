package controllers

import (
	"net/http"
	"strconv"
	"time"
	"voxarena_server/config"
	"voxarena_server/models"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

type TrackListenRequest struct {
	Duration       int     `json:"duration"`
	LastPosition   int     `json:"last_position"`
	CompletionRate float64 `json:"completion_rate"`
	IsCompleted    bool    `json:"is_completed"`
	IsSkipped      bool    `json:"is_skipped"`
}

func StartListening(c *gin.Context) {
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

	if room.IsLive {
		if err := config.DB.Model(&room).Update("listener_count", gorm.Expr("listener_count + ?", 1)).Error; err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to update listener count"})
			return
		}
	}

	listenHistory := models.ListenHistory{
		UserID:     userID,
		RoomID:     uint(roomID),
		ListenedAt: time.Now(),
	}

	if err := config.DB.Create(&listenHistory).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to create listen history"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message":        "Started listening",
		"listener_count": room.ListenerCount + 1,
		"total_listens":  room.TotalListens,
		"is_live":        room.IsLive,
		"history_id":     listenHistory.ID,
	})
}

func StopListening(c *gin.Context) {
	roomIDStr := c.Param("id")
	roomID, err := strconv.ParseUint(roomIDStr, 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid room ID"})
		return
	}

	var room models.Room
	if err := config.DB.First(&room, roomID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Room not found"})
		return
	}

	if room.IsLive && room.ListenerCount > 0 {
		if err := config.DB.Model(&room).Update("listener_count", gorm.Expr("listener_count - ?", 1)).Error; err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to update listener count"})
			return
		}
	}

	c.JSON(http.StatusOK, gin.H{
		"message":        "Stopped listening",
		"listener_count": room.ListenerCount - 1,
		"is_live":        room.IsLive,
	})
}

func UpdateListenHistory(c *gin.Context) {
	historyID := c.Param("id")

	var req TrackListenRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	userID := c.GetUint("user_id")

	var history models.ListenHistory
	if err := config.DB.Where("id = ? AND user_id = ?", historyID, userID).First(&history).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Listen history not found"})
		return
	}

	updates := map[string]interface{}{
		"duration":        req.Duration,
		"last_position":   req.LastPosition,
		"completion_rate": req.CompletionRate,
		"is_completed":    req.IsCompleted,
		"is_skipped":      req.IsSkipped,
	}

	if err := config.DB.Model(&history).Updates(updates).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to update listen history"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "Listen history updated",
		"history": history,
	})
}

func GetListenerCount(c *gin.Context) {
	roomIDStr := c.Param("id")
	roomID, err := strconv.ParseUint(roomIDStr, 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid room ID"})
		return
	}

	var room models.Room
	if err := config.DB.Select("id, listener_count, total_listens, is_live").First(&room, roomID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Room not found"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"room_id":        room.ID,
		"listener_count": room.ListenerCount,
		"total_listens":  room.TotalListens,
		"is_live":        room.IsLive,
	})
}

func GetUserListenHistory(c *gin.Context) {
	userID := c.GetUint("user_id")

	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "20"))
	offset := (page - 1) * limit

	var histories []models.ListenHistory
	var total int64

	db := config.DB

	var blockedBy []uint
	if userID > 0 {
		var err error
		blockedBy, err = GetUsersWhoHidMe(db, userID)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{
				"error": "Failed to fetch hidden relations",
			})
			return
		}
	}

	query := db.
		Where("listen_history.user_id = ?", userID).
		Joins("JOIN rooms ON rooms.id = listen_history.room_id").
		Where(
			"rooms.is_live = ? OR rooms.is_private = ? OR rooms.host_id = ?",
			true,
			false,
			userID,
		).
		Where("rooms.is_hidden = ?", false)

	if len(blockedBy) > 0 {
		query = query.Where("rooms.host_id NOT IN ?", blockedBy)
	}

	if err := query.
		Model(&models.ListenHistory{}).
		Count(&total).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error": "Failed to count history",
		})
		return
	}

	if err := query.
		Preload(
			"Room",
			"is_live = ? OR is_private = ? OR host_id = ? AND is_hidden = ?",
			true,
			false,
			userID,
			false,
		).
		Preload("Room.Host").
		Order("listen_history.listened_at DESC").
		Limit(limit).
		Offset(offset).
		Find(&histories).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error": "Failed to fetch history",
		})
		return
	}

	filteredHistories := make([]models.ListenHistory, 0)
	for _, h := range histories {
		if h.Room.ID != 0 {
			filteredHistories = append(filteredHistories, h)
		}
	}

	c.JSON(http.StatusOK, gin.H{
		"history":  filteredHistories,
		"total":    total,
		"page":     page,
		"limit":    limit,
		"has_more": offset+limit < int(total),
	})
}

func DeleteListenHistory(c *gin.Context) {
	userID := c.GetUint("user_id")
	historyID := c.Param("id")

	var history models.ListenHistory

	if err := config.DB.Where("id = ? AND user_id = ?", historyID, userID).
		First(&history).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{
			"error": "History not found",
		})
		return
	}

	if err := config.DB.Delete(&history).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error": "Failed to delete history",
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "History removed",
		"id":      historyID,
	})
}
