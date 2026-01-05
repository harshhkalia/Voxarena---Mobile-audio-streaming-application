package models

import (
	"time"
)

type Follow struct {
	ID          uint      `gorm:"primarykey" json:"id"`
	CreatedAt   time.Time `json:"created_at"`
	FollowerID  uint      `gorm:"not null;index:idx_follower_following,unique" json:"follower_id"`
	FollowingID uint      `gorm:"not null;index:idx_follower_following,unique" json:"following_id"`
	Follower    User      `gorm:"foreignKey:FollowerID" json:"follower"`
	Following   User      `gorm:"foreignKey:FollowingID" json:"following"`
}

func (Follow) TableName() string {
	return "follows"
}
