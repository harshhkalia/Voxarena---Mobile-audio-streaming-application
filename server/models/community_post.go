package models

import (
	"time"

	"gorm.io/gorm"
)

type CommunityPost struct {
	ID            uint           `gorm:"primarykey" json:"id"`
	CreatedAt     time.Time      `json:"created_at"`
	UpdatedAt     time.Time      `json:"updated_at"`
	DeletedAt     gorm.DeletedAt `gorm:"index" json:"-"`
	UserID        uint           `gorm:"not null;index" json:"user_id"`
	User          User           `gorm:"foreignKey:UserID" json:"user"`
	Content       string         `gorm:"type:text" json:"content"`
	AudioURL      string         `json:"audio_url"`
	Duration      int            `json:"duration"`
	LikesCount    int            `gorm:"default:0" json:"likes_count"`
	CommentsCount int            `gorm:"default:0" json:"comments_count"`
}

type CommunityPostImage struct {
	ID              uint           `gorm:"primarykey" json:"id"`
	CreatedAt       time.Time      `json:"created_at"`
	DeletedAt       gorm.DeletedAt `gorm:"index" json:"-"`
	CommunityPostID uint           `gorm:"not null;index" json:"community_post_id"`
	ImageURL        string         `gorm:"not null" json:"image_url"`
	Position        int            `gorm:"not null" json:"position"`
}

type CommunityPostLike struct {
	ID              uint           `gorm:"primarykey" json:"id"`
	CreatedAt       time.Time      `json:"created_at"`
	DeletedAt       gorm.DeletedAt `gorm:"index" json:"-"`
	CommunityPostID uint           `gorm:"not null;index:idx_post_user" json:"community_post_id"`
	UserID          uint           `gorm:"not null;index:idx_post_user" json:"user_id"`
	User            User           `gorm:"foreignKey:UserID" json:"user"`
}

type CommunityPostComment struct {
	ID              uint           `gorm:"primarykey" json:"id"`
	CreatedAt       time.Time      `json:"created_at"`
	UpdatedAt       time.Time      `json:"updated_at"`
	DeletedAt       gorm.DeletedAt `gorm:"index" json:"-"`
	CommunityPostID uint           `gorm:"not null;index" json:"community_post_id"`
	UserID          uint           `gorm:"not null;index" json:"user_id"`
	User            User           `gorm:"foreignKey:UserID" json:"user"`
	Content         string         `gorm:"type:text;not null" json:"content"`
	LikesCount      int            `gorm:"default:0" json:"likes_count"`

	ReplyToUserID *uint                  `gorm:"index" json:"reply_to_user_id"`
	ReplyToUser   *User                  `gorm:"foreignKey:ReplyToUserID" json:"reply_to_user,omitempty"`
	ParentID      *uint                  `gorm:"index" json:"parent_id"`
	Replies       []CommunityPostComment `gorm:"foreignKey:ParentID" json:"replies,omitempty"`
}

type CommunityCommentLike struct {
	ID        uint           `gorm:"primarykey" json:"id"`
	CreatedAt time.Time      `json:"created_at"`
	DeletedAt gorm.DeletedAt `gorm:"index" json:"-"`
	CommentID uint           `gorm:"not null;index:idx_comment_user" json:"comment_id"`
	UserID    uint           `gorm:"not null;index:idx_comment_user" json:"user_id"`
	User      User           `gorm:"foreignKey:UserID" json:"user"`
}

func (CommunityPost) TableName() string {
	return "community_posts"
}

func (CommunityPostImage) TableName() string {
	return "community_post_images"
}

func (CommunityPostLike) TableName() string {
	return "community_post_likes"
}

func (CommunityPostComment) TableName() string {
	return "community_post_comments"
}

func (CommunityCommentLike) TableName() string {
	return "community_comment_likes"
}

func (CommunityPostLike) AfterMigrate(tx *gorm.DB) error {
	return tx.Exec(`
		CREATE UNIQUE INDEX IF NOT EXISTS idx_unique_post_like 
		ON community_post_likes(community_post_id, user_id) 
		WHERE deleted_at IS NULL
	`).Error
}

func (CommunityCommentLike) AfterMigrate(tx *gorm.DB) error {
	return tx.Exec(`
		CREATE UNIQUE INDEX IF NOT EXISTS idx_unique_comment_like 
		ON community_comment_likes(comment_id, user_id) 
		WHERE deleted_at IS NULL
	`).Error
}
