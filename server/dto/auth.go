package dto

type GoogleAuthRequest struct {
	IDToken    string `json:"id_token" binding:"required"`
	Email      string `json:"email" binding:"required,email"`
	FullName   string `json:"full_name" binding:"required"`
	ProfilePic string `json:"profile_pic"`
	GoogleID   string `json:"google_id" binding:"required"`
}

type AuthResponse struct {
	Token   string      `json:"token"`
	User    UserProfile `json:"user"`
	Message string      `json:"message"`
}

type UserProfile struct {
	ID              uint   `json:"id"`
	Email           string `json:"email"`
	Username        string `json:"username"`
	FullName        string `json:"full_name"`
	ProfilePic      string `json:"profile_pic"`
	Bio             string `json:"bio"`
	IsVerified      bool   `json:"is_verified"`
	FollowersCount  int    `json:"followers_count"`
	FollowingCount  int    `json:"following_count"`
	TotalGiftsValue int64  `json:"total_gifts_value"`
	Role            string `json:"role"`
}