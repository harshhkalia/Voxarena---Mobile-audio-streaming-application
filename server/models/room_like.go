package models

import (
	"time"
)

type RoomLike struct {
	ID        uint      `gorm:"primarykey" json:"id"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`

	UserID uint `gorm:"not null;uniqueIndex:idx_user_room_like" json:"user_id"`
	User   User `gorm:"foreignKey:UserID" json:"user,omitempty"`
	RoomID uint `gorm:"not null;uniqueIndex:idx_user_room_like" json:"room_id"`
	Room   Room `gorm:"foreignKey:RoomID" json:"room,omitempty"`
}

func (RoomLike) TableName() string {
	return "room_likes"
}
