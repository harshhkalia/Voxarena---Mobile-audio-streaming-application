package models

import (
	"time"
)

type RoomReport struct {
	ID        uint      `gorm:"primarykey" json:"id"`
	CreatedAt time.Time `json:"created_at"`

	RoomID uint `gorm:"index;not null" json:"room_id"`
	Room   Room `gorm:"foreignKey:RoomID" json:"-"`

	ReporterID uint `gorm:"index;not null" json:"reporter_id"`
	Reporter   User `gorm:"foreignKey:ReporterID" json:"-"`

	Reason  string `gorm:"not null" json:"reason"`
	Details string `json:"details,omitempty"`

	Status string `gorm:"default:'pending'" json:"status"`
}

func (RoomReport) TableName() string {
	return "room_reports"
}
