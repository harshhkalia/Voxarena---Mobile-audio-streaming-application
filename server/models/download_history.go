package models

import (
	"time"

	"gorm.io/gorm"
)

type DownloadHistory struct {
	ID        uint           `gorm:"primarykey" json:"id"`
	CreatedAt time.Time      `json:"created_at"`
	UpdatedAt time.Time      `json:"updated_at"`
	DeletedAt gorm.DeletedAt `gorm:"index" json:"-"`

	UserID uint `gorm:"not null;index:idx_user_download;index:idx_user_downloaded_at" json:"user_id"`
	User   User `gorm:"foreignKey:UserID" json:"user,omitempty"`

	RoomID uint `gorm:"not null;index:idx_user_download;index:idx_room_downloaded_at" json:"room_id"`
	Room   Room `gorm:"foreignKey:RoomID" json:"room,omitempty"`

	DownloadedAt time.Time `gorm:"not null;index:idx_user_downloaded_at;index:idx_room_downloaded_at" json:"downloaded_at"`

	FileName     string `json:"file_name,omitempty"`
	FileSize     int64  `json:"file_size,omitempty"`
	DownloadPath string `json:"download_path,omitempty"`
}

func (DownloadHistory) TableName() string {
	return "download_history"
}
