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

const REPORT_THRESHOLD = 10

func ReportRoom(c *gin.Context) {
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

	roomIDStr := c.Param("id")
	roomID, err := strconv.Atoi(roomIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid room ID"})
		return
	}

	var req struct {
		Reason  string `json:"reason" binding:"required"`
		Details string `json:"details"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Reason is required"})
		return
	}

	var room models.Room
	if err := db.First(&room, roomID).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			c.JSON(http.StatusNotFound, gin.H{"error": "Room not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Database error"})
		return
	}

	if room.IsHidden {
		c.JSON(http.StatusBadRequest, gin.H{"error": "This room has already been hidden due to reports"})
		return
	}

	var existingReport models.RoomReport
	err = db.Where("room_id = ? AND reporter_id = ?", roomID, userID).First(&existingReport).Error
	if err == nil {
		c.JSON(http.StatusConflict, gin.H{
			"error":       "You have already reported this room",
			"status":      existingReport.Status,
			"reported_at": existingReport.CreatedAt,
		})
		return
	} else if err != gorm.ErrRecordNotFound {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Database error"})
		return
	}

	err = db.Transaction(func(tx *gorm.DB) error {
		report := models.RoomReport{
			RoomID:     uint(roomID),
			ReporterID: userID,
			Reason:     req.Reason,
			Details:    req.Details,
			Status:     "pending",
		}

		if err := tx.Create(&report).Error; err != nil {
			return err
		}

		if err := tx.Model(&models.Room{}).
			Where("id = ?", roomID).
			Update("report_count", gorm.Expr("report_count + ?", 1)).Error; err != nil {
			return err
		}

		if err := tx.First(&room, roomID).Error; err != nil {
			return err
		}

		if room.ReportCount >= REPORT_THRESHOLD {
			now := time.Now()
			if err := tx.Model(&models.Room{}).
				Where("id = ?", roomID).
				Updates(map[string]interface{}{
					"is_hidden":     true,
					"hidden_at":     &now,
					"hidden_reason": "Exceeded report threshold",
				}).Error; err != nil {
				return err
			}

			if err := tx.Model(&models.RoomReport{}).
				Where("room_id = ? AND status = ?", roomID, "pending").
				Update("status", "reviewed").Error; err != nil {
				return err
			}
		}

		return nil
	})

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to submit report"})
		return
	}

	var message string
	var roomHidden bool
	if room.ReportCount+1 >= REPORT_THRESHOLD {
		message = "Report submitted. Room has been hidden due to multiple reports."
		roomHidden = true
	} else {
		message = "Report submitted successfully"
		roomHidden = false
	}

	c.JSON(http.StatusOK, gin.H{
		"success":      true,
		"message":      message,
		"report_count": room.ReportCount + 1,
		"room_hidden":  roomHidden,
	})
}

func GetRoomReports(c *gin.Context) {
	db := config.DB

	roomIDStr := c.Param("id")
	roomID, err := strconv.Atoi(roomIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid room ID"})
		return
	}

	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "20"))
	offset := (page - 1) * limit

	var total int64
	db.Model(&models.RoomReport{}).Where("room_id = ?", roomID).Count(&total)

	var reports []models.RoomReport
	if err := db.
		Preload("Reporter").
		Where("room_id = ?", roomID).
		Order("created_at DESC").
		Limit(limit).
		Offset(offset).
		Find(&reports).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch reports"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"reports":  reports,
		"page":     page,
		"limit":    limit,
		"total":    total,
		"has_more": offset+len(reports) < int(total),
	})
}

func CleanupHiddenRooms(db *gorm.DB) error {
	sevenDaysAgo := time.Now().AddDate(0, 0, -7)

	result := db.Where("is_hidden = ? AND hidden_at IS NOT NULL AND hidden_at < ?", true, sevenDaysAgo).
		Delete(&models.Room{})

	if result.Error != nil {
		return result.Error
	}

	// Log the cleanup - you should use proper logging in production
	// log.Printf("Cleanup: Deleted %d hidden rooms older than 7 days", result.RowsAffected)

	return nil
}

func CheckIfReported(c *gin.Context) {
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

	roomIDStr := c.Param("id")
	roomID, err := strconv.Atoi(roomIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid room ID"})
		return
	}

	var report models.RoomReport
	err = db.Where("room_id = ? AND reporter_id = ?", roomID, userID).First(&report).Error

	if err == gorm.ErrRecordNotFound {
		c.JSON(http.StatusOK, gin.H{
			"has_reported": false,
		})
		return
	} else if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Database error"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"has_reported": true,
		"report_id":    report.ID,
		"reason":       report.Reason,
		"status":       report.Status,
		"reported_at":  report.CreatedAt,
	})
}
