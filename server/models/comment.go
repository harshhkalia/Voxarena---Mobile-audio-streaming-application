package models

import (
	"time"

	"gorm.io/gorm"
)

type Comment struct {
	ID            uint           `gorm:"primarykey" json:"id"`
	CreatedAt     time.Time      `json:"created_at"`
	UpdatedAt     time.Time      `json:"updated_at"`
	DeletedAt     gorm.DeletedAt `gorm:"index" json:"-"`
	Content       string         `gorm:"not null;type:text" json:"content"`
	RoomID        uint           `gorm:"not null;index" json:"room_id"`
	Room          Room           `gorm:"foreignKey:RoomID" json:"-"`
	UserID        uint           `gorm:"not null;index" json:"user_id"`
	User          User           `gorm:"foreignKey:UserID" json:"user"`
	ReplyToUserID *uint          `gorm:"index" json:"reply_to_user_id"`
	ReplyToUser   *User          `gorm:"foreignKey:ReplyToUserID" json:"reply_to_user,omitempty"`
	ParentID      *uint          `gorm:"index" json:"parent_id"`
	Replies       []Comment      `gorm:"foreignKey:ParentID" json:"replies,omitempty"`
	LikesCount    int            `gorm:"default:0" json:"likes_count"`
}

func (Comment) TableName() string {
	return "comments"
}

type CommentLike struct {
	ID        uint      `gorm:"primarykey" json:"id"`
	CreatedAt time.Time `json:"created_at"`

	CommentID uint    `gorm:"not null;index" json:"comment_id"`
	Comment   Comment `gorm:"foreignKey:CommentID" json:"-"`
	UserID    uint    `gorm:"not null;index" json:"user_id"`
	User      User    `gorm:"foreignKey:UserID" json:"-"`
}

func (CommentLike) TableName() string {
	return "comment_likes"
}
