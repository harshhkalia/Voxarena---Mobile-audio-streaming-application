package controllers

import (
	"fmt"
	"io"
	"net/http"
	"strings"
	"voxarena_server/config"
	"voxarena_server/models"
	"voxarena_server/utils"

	"github.com/gin-gonic/gin"
)

func GetUserProfile(c *gin.Context) {
	userID, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}

	var user models.User
	result := config.DB.First(&user, userID)
	
	if result.Error != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "User not found"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"user": gin.H{
			"id":                user.ID,
			"email":             user.Email,
			"username":          user.Username,
			"full_name":         user.FullName,
			"profile_pic":       user.ProfilePic,
			"bio":               user.Bio,
			"followers_count":   user.FollowersCount,
			"following_count":   user.FollowingCount,
			"total_gifts_value": user.TotalGiftsValue,
			"is_verified":       user.IsVerified,
			"role":              user.Role,
			"created_at":        user.CreatedAt,
			"last_login_at":     user.LastLoginAt,
		},
	})
}

func UploadProfileImage(c *gin.Context) {
	userID, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}

	file, header, err := c.Request.FormFile("profile_pic")
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "No image file provided",
			"details": err.Error(),
		})
		return
	}
	defer file.Close()

	if header.Size > 5*1024*1024 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "File size must be less than 5MB"})
		return
	}

	contentType := header.Header.Get("Content-Type")
	if !strings.HasPrefix(contentType, "image/") {
		c.JSON(http.StatusBadRequest, gin.H{"error": "File must be an image"})
		return
	}

	fileData, err := io.ReadAll(file)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to read file"})
		return
	}

	imageURL, err := utils.UploadProfilePicToCloudinary(fileData, fmt.Sprint(userID))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": fmt.Sprintf("Upload failed: %v", err)})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"url":     imageURL,
	})
}

func UpdateUserProfile(c *gin.Context) {
	userID, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}

	var input struct {
		Username   string `json:"username"`
		FullName   string `json:"full_name"`
		Bio        *string `json:"bio"`
		ProfilePic string `json:"profile_pic"`
	}

	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid input"})
		return
	}

	var user models.User
	if err := config.DB.First(&user, userID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "User not found"})
		return
	}

	if input.Username != "" {
		newUsername := strings.TrimSpace(strings.ToLower(input.Username))

		if len(newUsername) < 3 {
			c.JSON(http.StatusBadRequest, gin.H{
				"error": "Username must be at least 3 characters long",
			})
			return
		}

		if len(newUsername) > 30 {
			c.JSON(http.StatusBadRequest, gin.H{
				"error": "Username must be less than 30 characters",
			})
			return
		}

		for _, char := range newUsername {
			if !((char >= 'a' && char <= 'z') || (char >= '0' && char <= '9') || char == '_') {
				c.JSON(http.StatusBadRequest, gin.H{
					"error": "Username can only contain letters, numbers, and underscores",
				})
				return
			}
		}

		var existingUser models.User
		result := config.DB.Where("username = ? AND id != ?", newUsername, userID).First(&existingUser)
		
		if result.Error == nil {
			c.JSON(http.StatusConflict, gin.H{
				"error": "Username is already taken",
			})
			return
		}

		user.Username = newUsername
	}

	if input.FullName != "" {
		user.FullName = strings.TrimSpace(input.FullName)
	}
	
	if input.Bio != nil {
		user.Bio = strings.TrimSpace(*input.Bio)
	}
	
	user.ProfilePic = input.ProfilePic

	if err := config.DB.Save(&user).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error": "Failed to update profile",
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"message": "Profile updated successfully",
		"user": gin.H{
			"id":          user.ID,
			"email":       user.Email,
			"username":    user.Username,
			"full_name":   user.FullName,
			"profile_pic": user.ProfilePic,
			"bio":         user.Bio,
		},
	})
}