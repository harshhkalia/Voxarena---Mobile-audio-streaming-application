package controllers

import (
	"net/http"
	"strconv"
	"time"
	"voxarena_server/config"
	"voxarena_server/models"

	"github.com/gin-gonic/gin"
)

type CreateDownloadRequest struct {
	RoomID       uint   `json:"room_id" binding:"required"`
	FileName     string `json:"file_name"`
	FileSize     int64  `json:"file_size"`
	DownloadPath string `json:"download_path"`
}

func TrackDownload(c *gin.Context) {
	userID := c.GetUint("user_id")

	var req CreateDownloadRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	var room models.Room
	if err := config.DB.First(&room, req.RoomID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Room not found"})
		return
	}

	var existingDownload models.DownloadHistory
	oneHourAgo := time.Now().Add(-1 * time.Hour)
	err := config.DB.Where(
		"user_id = ? AND room_id = ? AND downloaded_at > ?",
		userID,
		req.RoomID,
		oneHourAgo,
	).First(&existingDownload).Error

	if err == nil {
		c.JSON(http.StatusOK, gin.H{
			"message":  "Download already tracked",
			"download": existingDownload,
		})
		return
	}

	downloadHistory := models.DownloadHistory{
		UserID:       userID,
		RoomID:       req.RoomID,
		DownloadedAt: time.Now(),
		FileName:     req.FileName,
		FileSize:     req.FileSize,
		DownloadPath: req.DownloadPath,
	}

	if err := config.DB.Create(&downloadHistory).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error": "Failed to track download",
		})
		return
	}

	c.JSON(http.StatusCreated, gin.H{
		"message":  "Download tracked successfully",
		"download": downloadHistory,
	})
}

func GetUserDownloadHistory(c *gin.Context) {
	userID := c.GetUint("user_id")

	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "20"))
	offset := (page - 1) * limit

	var downloads []models.DownloadHistory
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
		Where("download_history.user_id = ?", userID).
		Joins("JOIN rooms ON rooms.id = download_history.room_id").
		Where(
			"(rooms.is_live = ? OR rooms.is_private = ? OR rooms.host_id = ?) AND rooms.is_hidden = ?",
			true,
			false,
			userID,
			false,
		)

	if len(blockedBy) > 0 {
		query = query.Where("rooms.host_id NOT IN ?", blockedBy)
	}

	if err := query.
		Model(&models.DownloadHistory{}).
		Count(&total).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error": "Failed to count downloads",
		})
		return
	}

	if err := query.
		Preload(
			"Room",
			"(is_live = ? OR is_private = ? OR host_id = ?) AND is_hidden = ?",
			true,
			false,
			userID,
			false,
		).
		Preload("Room.Host").
		Order("download_history.downloaded_at DESC").
		Limit(limit).
		Offset(offset).
		Find(&downloads).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error": "Failed to fetch downloads",
		})
		return
	}

	filteredDownloads := make([]models.DownloadHistory, 0)
	for _, d := range downloads {
		if d.Room.ID != 0 {
			filteredDownloads = append(filteredDownloads, d)
		}
	}

	c.JSON(http.StatusOK, gin.H{
		"downloads": filteredDownloads,
		"total":     total,
		"page":      page,
		"limit":     limit,
		"has_more":  offset+limit < int(total),
	})
}

func DeleteDownloadHistory(c *gin.Context) {
	userID := c.GetUint("user_id")
	downloadID := c.Param("id")

	var download models.DownloadHistory

	if err := config.DB.Where("id = ? AND user_id = ?", downloadID, userID).
		First(&download).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{
			"error": "Download history not found",
		})
		return
	}

	if err := config.DB.Delete(&download).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error": "Failed to delete download history",
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "Download history removed",
		"id":      downloadID,
	})
}

func ClearAllDownloadHistory(c *gin.Context) {
	userID := c.GetUint("user_id")

	result := config.DB.Where("user_id = ?", userID).Delete(&models.DownloadHistory{})

	if result.Error != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error": "Failed to clear download history",
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "Download history cleared",
		"deleted": result.RowsAffected,
	})
}
