package models

import (
	"time"
)

type HiddenUser struct {
	ID        uint      `gorm:"primarykey" json:"id"`
	CreatedAt time.Time `json:"created_at"`

	UserID uint `gorm:"not null;index:idx_user_hidden,unique" json:"user_id"`
	User   User `gorm:"foreignKey:UserID" json:"user"`

	HiddenUserID uint `gorm:"not null;index:idx_user_hidden,unique" json:"hidden_user_id"`
	HiddenUser   User `gorm:"foreignKey:HiddenUserID" json:"hidden_user"`
}

func (HiddenUser) TableName() string {
	return "hidden_users"
}
