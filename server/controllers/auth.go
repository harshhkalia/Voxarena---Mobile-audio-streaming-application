package controllers

import (
	"encoding/json"
	"io"
	"net/http"
	"voxarena_server/config"
	"voxarena_server/dto"
	"voxarena_server/models"
	"voxarena_server/utils"

	"github.com/gin-gonic/gin"
)

func GoogleAuth(c *gin.Context) {
	var req dto.GoogleAuthRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid request"})
		return
	}

	resp, err := http.Get("https://oauth2.googleapis.com/tokeninfo?id_token=" + req.IDToken)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Failed to verify Google token"})
		return
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid Google token"})
		return
	}

	body, _ := io.ReadAll(resp.Body)
	var tokenInfo struct {
		Sub           string `json:"sub"`
		Email         string `json:"email"`
		EmailVerified string `json:"email_verified"`
	}

	if err := json.Unmarshal(body, &tokenInfo); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to parse Google response"})
		return
	}

	if tokenInfo.Sub != req.GoogleID {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Google ID mismatch"})
		return
	}

	var user models.User
	result := config.DB.Where("google_id = ?", req.GoogleID).First(&user)

	if result.Error != nil {
		profilePicURL, err := utils.UploadProfilePicFromURL(req.ProfilePic, req.GoogleID)
		if err != nil || profilePicURL == "" {
			profilePicURL = req.ProfilePic
		}

		user = models.User{
			GoogleID:   req.GoogleID,
			Email:      req.Email,
			FullName:   req.FullName,
			ProfilePic: profilePicURL,
			Role:       "user",
		}

		if err := config.DB.Create(&user).Error; err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to create user"})
			return
		}
	}

	token, err := utils.GenerateJWT(user.ID, user.Email, user.Role)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to generate token"})
		return
	}

	c.JSON(http.StatusOK, dto.AuthResponse{
		Token: token,
		User: dto.UserProfile{
			ID:         user.ID,
			Email:      user.Email,
			FullName:   user.FullName,
			ProfilePic: user.ProfilePic,
			Role:       user.Role,
		},
		Message: "Login successful",
	})
}

func GetMe(c *gin.Context) {
	userID, exists := c.Get("userID")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}

	var user models.User
	if err := config.DB.First(&user, userID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "User not found"})
		return
	}

	c.JSON(http.StatusOK, dto.UserProfile{
		ID:         user.ID,
		Email:      user.Email,
		FullName:   user.FullName,
		ProfilePic: user.ProfilePic,
		Role:       user.Role,
	})
}

func GetUserProfileByID(c *gin.Context) {
	db := config.DB

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

	if currentUserID > 0 {
		var hidden models.HiddenUser
		err := db.Where(
			"user_id = ? AND hidden_user_id = ?",
			targetUserID,
			currentUserID,
		).First(&hidden).Error

		if err == nil {
			c.JSON(http.StatusNotFound, gin.H{
				"error": "User not found",
			})
			return
		}
	}

	var user models.User
	if err := db.First(&user, targetUserID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{
			"error": "User not found",
		})
		return
	}

	isFollowing := false

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"user": dto.UserProfile{
			ID:             user.ID,
			Email:          user.Email,
			FullName:       user.FullName,
			Username:       user.Username,
			ProfilePic:     user.ProfilePic,
			Bio:            user.Bio,
			IsVerified:     user.IsVerified,
			FollowersCount: user.FollowersCount,
			Role:           user.Role,
		},
		"is_following": isFollowing,
	})
}
