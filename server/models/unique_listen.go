package models

import (
	"time"

	"gorm.io/gorm"
)

type UniqueRoomListen struct {
	ID        uint           `gorm:"primarykey" json:"id"`
	CreatedAt time.Time      `json:"created_at"`
	UpdatedAt time.Time      `json:"updated_at"`
	DeletedAt gorm.DeletedAt `gorm:"index" json:"-"`
	RoomID    uint           `gorm:"not null;index:idx_room_user" json:"room_id"`
	UserID    uint           `gorm:"not null;index:idx_room_user" json:"user_id"`
	Room      Room           `gorm:"foreignKey:RoomID" json:"-"`
	User      User           `gorm:"foreignKey:UserID" json:"-"`
}

func (UniqueRoomListen) TableName() string {
	return "unique_room_listens"
}
