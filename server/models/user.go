package models

import (
	"time"

	"gorm.io/gorm"
)

type User struct {
	ID              uint           `gorm:"primarykey" json:"id"`
	CreatedAt       time.Time      `json:"created_at"`
	UpdatedAt       time.Time      `json:"updated_at"`
	DeletedAt       gorm.DeletedAt `gorm:"index" json:"-"`
	Email           string         `gorm:"uniqueIndex;not null" json:"email"`
	Username        string         `gorm:"uniqueIndex" json:"username"`
	FullName        string         `json:"full_name"`
	ProfilePic      string         `json:"profile_pic"`
	Bio             string         `json:"bio"`
	GoogleID        string         `gorm:"uniqueIndex" json:"google_id,omitempty"`
	Provider        string         `gorm:"default:'google'" json:"provider"`
	IsVerified      bool           `gorm:"default:false" json:"is_verified"`
	IsActive        bool           `gorm:"default:true" json:"is_active"`
	LastLoginAt     *time.Time     `json:"last_login_at,omitempty"`
	FollowersCount  int            `gorm:"default:0" json:"followers_count"`
	FollowingCount  int            `gorm:"default:0" json:"following_count"`
	TotalGiftsValue int64          `gorm:"default:0" json:"total_gifts_value"`
	Role            string         `gorm:"default:'user'" json:"role"`
}

func (User) TableName() string {
	return "users"
}

func (u *User) BeforeCreate(tx *gorm.DB) error {
	if u.Username == "" && u.Email != "" {
		u.Username = u.Email[:len(u.Email)-len("@gmail.com")]
	}
	return nil
}
