package models

import (
	"time"

	"gorm.io/gorm"
)

type Room struct {
	ID            uint           `gorm:"primarykey" json:"id"`
	CreatedAt     time.Time      `json:"created_at"`
	UpdatedAt     time.Time      `json:"updated_at"`
	DeletedAt     gorm.DeletedAt `gorm:"index" json:"-"`
	Title         string         `gorm:"not null" json:"title"`
	Description   string         `json:"description"`
	Topic         string         `gorm:"not null" json:"topic"`
	AudioURL      string         `gorm:"not null" json:"audio_url"`
	ThumbnailURL  string         `json:"thumbnail_url"`
	Duration      int            `json:"duration"`
	HostID        uint           `gorm:"not null" json:"host_id"`
	Host          User           `gorm:"foreignKey:HostID" json:"host"`
	IsLive        bool           `gorm:"default:false" json:"is_live"`
	IsPrivate     bool           `gorm:"default:false" json:"is_private"`
	ListenerCount int            `gorm:"default:0" json:"listener_count"`
	TotalListens  int            `gorm:"default:0" json:"total_listens"`
	LikesCount    int            `gorm:"default:0" json:"likes_count"`
	ReportCount   int            `gorm:"default:0" json:"report_count"`
	IsHidden      bool           `gorm:"default:false" json:"is_hidden"`
	HiddenAt      *time.Time     `json:"hidden_at,omitempty"`
	HiddenReason  string         `json:"hidden_reason,omitempty"`
}

func (Room) TableName() string {
	return "rooms"
}

func (r *Room) IncrementListens(tx *gorm.DB) error {
	return tx.Model(r).Update("total_listens", gorm.Expr("total_listens + ?", 1)).Error
}
