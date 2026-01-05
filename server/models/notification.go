package models

import (
	"time"

	"gorm.io/gorm"
)

type NotificationType string

const (
	NotificationTypeFollow         NotificationType = "follow"
	NotificationTypeLike           NotificationType = "like"
	NotificationTypeComment        NotificationType = "comment"
	NotificationTypeCommentLike    NotificationType = "comment_like"
	NotificationTypeNewRoom        NotificationType = "new_room"
	NotificationTypeRoomLive       NotificationType = "room_live"
	NotificationTypeCommunityPost  NotificationType = "community_post"
	NotificationTypeCommunityLike  NotificationType = "community_post_like"
	NotificationTypeCommunityComment NotificationType = "community_comment"
	NotificationTypeGift           NotificationType = "gift"
	NotificationTypeMention        NotificationType = "mention"
	NotificationTypeSystem         NotificationType = "system"
)

type Notification struct {
	ID          uint             `gorm:"primarykey" json:"id"`
	CreatedAt   time.Time        `json:"created_at"`
	UpdatedAt   time.Time        `json:"updated_at"`
	DeletedAt   gorm.DeletedAt   `gorm:"index" json:"-"`
	UserID      uint             `gorm:"not null;index" json:"user_id"`          
	User        User             `gorm:"foreignKey:UserID" json:"-"`
	ActorID     uint             `gorm:"index" json:"actor_id"`                  
	Actor       User             `gorm:"foreignKey:ActorID" json:"actor"`
	Type        NotificationType `gorm:"type:varchar(50);not null;index" json:"type"`
	Title       string           `gorm:"not null" json:"title"`
	Message     string           `json:"message"`
	ExtraData   string           `json:"extra_data,omitempty"`                   // For storing original comment text on replies
	ReferenceID *uint            `gorm:"index" json:"reference_id,omitempty"`    
	ReferenceType string         `json:"reference_type,omitempty"`               
	ImageURL    string           `json:"image_url,omitempty"`                    
	ActionURL   string           `json:"action_url,omitempty"`                   
	IsRead      bool             `gorm:"default:false;index" json:"is_read"`
	ReadAt      *time.Time       `json:"read_at,omitempty"`
}

func (Notification) TableName() string {
	return "notifications"
}

func (n *Notification) MarkAsRead(tx *gorm.DB) error {
	now := time.Now()
	return tx.Model(n).Updates(map[string]interface{}{
		"is_read": true,
		"read_at": now,
	}).Error
}

func MarkAllAsRead(tx *gorm.DB, userID uint) error {
	now := time.Now()
	return tx.Model(&Notification{}).
		Where("user_id = ? AND is_read = ?", userID, false).
		Updates(map[string]interface{}{
			"is_read": true,
			"read_at": now,
		}).Error
}

func GetUnreadCount(tx *gorm.DB, userID uint) (int64, error) {
	var count int64
	err := tx.Model(&Notification{}).
		Where("user_id = ? AND is_read = ?", userID, false).
		Count(&count).Error
	return count, err
}
