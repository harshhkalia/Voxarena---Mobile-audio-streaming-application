package services

import (
	"fmt"
	"log"

	"voxarena_server/models"
	"voxarena_server/websocket"

	"gorm.io/gorm"
)

type NotificationService struct {
	db *gorm.DB
}

func NewNotificationService(db *gorm.DB) *NotificationService {
	return &NotificationService{db: db}
}

func (ns *NotificationService) NotifyNewRoom(room *models.Room) error {
	var follows []models.Follow
	if err := ns.db.Where("following_id = ?", room.HostID).
		Find(&follows).Error; err != nil {
		return fmt.Errorf("failed to get followers: %w", err)
	}

	if len(follows) == 0 {
		log.Printf("No followers to notify for room %d", room.ID)
		return nil
	}

	var hiddenUsers []models.HiddenUser
	if err := ns.db.Where("user_id = ?", room.HostID).
		Find(&hiddenUsers).Error; err != nil {
		return fmt.Errorf("failed to get hidden users: %w", err)
	}

	hiddenSet := make(map[uint]struct{}, len(hiddenUsers))
	for _, hu := range hiddenUsers {
		hiddenSet[hu.HiddenUserID] = struct{}{}
	}

	var host models.User
	if err := ns.db.First(&host, room.HostID).Error; err != nil {
		return fmt.Errorf("failed to load host: %w", err)
	}

	notifications := make([]models.Notification, 0, len(follows))
	followerIDs := make([]uint, 0, len(follows))

	for _, follow := range follows {
		if _, isHidden := hiddenSet[follow.FollowerID]; isHidden {
			continue
		}

		notification := models.Notification{
			UserID:        follow.FollowerID,
			ActorID:       room.HostID,
			Type:          models.NotificationTypeNewRoom,
			Title:         fmt.Sprintf("%s uploaded a new audio", host.FullName),
			Message:       room.Title,
			ReferenceID:   &room.ID,
			ReferenceType: "room",
			ImageURL:      room.ThumbnailURL,
			ActionURL:     fmt.Sprintf("/rooms/%d", room.ID),
			IsRead:        false,
		}
		notifications = append(notifications, notification)
		followerIDs = append(followerIDs, follow.FollowerID)
	}

	if len(notifications) == 0 {
		log.Printf("No eligible followers to notify for room %d (all hidden)", room.ID)
		return nil
	}

	if err := ns.db.Create(&notifications).Error; err != nil {
		return fmt.Errorf("failed to create notifications: %w", err)
	}

	log.Printf("✓ Created %d notifications for room %d", len(notifications), room.ID)

	if websocket.GlobalHub != nil {
		for _, notification := range notifications {
			payload := map[string]interface{}{
				"type": "notification",
				"data": map[string]interface{}{
					"id":             notification.ID,
					"type":           notification.Type,
					"title":          notification.Title,
					"message":        notification.Message,
					"image_url":      notification.ImageURL,
					"action_url":     notification.ActionURL,
					"reference_id":   notification.ReferenceID,
					"reference_type": notification.ReferenceType,
					"is_read":        notification.IsRead,
					"created_at":     notification.CreatedAt,
					"actor": map[string]interface{}{
						"id":          host.ID,
						"full_name":   host.FullName,
						"username":    host.Username,
						"profile_pic": host.ProfilePic,
					},
				},
			}
			websocket.GlobalHub.SendToUsers([]uint{notification.UserID}, payload)
		}
		log.Printf("✓ Sent real-time notifications for room %d to %d followers", room.ID, len(notifications))
	}

	return nil
}

func (ns *NotificationService) NotifyNewComment(room *models.Room, comment *models.Comment, commentAuthor models.User) error {
	if comment.UserID == room.HostID {
		return nil
	}

	notification := models.Notification{
		UserID:        room.HostID,
		ActorID:       comment.UserID,
		Type:          models.NotificationTypeComment,
		Title:         fmt.Sprintf("@%s commented on your audio", commentAuthor.Username),
		Message:       comment.Content,
		ReferenceID:   &room.ID,
		ReferenceType: "room",
		ImageURL:      room.ThumbnailURL,
		ActionURL:     fmt.Sprintf("/rooms/%d", room.ID),
		IsRead:        false,
	}

	if err := ns.db.Create(&notification).Error; err != nil {
		return fmt.Errorf("failed to create comment notification: %w", err)
	}

	ns.sendRealtimeNotification(notification, commentAuthor)

	log.Printf("✓ Sent comment notification to room owner %d", room.HostID)
	return nil
}

func (ns *NotificationService) NotifyCommentReply(parentComment *models.Comment, reply *models.Comment, replier models.User, room *models.Room) error {
	if reply.UserID == parentComment.UserID {
		return nil
	}

	var roomHost models.User
	if err := ns.db.First(&roomHost, room.HostID).Error; err != nil {
		return fmt.Errorf("failed to load room host: %w", err)
	}

	notification := models.Notification{
		UserID:        parentComment.UserID,
		ActorID:       reply.UserID,
		Type:          models.NotificationTypeComment,
		Title:         fmt.Sprintf("@%s mentioned you in a comment", replier.Username),
		Message:       reply.Content,
		ExtraData:     parentComment.Content,
		ReferenceID:   &room.ID,
		ReferenceType: "room",
		ImageURL:      room.ThumbnailURL,
		ActionURL:     fmt.Sprintf("/rooms/%d", room.ID),
		IsRead:        false,
	}

	if err := ns.db.Create(&notification).Error; err != nil {
		return fmt.Errorf("failed to create reply notification: %w", err)
	}

	ns.sendRealtimeNotification(notification, replier)

	log.Printf("✓ Sent reply notification to comment author %d", parentComment.UserID)
	return nil
}

func (ns *NotificationService) sendRealtimeNotification(notification models.Notification, actor models.User) {
	if websocket.GlobalHub == nil {
		log.Println("⚠️ WebSocket hub not initialized")
		return
	}

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
				"id":          actor.ID,
				"full_name":   actor.FullName,
				"username":    actor.Username,
				"profile_pic": actor.ProfilePic,
			},
		},
	}
	websocket.GlobalHub.SendToUsers([]uint{notification.UserID}, payload)
}

func (ns *NotificationService) NotifyNewCommunityPostComment(post *models.CommunityPost, comment *models.CommunityPostComment, commentAuthor models.User) error {
	if comment.UserID == post.UserID {
		return nil
	}

	// Get first image URL if available
	var firstImage models.CommunityPostImage
	var imageURL string
	if err := ns.db.Where("community_post_id = ?", post.ID).
		Order("position ASC").
		First(&firstImage).Error; err == nil {
		imageURL = firstImage.ImageURL
	}

	notification := models.Notification{
		UserID:        post.UserID,
		ActorID:       comment.UserID,
		Type:          models.NotificationTypeCommunityComment,
		Title:         fmt.Sprintf("@%s commented on your post", commentAuthor.Username),
		Message:       comment.Content,
		ReferenceID:   &post.ID,
		ReferenceType: "post",
		ImageURL:      imageURL,
		ActionURL:     fmt.Sprintf("/profile/%d?postId=%d", post.UserID, post.ID),
		IsRead:        false,
	}

	if err := ns.db.Create(&notification).Error; err != nil {
		return fmt.Errorf("failed to create community comment notification: %w", err)
	}

	ns.sendRealtimeNotification(notification, commentAuthor)

	log.Printf("✓ Sent comment notification to post owner %d", post.UserID)
	return nil
}

func (ns *NotificationService) NotifyCommunityPostCommentReply(parentComment *models.CommunityPostComment, reply *models.CommunityPostComment, replier models.User, post *models.CommunityPost) error {
	if reply.UserID == parentComment.UserID {
		return nil
	}

	var postAuthor models.User
	if err := ns.db.First(&postAuthor, post.UserID).Error; err != nil {
		return fmt.Errorf("failed to load post author: %w", err)
	}

	// Get first image URL if available
	var firstImage models.CommunityPostImage
	var imageURL string
	if err := ns.db.Where("community_post_id = ?", post.ID).
		Order("position ASC").
		First(&firstImage).Error; err == nil {
		imageURL = firstImage.ImageURL
	}

	notification := models.Notification{
		UserID:        parentComment.UserID,
		ActorID:       reply.UserID,
		Type:          models.NotificationTypeCommunityComment,
		Title:         fmt.Sprintf("@%s mentioned you in a comment", replier.Username),
		Message:       reply.Content,
		ExtraData:     parentComment.Content,
		ReferenceID:   &post.ID,
		ReferenceType: "post",
		ImageURL:      imageURL,
		ActionURL:     fmt.Sprintf("/profile/%d?postId=%d", post.UserID, post.ID),
		IsRead:        false,
	}

	if err := ns.db.Create(&notification).Error; err != nil {
		return fmt.Errorf("failed to create community reply notification: %w", err)
	}

	ns.sendRealtimeNotification(notification, replier)

	log.Printf("✓ Sent community reply notification to comment author %d", parentComment.UserID)
	return nil
}

func (ns *NotificationService) NotifyNewCommunityPost(post *models.CommunityPost) error {
	var follows []models.Follow
	if err := ns.db.Where("following_id = ?", post.UserID).
		Find(&follows).Error; err != nil {
		return fmt.Errorf("failed to get followers: %w", err)
	}

	if len(follows) == 0 {
		log.Printf("No followers to notify for community post %d", post.ID)
		return nil
	}

	var hiddenUsers []models.HiddenUser
	if err := ns.db.Where("user_id = ?", post.UserID).
		Find(&hiddenUsers).Error; err != nil {
		return fmt.Errorf("failed to get hidden users: %w", err)
	}

	hiddenSet := make(map[uint]struct{}, len(hiddenUsers))
	for _, hu := range hiddenUsers {
		hiddenSet[hu.HiddenUserID] = struct{}{}
	}

	var author models.User
	if err := ns.db.First(&author, post.UserID).Error; err != nil {
		return fmt.Errorf("failed to load author: %w", err)
	}

	notifications := make([]models.Notification, 0, len(follows))
	followerIDs := make([]uint, 0, len(follows))

	var firstImage models.CommunityPostImage
	var imageURL string
	if err := ns.db.Where("community_post_id = ?", post.ID).
		Order("position ASC").
		First(&firstImage).Error; err == nil {
		imageURL = firstImage.ImageURL
	}

	for _, follow := range follows {
		if _, isHidden := hiddenSet[follow.FollowerID]; isHidden {
			continue
		}

		notification := models.Notification{
			UserID:        follow.FollowerID,
			ActorID:       post.UserID,
			Type:          models.NotificationTypeCommunityPost,
			Title:         fmt.Sprintf("%s created a new post", author.FullName),
			Message:       post.Content,
			ReferenceID:   &post.ID,
			ReferenceType: "post",
			ImageURL:      imageURL,
			ActionURL:     fmt.Sprintf("/profile/%d?postId=%d", post.UserID, post.ID),
			IsRead:        false,
		}
		notifications = append(notifications, notification)
		followerIDs = append(followerIDs, follow.FollowerID)
	}

	if len(notifications) == 0 {
		log.Printf("No eligible followers to notify for post %d (all hidden)", post.ID)
		return nil
	}

	if err := ns.db.Create(&notifications).Error; err != nil {
		return fmt.Errorf("failed to create notifications: %w", err)
	}

	log.Printf("✓ Created %d notifications for community post %d", len(notifications), post.ID)

	if websocket.GlobalHub != nil {
		for _, notification := range notifications {
			payload := map[string]interface{}{
				"type": "notification",
				"data": map[string]interface{}{
					"id":             notification.ID,
					"type":           notification.Type,
					"title":          notification.Title,
					"message":        notification.Message,
					"image_url":      notification.ImageURL,
					"action_url":     notification.ActionURL,
					"reference_id":   notification.ReferenceID,
					"reference_type": notification.ReferenceType,
					"is_read":        notification.IsRead,
					"created_at":     notification.CreatedAt,
					"actor": map[string]interface{}{
						"id":          author.ID,
						"full_name":   author.FullName,
						"username":    author.Username,
						"profile_pic": author.ProfilePic,
					},
				},
			}
			websocket.GlobalHub.SendToUsers([]uint{notification.UserID}, payload)
		}
		log.Printf("✓ Sent real-time notifications for post %d to %d followers", post.ID, len(notifications))
	}

	return nil
}
