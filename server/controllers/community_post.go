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

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

func CreateCommunityPost(c *gin.Context) {
	userID, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}

	var uid uint
	switch v := userID.(type) {
	case uint:
		uid = v
	case int:
		uid = uint(v)
	case int64:
		uid = uint(v)
	case float64:
		uid = uint(v)
	default:
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid user ID"})
		return
	}

	if err := c.Request.ParseMultipartForm(100 << 20); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Failed to parse form"})
		return
	}

	content := strings.TrimSpace(c.PostForm("content"))
	durationStr := c.PostForm("duration")

	if content == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Content is required"})
		return
	}

	post := models.CommunityPost{
		UserID:        uid,
		Content:       content,
		LikesCount:    0,
		CommentsCount: 0,
	}

	audioFile, audioHeader, err := c.Request.FormFile("audio")
	if err == nil {
		defer audioFile.Close()

		if audioHeader.Size > 10*1024*1024 {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Audio file must be less than 10MB"})
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

		audioURL, err := utils.UploadCommunityAudioToCloudinary(audioData, fmt.Sprint(uid))
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": fmt.Sprintf("Failed to upload audio: %v", err)})
			return
		}

		post.AudioURL = audioURL

		if durationStr != "" {
			duration, _ := strconv.Atoi(durationStr)
			if duration > 60 {
				c.JSON(http.StatusBadRequest, gin.H{"error": "Audio duration must not exceed 60 seconds"})
				return
			}
			post.Duration = duration
		}
	}

	tx := config.DB.Begin()

	if err := tx.Create(&post).Error; err != nil {
		tx.Rollback()
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to create post"})
		return
	}

	form, _ := c.MultipartForm()
	images := form.File["images"]

	if len(images) > 5 {
		tx.Rollback()
		c.JSON(http.StatusBadRequest, gin.H{"error": "Maximum 5 images allowed"})
		return
	}

	var imageURLs []string
	for i, imageHeader := range images {
		imageFile, err := imageHeader.Open()
		if err != nil {
			tx.Rollback()
			c.JSON(http.StatusBadRequest, gin.H{"error": fmt.Sprintf("Failed to open image %d", i+1)})
			return
		}
		defer imageFile.Close()

		if imageHeader.Size > 5*1024*1024 {
			tx.Rollback()
			c.JSON(http.StatusBadRequest, gin.H{"error": fmt.Sprintf("Image %d must be less than 5MB", i+1)})
			return
		}

		imageData, err := io.ReadAll(imageFile)
		if err != nil {
			tx.Rollback()
			c.JSON(http.StatusInternalServerError, gin.H{"error": fmt.Sprintf("Failed to read image %d", i+1)})
			return
		}

		imageURL, err := utils.UploadCommunityImageToCloudinary(imageData, fmt.Sprint(uid))
		if err != nil {
			tx.Rollback()
			c.JSON(http.StatusInternalServerError, gin.H{"error": fmt.Sprintf("Failed to upload image %d: %v", i+1, err)})
			return
		}

		postImage := models.CommunityPostImage{
			CommunityPostID: post.ID,
			ImageURL:        imageURL,
			Position:        i,
		}

		if err := tx.Create(&postImage).Error; err != nil {
			tx.Rollback()
			c.JSON(http.StatusInternalServerError, gin.H{"error": fmt.Sprintf("Failed to save image %d", i+1)})
			return
		}

		imageURLs = append(imageURLs, imageURL)
	}

	tx.Commit()

	config.DB.Preload("User").First(&post, post.ID)

	notifService := services.NewNotificationService(config.DB)
	if err := notifService.NotifyNewCommunityPost(&post); err != nil {
		fmt.Printf("Failed to send notifications for new post: %v\n", err)
	}

	c.JSON(http.StatusCreated, gin.H{
		"success": true,
		"message": "Community post created successfully",
		"post": gin.H{
			"id":             post.ID,
			"user_id":        post.UserID,
			"content":        post.Content,
			"audio_url":      post.AudioURL,
			"duration":       post.Duration,
			"images":         imageURLs,
			"likes_count":    post.LikesCount,
			"comments_count": post.CommentsCount,
			"created_at":     post.CreatedAt,
			"user":           post.User,
		},
	})
}

func GetCommunityPosts(c *gin.Context) {
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
	var posts []models.CommunityPost
	var total int64

	var blockedBy []uint
	if viewerID > 0 {
		var err error
		blockedBy, err = GetUsersWhoHidMe(db, viewerID)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch hidden relations"})
			return
		}
	}

	query := db.Model(&models.CommunityPost{})
	if len(blockedBy) > 0 {
		query = query.Where("user_id NOT IN ?", blockedBy)
	}

	query.Count(&total)

	if err := query.
		Preload("User").
		Order("created_at DESC").
		Limit(limit).
		Offset(offset).
		Find(&posts).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch posts"})
		return
	}

	var likedPostIDs []uint
	if viewerID > 0 {
		db.Model(&models.CommunityPostLike{}).
			Where("user_id = ?", viewerID).
			Pluck("community_post_id", &likedPostIDs)
	}

	likedMap := make(map[uint]bool)
	for _, id := range likedPostIDs {
		likedMap[id] = true
	}

	var postsWithImages []map[string]interface{}
	for _, post := range posts {
		var images []models.CommunityPostImage
		db.Where("community_post_id = ?", post.ID).
			Order("position ASC").
			Find(&images)

		postData := map[string]interface{}{
			"id":             post.ID,
			"user_id":        post.UserID,
			"user":           post.User,
			"content":        post.Content,
			"audio_url":      post.AudioURL,
			"duration":       post.Duration,
			"images":         images,
			"likes_count":    post.LikesCount,
			"comments_count": post.CommentsCount,
			"is_liked":       likedMap[post.ID],
			"created_at":     post.CreatedAt,
			"updated_at":     post.UpdatedAt,
		}

		postsWithImages = append(postsWithImages, postData)
	}

	c.JSON(http.StatusOK, gin.H{
		"success":  true,
		"posts":    postsWithImages,
		"page":     page,
		"limit":    limit,
		"total":    total,
		"has_more": offset+len(posts) < int(total),
	})
}

func GetCommunityPostByID(c *gin.Context) {
	postID := c.Param("id")

	userIDValue, _ := c.Get("user_id")
	var viewerID uint
	if userIDValue != nil {
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

	var post models.CommunityPost
	if err := config.DB.Preload("User").First(&post, postID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Post not found"})
		return
	}

	if viewerID > 0 {
		var hidden models.HiddenUser
		err := config.DB.Where("user_id = ? AND hidden_user_id = ?", post.UserID, viewerID).First(&hidden).Error
		if err == nil {
			c.JSON(http.StatusForbidden, gin.H{
				"error":         "This content is not available",
				"is_restricted": true,
			})
			return
		}
	}

	var images []models.CommunityPostImage
	config.DB.Where("community_post_id = ?", post.ID).
		Order("position ASC").
		Find(&images)

	var isLiked bool
	if viewerID > 0 {
		var like models.CommunityPostLike
		err := config.DB.Where("community_post_id = ? AND user_id = ?", post.ID, viewerID).First(&like).Error
		isLiked = (err == nil)
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"post": gin.H{
			"id":             post.ID,
			"user_id":        post.UserID,
			"user":           post.User,
			"content":        post.Content,
			"audio_url":      post.AudioURL,
			"duration":       post.Duration,
			"images":         images,
			"likes_count":    post.LikesCount,
			"comments_count": post.CommentsCount,
			"is_liked":       isLiked,
			"created_at":     post.CreatedAt,
			"updated_at":     post.UpdatedAt,
		},
	})
}

func GetUserCommunityPosts(c *gin.Context) {
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
	var posts []models.CommunityPost
	var total int64

	if currentUserID > 0 {
		var hidden models.HiddenUser
		err := db.Where("user_id = ? AND hidden_user_id = ?", targetUserID, currentUserID).First(&hidden).Error
		if err == nil {
			c.JSON(http.StatusOK, gin.H{
				"success":  true,
				"posts":    []models.CommunityPost{},
				"page":     page,
				"limit":    limit,
				"total":    0,
				"has_more": false,
			})
			return
		}
	}

	query := db.Model(&models.CommunityPost{}).Where("user_id = ?", targetUserID)
	query.Count(&total)

	if err := query.
		Preload("User").
		Order("created_at DESC").
		Limit(limit).
		Offset(offset).
		Find(&posts).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch posts"})
		return
	}

	var likedPostIDs []uint
	if currentUserID > 0 {
		db.Model(&models.CommunityPostLike{}).
			Where("user_id = ?", currentUserID).
			Pluck("community_post_id", &likedPostIDs)
	}

	likedMap := make(map[uint]bool)
	for _, id := range likedPostIDs {
		likedMap[id] = true
	}

	var postsWithImages []map[string]interface{}
	for _, post := range posts {
		var images []models.CommunityPostImage
		db.Where("community_post_id = ?", post.ID).
			Order("position ASC").
			Find(&images)

		postData := map[string]interface{}{
			"id":             post.ID,
			"user_id":        post.UserID,
			"user":           post.User,
			"content":        post.Content,
			"audio_url":      post.AudioURL,
			"duration":       post.Duration,
			"images":         images,
			"likes_count":    post.LikesCount,
			"comments_count": post.CommentsCount,
			"is_liked":       likedMap[post.ID],
			"created_at":     post.CreatedAt,
			"updated_at":     post.UpdatedAt,
		}

		postsWithImages = append(postsWithImages, postData)
	}

	c.JSON(http.StatusOK, gin.H{
		"success":  true,
		"posts":    postsWithImages,
		"page":     page,
		"limit":    limit,
		"total":    total,
		"has_more": offset+len(posts) < int(total),
	})
}

func UpdateCommunityPost(c *gin.Context) {
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
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid user ID"})
		return
	}

	postID := c.Param("id")

	var post models.CommunityPost
	if err := config.DB.Where("id = ? AND user_id = ?", postID, userID).First(&post).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			c.JSON(http.StatusNotFound, gin.H{"error": "Post not found or unauthorized"})
		} else {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Database error"})
		}
		return
	}

	if err := c.Request.ParseMultipartForm(100 << 20); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Failed to parse form"})
		return
	}

	content := strings.TrimSpace(c.PostForm("content"))
	if content == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Content is required"})
		return
	}
	post.Content = content

	tx := config.DB.Begin()

	removeAudio := c.PostForm("remove_audio")
	if removeAudio == "true" {
		if post.AudioURL != "" {
			if err := utils.DeleteCommunityAudioFromCloudinary(post.AudioURL); err != nil {
				fmt.Printf("Failed to delete audio from Cloudinary: %v\n", err)
			}

			post.AudioURL = ""
			post.Duration = 0
		}
	}

	form, _ := c.MultipartForm()
	newAudioFiles := form.File["new_audio"]

	if len(newAudioFiles) > 0 {
		audioHeader := newAudioFiles[0]
		audioFile, err := audioHeader.Open()
		if err != nil {
			tx.Rollback()
			c.JSON(http.StatusBadRequest, gin.H{"error": "Failed to open audio file"})
			return
		}
		defer audioFile.Close()

		if audioHeader.Size > 10*1024*1024 {
			tx.Rollback()
			c.JSON(http.StatusBadRequest, gin.H{"error": "Audio file must be less than 10MB"})
			return
		}

		audioData, err := io.ReadAll(audioFile)
		if err != nil {
			tx.Rollback()
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to read audio file"})
			return
		}

		if post.AudioURL != "" {
			if err := utils.DeleteCommunityAudioFromCloudinary(post.AudioURL); err != nil {
				fmt.Printf("Failed to delete old audio from Cloudinary: %v\n", err)
			}
		}

		audioURL, err := utils.UploadCommunityAudioToCloudinary(audioData, fmt.Sprint(userID))
		if err != nil {
			tx.Rollback()
			c.JSON(http.StatusInternalServerError, gin.H{"error": fmt.Sprintf("Failed to upload audio: %v", err)})
			return
		}

		post.AudioURL = audioURL

		durationStr := c.PostForm("audio_duration")
		if durationStr != "" {
			if duration, err := strconv.Atoi(durationStr); err == nil {
				post.Duration = duration
			}
		}
	}

	deleteIndicesStr := c.PostForm("delete_image_indices")
	if deleteIndicesStr != "" {
		var currentImages []models.CommunityPostImage
		tx.Where("community_post_id = ?", post.ID).
			Order("position ASC").
			Find(&currentImages)

		indices := strings.Split(deleteIndicesStr, ",")
		for _, indexStr := range indices {
			index, err := strconv.Atoi(strings.TrimSpace(indexStr))
			if err != nil {
				continue
			}

			if index >= 0 && index < len(currentImages) {
				imageToDelete := currentImages[index]

				if err := utils.DeleteCommunityImageFromCloudinary(imageToDelete.ImageURL); err != nil {
					fmt.Printf("Failed to delete image from Cloudinary: %v\n", err)
				}

				if err := tx.Delete(&imageToDelete).Error; err != nil {
					tx.Rollback()
					c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to delete image"})
					return
				}
			}
		}

		var remainingImages []models.CommunityPostImage
		tx.Where("community_post_id = ?", post.ID).
			Order("position ASC").
			Find(&remainingImages)

		for i, img := range remainingImages {
			img.Position = i
			if err := tx.Save(&img).Error; err != nil {
				tx.Rollback()
				c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to reorder images"})
				return
			}
		}
	}

	newImages := form.File["new_images"]

	if len(newImages) > 0 {
		var currentImageCount int64
		tx.Model(&models.CommunityPostImage{}).
			Where("community_post_id = ?", post.ID).
			Count(&currentImageCount)

		if int(currentImageCount)+len(newImages) > 5 {
			tx.Rollback()
			c.JSON(http.StatusBadRequest, gin.H{"error": "Maximum 5 images allowed"})
			return
		}

		var maxPosition int
		var lastImage models.CommunityPostImage
		if err := tx.Where("community_post_id = ?", post.ID).
			Order("position DESC").
			First(&lastImage).Error; err == nil {
			maxPosition = lastImage.Position
		} else {
			maxPosition = -1
		}

		for i, imageHeader := range newImages {
			imageFile, err := imageHeader.Open()
			if err != nil {
				tx.Rollback()
				c.JSON(http.StatusBadRequest, gin.H{"error": fmt.Sprintf("Failed to open image %d", i+1)})
				return
			}
			defer imageFile.Close()

			if imageHeader.Size > 5*1024*1024 {
				tx.Rollback()
				c.JSON(http.StatusBadRequest, gin.H{"error": fmt.Sprintf("Image %d must be less than 5MB", i+1)})
				return
			}

			imageData, err := io.ReadAll(imageFile)
			if err != nil {
				tx.Rollback()
				c.JSON(http.StatusInternalServerError, gin.H{"error": fmt.Sprintf("Failed to read image %d", i+1)})
				return
			}

			imageURL, err := utils.UploadCommunityImageToCloudinary(imageData, fmt.Sprint(userID))
			if err != nil {
				tx.Rollback()
				c.JSON(http.StatusInternalServerError, gin.H{"error": fmt.Sprintf("Failed to upload image %d: %v", i+1, err)})
				return
			}

			newImage := models.CommunityPostImage{
				CommunityPostID: post.ID,
				ImageURL:        imageURL,
				Position:        maxPosition + 1 + i,
			}

			if err := tx.Create(&newImage).Error; err != nil {
				tx.Rollback()
				c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to save image record"})
				return
			}
		}
	}

	if err := tx.Save(&post).Error; err != nil {
		tx.Rollback()
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to update post"})
		return
	}

	if err := tx.Commit().Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to commit changes"})
		return
	}

	var images []models.CommunityPostImage
	config.DB.Where("community_post_id = ?", post.ID).
		Order("position ASC").
		Find(&images)

	config.DB.Preload("User").First(&post, post.ID)

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"message": "Post updated successfully",
		"post": gin.H{
			"id":             post.ID,
			"user_id":        post.UserID,
			"content":        post.Content,
			"audio_url":      post.AudioURL,
			"duration":       post.Duration,
			"images":         images,
			"likes_count":    post.LikesCount,
			"comments_count": post.CommentsCount,
			"updated_at":     post.UpdatedAt,
			"user":           post.User,
		},
	})
}

func DeleteCommunityPost(c *gin.Context) {
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
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid user ID"})
		return
	}

	postID := c.Param("id")

	var post models.CommunityPost
	if err := config.DB.Where("id = ? AND user_id = ?", postID, userID).First(&post).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			c.JSON(http.StatusNotFound, gin.H{"error": "Post not found or unauthorized"})
		} else {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Database error"})
		}
		return
	}

	config.DB.Where("community_post_id = ?", post.ID).Delete(&models.CommunityPostImage{})
	config.DB.Where("community_post_id = ?", post.ID).Delete(&models.CommunityPostLike{})

	var commentIDs []uint
	config.DB.Model(&models.CommunityPostComment{}).
		Where("community_post_id = ?", post.ID).
		Pluck("id", &commentIDs)

	if len(commentIDs) > 0 {
		config.DB.Where("comment_id IN ?", commentIDs).Delete(&models.CommunityCommentLike{})
	}

	config.DB.Where("community_post_id = ?", post.ID).Delete(&models.CommunityPostComment{})

	if err := config.DB.Delete(&post).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to delete post"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"message": "Post deleted successfully",
		"id":      post.ID,
	})
}

func ToggleCommunityPostLike(c *gin.Context) {
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
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid user ID"})
		return
	}

	postID := c.Param("id")

	var post models.CommunityPost
	if err := config.DB.First(&post, postID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Post not found"})
		return
	}

	var hidden models.HiddenUser
	err := config.DB.Where("user_id = ? AND hidden_user_id = ?", post.UserID, userID).First(&hidden).Error
	if err == nil {
		c.JSON(http.StatusForbidden, gin.H{
			"error":         "You cannot interact with this content",
			"is_restricted": true,
		})
		return
	}

	tx := config.DB.Begin()

	var like models.CommunityPostLike
	err = tx.Where("community_post_id = ? AND user_id = ?", postID, userID).First(&like).Error

	if err == gorm.ErrRecordNotFound {
		like = models.CommunityPostLike{
			CommunityPostID: post.ID,
			UserID:          userID,
		}

		if err := tx.Create(&like).Error; err != nil {
			tx.Rollback()
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to like post"})
			return
		}

		if err := tx.Model(&post).Update("likes_count", gorm.Expr("likes_count + ?", 1)).Error; err != nil {
			tx.Rollback()
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to update likes count"})
			return
		}

		tx.Commit()
		config.DB.First(&post, postID)

		c.JSON(http.StatusOK, gin.H{
			"success":     true,
			"liked":       true,
			"likes_count": post.LikesCount,
			"message":     "Post liked successfully",
		})
	} else if err != nil {
		tx.Rollback()
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Database error"})
	} else {
		if err := tx.Delete(&like).Error; err != nil {
			tx.Rollback()
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to unlike post"})
			return
		}

		if err := tx.Model(&post).Update("likes_count", gorm.Expr("likes_count - ?", 1)).Error; err != nil {
			tx.Rollback()
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to update likes count"})
			return
		}

		tx.Commit()
		config.DB.First(&post, postID)

		c.JSON(http.StatusOK, gin.H{
			"success":     true,
			"liked":       false,
			"likes_count": post.LikesCount,
			"message":     "Post unliked successfully",
		})
	}
}

func CheckCommunityPostLikeStatus(c *gin.Context) {
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
	}

	postID := c.Param("id")

	var like models.CommunityPostLike
	err := config.DB.Where("community_post_id = ? AND user_id = ?", postID, userID).First(&like).Error

	c.JSON(http.StatusOK, gin.H{
		"liked": err == nil,
	})
}

func CreateCommunityPostComment(c *gin.Context) {
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
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid user ID"})
		return
	}

	postID := c.Param("id")

	var post models.CommunityPost
	if err := db.First(&post, postID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Post not found"})
		return
	}

	var hidden models.HiddenUser
	err := db.Where("user_id = ? AND hidden_user_id = ?", post.UserID, userID).First(&hidden).Error
	if err == nil {
		c.JSON(http.StatusForbidden, gin.H{
			"error":         "You cannot interact with this content",
			"is_restricted": true,
		})
		return
	}

	var body struct {
		Content       string `json:"content" binding:"required"`
		ParentID      *uint  `json:"parent_id"`
		ReplyToUserID *uint  `json:"reply_to_user_id"`
	}

	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Content is required"})
		return
	}

	content := strings.TrimSpace(body.Content)
	if content == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Content cannot be empty"})
		return
	}

	if body.ParentID != nil {
		var parent models.CommunityPostComment
		if err := db.
			Where("id = ? AND community_post_id = ?", *body.ParentID, post.ID).
			First(&parent).Error; err != nil {

			c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid parent comment"})
			return
		}

		var parentHidden models.HiddenUser
		err := db.Where("user_id = ? AND hidden_user_id = ?", parent.UserID, userID).First(&parentHidden).Error
		if err == nil {
			c.JSON(http.StatusForbidden, gin.H{
				"error":         "You cannot reply to this comment",
				"is_restricted": true,
			})
			return
		}
	}

	if body.ReplyToUserID != nil {
		var user models.User
		if err := db.First(&user, *body.ReplyToUserID).Error; err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid reply user"})
			return
		}

		var replyHidden models.HiddenUser
		err := db.Where("user_id = ? AND hidden_user_id = ?", *body.ReplyToUserID, userID).First(&replyHidden).Error
		if err == nil {
			c.JSON(http.StatusForbidden, gin.H{
				"error":         "You cannot reply to this user",
				"is_restricted": true,
			})
			return
		}
	}

	comment := models.CommunityPostComment{
		CommunityPostID: post.ID,
		UserID:          userID,
		Content:         content,
		ParentID:        body.ParentID,
		ReplyToUserID:   body.ReplyToUserID,
		LikesCount:      0,
	}

	if err := db.Create(&comment).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to create comment"})
		return
	}

	db.Model(&post).
		Update("comments_count", gorm.Expr("comments_count + 1"))

	db.Preload("User").
		Preload("ReplyToUser").
		First(&comment, comment.ID)

	// Send notifications
	notificationService := services.NewNotificationService(db)
	go func() {
		// If this is a reply/mention, notify the mentioned user
		if body.ParentID != nil && body.ReplyToUserID != nil {
			var parentComment models.CommunityPostComment
			if err := db.First(&parentComment, *body.ParentID).Error; err == nil {
				if err := notificationService.NotifyCommunityPostCommentReply(&parentComment, &comment, comment.User, &post); err != nil {
					log.Printf("⚠️ Failed to send community comment reply notification: %v", err)
				}
			}
		} else {
			// Regular comment - notify post owner
			if err := notificationService.NotifyNewCommunityPostComment(&post, &comment, comment.User); err != nil {
				log.Printf("⚠️ Failed to send community comment notification: %v", err)
			}
		}
	}()

	c.JSON(http.StatusCreated, gin.H{
		"success": true,
		"message": "Comment created successfully",
		"comment": comment,
	})
}

func GetCommunityPostComments(c *gin.Context) {
	postID := c.Param("id")

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
	if page < 1 {
		page = 1
	}
	if limit < 1 {
		limit = 20
	}
	offset := (page - 1) * limit

	db := config.DB

	var blockedBy []uint
	var err error
	if userID > 0 {
		blockedBy, err = GetUsersWhoHidMe(db, userID)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch hidden relations"})
			return
		}
	}

	query := db.Where("community_post_id = ? AND parent_id IS NULL", postID)
	if len(blockedBy) > 0 {
		query = query.Where("user_id NOT IN ?", blockedBy)
	}

	var comments []models.CommunityPostComment
	if err := query.
		Preload("User").
		Order("created_at DESC").
		Limit(limit).
		Offset(offset).
		Find(&comments).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch comments"})
		return
	}

	var likedCommentIDs []uint
	if userID > 0 {
		db.Model(&models.CommunityCommentLike{}).
			Where("user_id = ?", userID).
			Pluck("comment_id", &likedCommentIDs)
	}

	likedMap := make(map[uint]bool)
	for _, id := range likedCommentIDs {
		likedMap[id] = true
	}

	type CommentResponse struct {
		models.CommunityPostComment
		IsLiked      bool                     `json:"is_liked"`
		RepliesCount int                      `json:"replies_count"`
		Replies      []map[string]interface{} `json:"replies"`
	}

	var response []CommentResponse

	for _, comment := range comments {
		var allReplies []models.CommunityPostComment
		rawQuery := `
            WITH RECURSIVE reply_tree AS (
                SELECT * FROM community_post_comments
                WHERE parent_id = ? AND deleted_at IS NULL
        `
		args := []interface{}{comment.ID}

		if len(blockedBy) > 0 {
			rawQuery += " AND user_id NOT IN ?"
			args = append(args, blockedBy)
		}

		rawQuery += `
                UNION ALL
                SELECT c.* FROM community_post_comments c
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
                SELECT * FROM community_post_comments
                WHERE parent_id = ? AND deleted_at IS NULL
        `
		countArgs := []interface{}{comment.ID}

		if len(blockedBy) > 0 {
			countQuery += " AND user_id NOT IN ?"
			countArgs = append(countArgs, blockedBy)
		}

		countQuery += `
                UNION ALL
                SELECT c.* FROM community_post_comments c
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
			CommunityPostComment: comment,
			IsLiked:              likedMap[comment.ID],
			RepliesCount:         int(repliesCount),
			Replies:              formattedReplies,
		})
	}

	totalQuery := db.Model(&models.CommunityPostComment{}).
		Where("community_post_id = ? AND parent_id IS NULL", postID)
	if len(blockedBy) > 0 {
		totalQuery = totalQuery.Where("user_id NOT IN ?", blockedBy)
	}

	var total int64
	totalQuery.Count(&total)

	c.JSON(http.StatusOK, gin.H{
		"success":  true,
		"comments": response,
		"page":     page,
		"limit":    limit,
		"total":    total,
		"has_more": offset+len(comments) < int(total),
	})
}

func DeleteCommunityPostComment(c *gin.Context) {
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
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid user ID"})
		return
	}

	commentID, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid comment ID"})
		return
	}

	var comment models.CommunityPostComment
	if err := db.First(&comment, commentID).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			c.JSON(http.StatusNotFound, gin.H{"error": "Comment not found"})
		} else {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Database error"})
		}
		return
	}

	isCommentOwner := comment.UserID == userID

	isParentOwner := false
	if comment.ParentID != nil {
		var parent models.CommunityPostComment
		if err := db.First(&parent, *comment.ParentID).Error; err == nil {
			isParentOwner = parent.UserID == userID
		}
	}

	isPostOwner := false
	var post models.CommunityPost
	if err := db.
		Select("id", "user_id").
		First(&post, comment.CommunityPostID).Error; err == nil {
		isPostOwner = post.UserID == userID
	}

	if !isCommentOwner && !isParentOwner && !isPostOwner {
		c.JSON(http.StatusForbidden, gin.H{
			"error": "You are not allowed to delete this comment",
		})
		return
	}

	var replyIDs []uint
	db.Model(&models.CommunityPostComment{}).
		Where("parent_id = ?", comment.ID).
		Pluck("id", &replyIDs)

	if len(replyIDs) > 0 {
		db.Where("comment_id IN ?", replyIDs).
			Delete(&models.CommunityCommentLike{})
	}

	db.Where("parent_id = ?", comment.ID).
		Delete(&models.CommunityPostComment{})

	db.Where("comment_id = ?", comment.ID).
		Delete(&models.CommunityCommentLike{})

	if err := db.Delete(&comment).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to delete comment"})
		return
	}

	db.Model(&models.CommunityPost{}).
		Where("id = ?", comment.CommunityPostID).
		Update("comments_count", gorm.Expr("comments_count - 1"))

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"message": "Comment deleted successfully",
		"id":      comment.ID,
	})
}

func ToggleCommunityCommentLike(c *gin.Context) {
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
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid user ID"})
		return
	}

	commentID := c.Param("id")

	var comment models.CommunityPostComment
	if err := config.DB.First(&comment, commentID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Comment not found"})
		return
	}

	var hidden models.HiddenUser
	err := config.DB.Where("user_id = ? AND hidden_user_id = ?", comment.UserID, userID).First(&hidden).Error
	if err == nil {
		c.JSON(http.StatusForbidden, gin.H{
			"error":         "You cannot interact with this content",
			"is_restricted": true,
		})
		return
	}

	tx := config.DB.Begin()

	var like models.CommunityCommentLike
	err = tx.Where("comment_id = ? AND user_id = ?", commentID, userID).First(&like).Error

	if err == gorm.ErrRecordNotFound {
		like = models.CommunityCommentLike{
			CommentID: comment.ID,
			UserID:    userID,
		}

		if err := tx.Create(&like).Error; err != nil {
			tx.Rollback()
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to like comment"})
			return
		}

		if err := tx.Model(&comment).Update("likes_count", gorm.Expr("likes_count + ?", 1)).Error; err != nil {
			tx.Rollback()
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to update likes count"})
			return
		}

		tx.Commit()
		config.DB.First(&comment, commentID)

		c.JSON(http.StatusOK, gin.H{
			"success":     true,
			"liked":       true,
			"likes_count": comment.LikesCount,
			"message":     "Comment liked successfully",
		})
	} else if err != nil {
		tx.Rollback()
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Database error"})
	} else {
		if err := tx.Delete(&like).Error; err != nil {
			tx.Rollback()
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to unlike comment"})
			return
		}

		if err := tx.Model(&comment).Update("likes_count", gorm.Expr("likes_count - ?", 1)).Error; err != nil {
			tx.Rollback()
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to update likes count"})
			return
		}

		tx.Commit()
		config.DB.First(&comment, commentID)

		c.JSON(http.StatusOK, gin.H{
			"success":     true,
			"liked":       false,
			"likes_count": comment.LikesCount,
			"message":     "Comment unliked successfully",
		})
	}
}

func CheckCommunityCommentLikeStatus(c *gin.Context) {
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
	}

	commentID := c.Param("id")

	var like models.CommunityCommentLike
	err := config.DB.Where("comment_id = ? AND user_id = ?", commentID, userID).First(&like).Error

	c.JSON(http.StatusOK, gin.H{
		"liked": err == nil,
	})
}

func GetCommunityCommentReplies(c *gin.Context) {
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

	var replies []models.CommunityPostComment

	rawQuery := `
        WITH RECURSIVE reply_tree AS (
            SELECT * FROM community_post_comments
            WHERE parent_id = ? AND deleted_at IS NULL
    `
	args := []interface{}{commentID}

	if len(blockedBy) > 0 {
		rawQuery += " AND user_id NOT IN ?"
		args = append(args, blockedBy)
	}

	rawQuery += `
            UNION ALL
            SELECT c.* FROM community_post_comments c
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
		db.Model(&models.CommunityCommentLike{}).
			Where("user_id = ?", userID).
			Pluck("comment_id", &likedCommentIDs)
	}

	likedMap := make(map[uint]bool)
	for _, id := range likedCommentIDs {
		likedMap[id] = true
	}

	type ReplyResponse struct {
		models.CommunityPostComment
		IsLiked bool `json:"is_liked"`
	}

	var response []ReplyResponse
	for _, reply := range replies {
		response = append(response, ReplyResponse{
			CommunityPostComment: reply,
			IsLiked:              likedMap[reply.ID],
		})
	}

	countQuery := `
        WITH RECURSIVE reply_tree AS (
            SELECT * FROM community_post_comments
            WHERE parent_id = ? AND deleted_at IS NULL
    `
	countArgs := []interface{}{commentID}

	if len(blockedBy) > 0 {
		countQuery += " AND user_id NOT IN ?"
		countArgs = append(countArgs, blockedBy)
	}

	countQuery += `
            UNION ALL
            SELECT c.* FROM community_post_comments c
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
		"success":  true,
		"replies":  response,
		"page":     page,
		"limit":    limit,
		"total":    total,
		"has_more": offset+len(replies) < int(total),
	})
}
