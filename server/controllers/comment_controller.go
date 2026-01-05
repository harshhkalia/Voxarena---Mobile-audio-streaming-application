package controllers

import (
	"log"
	"net/http"
	"strconv"
	"voxarena_server/config"
	"voxarena_server/models"
	"voxarena_server/services"
	"voxarena_server/websocket"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

func CreateComment(c *gin.Context) {
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

	roomID, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid room ID"})
		return
	}

	var req struct {
		Content       string `json:"content" binding:"required"`
		ParentID      *uint  `json:"parent_id"`
		ReplyToUserID *uint  `json:"reply_to_user_id"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	var room models.Room
	if err := db.First(&room, roomID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Room not found"})
		return
	}

	if req.ParentID != nil {
		var parentComment models.Comment
		if err := db.First(&parentComment, *req.ParentID).Error; err != nil {
			c.JSON(http.StatusNotFound, gin.H{"error": "Parent comment not found"})
			return
		}
		if parentComment.RoomID != uint(roomID) {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Parent comment is from different room"})
			return
		}
	}

	comment := models.Comment{
		Content:       req.Content,
		RoomID:        uint(roomID),
		UserID:        userID,
		ParentID:      req.ParentID,
		ReplyToUserID: req.ReplyToUserID,
	}

	if err := db.Create(&comment).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to create comment"})
		return
	}

	db.
		Preload("User").
		Preload("ReplyToUser").
		First(&comment, comment.ID)

	notificationService := services.NewNotificationService(db)
	go func() {
		if err := notificationService.NotifyNewComment(&room, &comment, comment.User); err != nil {
			log.Printf("⚠️ Failed to send comment notification: %v", err)
		}
	}()

	c.JSON(http.StatusCreated, gin.H{
		"comment": comment,
		"message": "Comment created successfully",
	})
}

func GetComments(c *gin.Context) {
	db := config.DB

	roomID, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid room ID"})
		return
	}

	userIDValue, _ := c.Get("user_id")
	var userID uint
	if userIDValue != nil {
		switch v := userIDValue.(type) {
		case uint:
			userID = v
		case int:
			userID = uint(v)
		case int64:
			userID = uint(v)
		case float64:
			userID = uint(v)
		}
	}

	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "20"))
	offset := (page - 1) * limit

	var blockedBy []uint
	if userID > 0 {
		blockedBy, err = GetUsersWhoHidMe(db, userID)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{
				"error": "Failed to fetch hidden relations",
			})
			return
		}
	}

	query := db.
		Where("room_id = ? AND parent_id IS NULL", roomID)

	if len(blockedBy) > 0 {
		query = query.Where("user_id NOT IN ?", blockedBy)
	}

	var comments []models.Comment
	if err := query.
		Preload("User").
		Order("created_at DESC").
		Limit(limit).
		Offset(offset).
		Find(&comments).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error": "Failed to fetch comments",
		})
		return
	}

	var likedCommentIDs []uint
	if userID > 0 {
		db.Model(&models.CommentLike{}).
			Where("user_id = ?", userID).
			Pluck("comment_id", &likedCommentIDs)
	}

	likedMap := make(map[uint]bool)
	for _, id := range likedCommentIDs {
		likedMap[id] = true
	}

	type CommentResponse struct {
		models.Comment
		IsLiked      bool                     `json:"is_liked"`
		RepliesCount int                      `json:"replies_count"`
		Replies      []map[string]interface{} `json:"replies"`
	}

	var response []CommentResponse

	for _, comment := range comments {

		var allReplies []models.Comment
		rawQuery := `
			WITH RECURSIVE reply_tree AS (
				SELECT * FROM comments
				WHERE parent_id = ? AND deleted_at IS NULL
		`
		args := []interface{}{comment.ID}

		if len(blockedBy) > 0 {
			rawQuery += " AND user_id NOT IN ?"
			args = append(args, blockedBy)
		}

		rawQuery += `
				UNION ALL
				SELECT c.* FROM comments c
				INNER JOIN reply_tree rt ON c.parent_id = rt.id
				WHERE c.deleted_at IS NULL
		`

		if len(blockedBy) > 0 {
			rawQuery += " AND c.user_id NOT IN ?"
			args = append(args, blockedBy)
		}

		rawQuery += `
			)
			SELECT * FROM reply_tree ORDER BY created_at ASC
		`

		db.Raw(rawQuery, args...).Scan(&allReplies)

		for i := range allReplies {
			db.Preload("User").
				Preload("ReplyToUser").
				First(&allReplies[i], allReplies[i].ID)
		}

		var formattedReplies []map[string]interface{}
		limitReplies := allReplies
		if len(allReplies) > 3 {
			limitReplies = allReplies[:3]
		}

		for _, reply := range limitReplies {
			formattedReplies = append(formattedReplies, map[string]interface{}{
				"id":            reply.ID,
				"content":       reply.Content,
				"user":          reply.User,
				"reply_to_user": reply.ReplyToUser,
				"parent_id":     reply.ParentID,
				"created_at":    reply.CreatedAt,
				"likes_count":   reply.LikesCount,
				"is_liked":      likedMap[reply.ID],
			})
		}

		var repliesCount int64
		countQuery := `
			WITH RECURSIVE reply_tree AS (
				SELECT * FROM comments
				WHERE parent_id = ? AND deleted_at IS NULL
		`
		countArgs := []interface{}{comment.ID}

		if len(blockedBy) > 0 {
			countQuery += " AND user_id NOT IN ?"
			countArgs = append(countArgs, blockedBy)
		}

		countQuery += `
				UNION ALL
				SELECT c.* FROM comments c
				INNER JOIN reply_tree rt ON c.parent_id = rt.id
				WHERE c.deleted_at IS NULL
		`

		if len(blockedBy) > 0 {
			countQuery += " AND c.user_id NOT IN ?"
			countArgs = append(countArgs, blockedBy)
		}

		countQuery += `
			)
			SELECT COUNT(*) FROM reply_tree
		`

		db.Raw(countQuery, countArgs...).Count(&repliesCount)

		response = append(response, CommentResponse{
			Comment:      comment,
			IsLiked:      likedMap[comment.ID],
			RepliesCount: int(repliesCount),
			Replies:      formattedReplies,
		})
	}

	totalQuery := db.Model(&models.Comment{}).
		Where("room_id = ? AND parent_id IS NULL", roomID)

	if len(blockedBy) > 0 {
		totalQuery = totalQuery.Where("user_id NOT IN ?", blockedBy)
	}

	var total int64
	totalQuery.Count(&total)

	c.JSON(http.StatusOK, gin.H{
		"comments": response,
		"page":     page,
		"limit":    limit,
		"total":    total,
		"has_more": offset+len(comments) < int(total),
	})
}

func GetReplies(c *gin.Context) {
	db := config.DB

	commentID, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid comment ID"})
		return
	}

	userIDValue, _ := c.Get("user_id")
	var userID uint
	if userIDValue != nil {
		switch v := userIDValue.(type) {
		case uint:
			userID = v
		case int:
			userID = uint(v)
		case int64:
			userID = uint(v)
		case float64:
			userID = uint(v)
		}
	}

	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "20"))
	offset := (page - 1) * limit

	var blockedBy []uint
	if userID > 0 {
		blockedBy, err = GetUsersWhoHidMe(db, userID)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{
				"error": "Failed to fetch hidden relations",
			})
			return
		}
	}

	var replies []models.Comment

	rawQuery := `
		WITH RECURSIVE reply_tree AS (
			SELECT * FROM comments
			WHERE parent_id = ? AND deleted_at IS NULL
	`
	args := []interface{}{commentID}

	if len(blockedBy) > 0 {
		rawQuery += " AND user_id NOT IN ?"
		args = append(args, blockedBy)
	}

	rawQuery += `
			UNION ALL
			SELECT c.* FROM comments c
			INNER JOIN reply_tree rt ON c.parent_id = rt.id
			WHERE c.deleted_at IS NULL
	`

	if len(blockedBy) > 0 {
		rawQuery += " AND c.user_id NOT IN ?"
		args = append(args, blockedBy)
	}

	rawQuery += `
		)
		SELECT * FROM reply_tree
		ORDER BY created_at ASC
		LIMIT ? OFFSET ?
	`

	args = append(args, limit, offset)

	db.Raw(rawQuery, args...).Scan(&replies)

	for i := range replies {
		db.Preload("User").
			Preload("ReplyToUser").
			First(&replies[i], replies[i].ID)
	}

	var likedCommentIDs []uint
	if userID > 0 {
		db.Model(&models.CommentLike{}).
			Where("user_id = ?", userID).
			Pluck("comment_id", &likedCommentIDs)
	}

	likedMap := make(map[uint]bool)
	for _, id := range likedCommentIDs {
		likedMap[id] = true
	}

	type ReplyResponse struct {
		models.Comment
		IsLiked bool `json:"is_liked"`
	}

	var response []ReplyResponse
	for _, reply := range replies {
		response = append(response, ReplyResponse{
			Comment: reply,
			IsLiked: likedMap[reply.ID],
		})
	}

	countQuery := `
		WITH RECURSIVE reply_tree AS (
			SELECT * FROM comments
			WHERE parent_id = ? AND deleted_at IS NULL
	`
	countArgs := []interface{}{commentID}

	if len(blockedBy) > 0 {
		countQuery += " AND user_id NOT IN ?"
		countArgs = append(countArgs, blockedBy)
	}

	countQuery += `
			UNION ALL
			SELECT c.* FROM comments c
			INNER JOIN reply_tree rt ON c.parent_id = rt.id
			WHERE c.deleted_at IS NULL
	`

	if len(blockedBy) > 0 {
		countQuery += " AND c.user_id NOT IN ?"
		countArgs = append(countArgs, blockedBy)
	}

	countQuery += `
		)
		SELECT COUNT(*) FROM reply_tree
	`

	var total int64
	db.Raw(countQuery, countArgs...).Count(&total)

	c.JSON(http.StatusOK, gin.H{
		"replies":  response,
		"page":     page,
		"limit":    limit,
		"total":    total,
		"has_more": offset+len(replies) < int(total),
	})
}

func DeleteComment(c *gin.Context) {
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

	commentID, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid comment ID"})
		return
	}

	var comment models.Comment
	if err := db.Preload("Room").Preload("Room.Host").First(&comment, commentID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Comment not found"})
		return
	}

	isCommentOwner := comment.UserID == userID
	isRoomOwner := comment.Room.HostID == userID

	if !isCommentOwner && !isRoomOwner {
		c.JSON(http.StatusForbidden, gin.H{"error": "You can only delete your own comments or comments in your room"})
		return
	}

	db.Where("parent_id = ?", commentID).Delete(&models.Comment{})
	db.Where("comment_id = ?", commentID).Delete(&models.CommentLike{})

	var affectedUserIDs []uint
	db.Model(&models.Notification{}).
		Where("actor_id = ? AND message = ? AND reference_type = ? AND reference_id = ?",
			comment.UserID, comment.Content, "room", comment.RoomID).
		Pluck("user_id", &affectedUserIDs)

	db.Where("actor_id = ? AND message = ? AND reference_type = ? AND reference_id = ?",
		comment.UserID, comment.Content, "room", comment.RoomID).
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
			"type": "remove_comment_notification",
			"data": map[string]interface{}{
				"actor_id":   comment.UserID,
				"message":    comment.Content,
				"room_id":    comment.RoomID,
			},
		}
		websocket.GlobalHub.SendToUsers(userIDList, payload)
		log.Printf("✓ Sent remove_comment_notification to %d users for comment %d", len(userIDList), comment.ID)
	}

	if err := db.Delete(&comment).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to delete comment"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Comment deleted successfully"})
}

func ToggleCommentLike(c *gin.Context) {
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

	commentID, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid comment ID"})
		return
	}

	var comment models.Comment
	if err := db.Preload("Room").Preload("Room.Host").First(&comment, commentID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Comment not found"})
		return
	}

	var liker models.User
	db.First(&liker, userID)

	var like models.CommentLike
	err = db.Where("comment_id = ? AND user_id = ?", commentID, userID).First(&like).Error

	if err == gorm.ErrRecordNotFound {
		like = models.CommentLike{
			CommentID: uint(commentID),
			UserID:    userID,
		}
		if err := db.Create(&like).Error; err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to like comment"})
			return
		}

		db.Model(&comment).Update("likes_count", gorm.Expr("likes_count + ?", 1))
		db.First(&comment, commentID)

		if comment.UserID != userID {
			hostName := "a post"
			if comment.Room.Host.FullName != "" {
				hostName = comment.Room.Host.FullName + "'s audio"
			}

			notification := models.Notification{
				UserID:        comment.UserID,
				ActorID:       userID,
				Type:          models.NotificationTypeCommentLike,
				Title:         liker.FullName + " liked your comment",
				Message:       comment.Content,
				ExtraData:     hostName,
				ReferenceID:   &comment.RoomID,
				ReferenceType: "room",
				ImageURL:      comment.Room.ThumbnailURL,
				ActionURL:     "/comments/" + strconv.Itoa(commentID),
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
							"extra_data":     notification.ExtraData,
							"image_url":      notification.ImageURL,
							"action_url":     notification.ActionURL,
							"reference_id":   notification.ReferenceID,
							"reference_type": notification.ReferenceType,
							"is_read":        notification.IsRead,
							"created_at":     notification.CreatedAt,
							"actor": map[string]interface{}{
								"id":          liker.ID,
								"full_name":   liker.FullName,
								"username":    liker.Username,
								"profile_pic": liker.ProfilePic,
							},
						},
					}
					websocket.GlobalHub.SendToUsers([]uint{comment.UserID}, payload)
					log.Printf("✓ Sent comment_like notification to user %d", comment.UserID)
				}
			}
		}

		c.JSON(http.StatusOK, gin.H{
			"is_liked":    true,
			"likes_count": comment.LikesCount,
			"message":     "Comment liked",
		})
	} else if err == nil {
		db.Delete(&like)
		db.Model(&comment).Update("likes_count", gorm.Expr("GREATEST(likes_count - ?, 0)", 1))
		db.First(&comment, commentID)
		if comment.UserID != userID {
			db.Where("user_id = ? AND actor_id = ? AND type = ? AND message = ?",
				comment.UserID, userID, models.NotificationTypeCommentLike, comment.Content).
				Delete(&models.Notification{})

			if websocket.GlobalHub != nil {
				payload := map[string]interface{}{
					"type": "remove_comment_like_notification",
					"data": map[string]interface{}{
						"actor_id": userID,
						"message":  comment.Content,
					},
				}
				websocket.GlobalHub.SendToUsers([]uint{comment.UserID}, payload)
				log.Printf("✓ Sent remove_comment_like_notification to user %d", comment.UserID)
			}
		}

		c.JSON(http.StatusOK, gin.H{
			"is_liked":    false,
			"likes_count": comment.LikesCount,
			"message":     "Comment unliked",
		})
	} else {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Database error"})
	}
}
