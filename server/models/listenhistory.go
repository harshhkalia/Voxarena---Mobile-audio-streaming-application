package models

import (
	"time"

	"gorm.io/gorm"
)

type ListenHistory struct {
	ID        uint           `gorm:"primarykey" json:"id"`
	CreatedAt time.Time      `json:"created_at"`
	UpdatedAt time.Time      `json:"updated_at"`
	DeletedAt gorm.DeletedAt `gorm:"index" json:"-"`

	UserID uint `gorm:"not null;index:idx_user_room;index:idx_user_listened_at" json:"user_id"`
	User   User `gorm:"foreignKey:UserID" json:"user,omitempty"`
	RoomID uint `gorm:"not null;index:idx_user_room;index:idx_room_listened_at" json:"room_id"`
	Room   Room `gorm:"foreignKey:RoomID" json:"room,omitempty"`

	ListenedAt     time.Time `gorm:"not null;index:idx_user_listened_at;index:idx_room_listened_at" json:"listened_at"`
	Duration       int       `json:"duration"`
	CompletionRate float64   `json:"completion_rate"`

	IsCompleted  bool `gorm:"default:false" json:"is_completed"`
	IsSkipped    bool `gorm:"default:false" json:"is_skipped"`
	LastPosition int  `json:"last_position"`
}

func (ListenHistory) TableName() string {
	return "listen_history"
}
