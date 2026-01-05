package routes

import (
	"voxarena_server/controllers"
	"voxarena_server/middleware"
	"voxarena_server/websocket"

	"github.com/gin-gonic/gin"
)

func SetupRoutes(router *gin.Engine) {
	router.Use(middleware.CORSMiddleware())

	v1 := router.Group("/api/v1")
	{
		v1.GET("/status", controllers.GetStatus)
		v1.GET("/topics", controllers.GetTopics)
		v1.GET("/discovery", middleware.OptionalAuthMiddleware(), controllers.GetDiscoveryFeed)

		auth := v1.Group("/auth")
		{
			auth.POST("/google", controllers.GoogleAuth)
		}

		v1.GET("/search", middleware.OptionalAuthMiddleware(), controllers.GlobalSearch)

		protected := v1.Group("/")
		protected.Use(middleware.AuthMiddleware())
		{
			protected.GET("/me", controllers.GetMe)
			protected.GET("/ws", websocket.HandleWebSocket)

			protected.GET("/profile", controllers.GetUserProfile)
			protected.PUT("/profile", controllers.UpdateUserProfile)
			protected.POST("/profile/upload-image", controllers.UploadProfileImage)

			protected.GET("/users/:id", controllers.GetUserProfileByID)
			protected.GET("/users/:id/rooms", controllers.GetUserRooms)

			protected.POST("/rooms", controllers.CreateRoom)
			protected.GET("/rooms", controllers.GetRooms)
			protected.GET("/rooms/:id", controllers.GetRoomByID)
			protected.GET("/my-rooms", controllers.GetMyRooms)
			protected.PUT("/rooms/:id", controllers.UpdateRoom)
			protected.PUT("/rooms/:id/privacy", controllers.UpdateRoomPrivacy)
			protected.DELETE("/rooms/:id", controllers.DeleteRoom)

			protected.POST("/rooms/:id/start-listening", controllers.StartListening)
			protected.POST("/rooms/:id/stop-listening", controllers.StopListening)
			protected.GET("/rooms/:id/listeners", controllers.GetListenerCount)
			protected.PUT("/listen-history/:id", controllers.UpdateListenHistory)
			protected.GET("/my-history", controllers.GetUserListenHistory)
			protected.DELETE("/listen-history/:id", controllers.DeleteListenHistory)

			protected.POST("/rooms/:id/like", controllers.ToggleLike)
			protected.GET("/rooms/:id/like-status", controllers.CheckIfLiked)

			protected.POST("/rooms/:id/comments", controllers.CreateComment)
			protected.GET("/rooms/:id/comments", controllers.GetComments)
			protected.GET("/comments/:id/replies", controllers.GetReplies)
			protected.DELETE("/comments/:id", controllers.DeleteComment)
			protected.POST("/comments/:id/like", controllers.ToggleCommentLike)

			protected.POST("/users/:id/follow", controllers.ToggleFollow)
			protected.GET("/users/:id/follow-status", controllers.CheckFollowStatus)
			protected.GET("/users/:id/followers", controllers.GetFollowers)
			protected.GET("/users/:id/following", controllers.GetFollowing)
			protected.GET("/following/rooms", controllers.GetFollowingRooms)
			protected.DELETE("/users/:id/remove-follower", controllers.RemoveFollower)

			protected.POST("/queue/smart", controllers.GetSmartQueue)
			protected.GET("/queue/search", controllers.GetQueueFromSearch)

			protected.POST("/users/:id/hide", controllers.ToggleHideUser)
			protected.GET("/users/:id/hide-status", controllers.CheckHiddenStatus)
			protected.GET("/hidden-users", controllers.GetHiddenUsers)

			protected.POST("/downloads", controllers.TrackDownload)
			protected.GET("/my-downloads", controllers.GetUserDownloadHistory)
			protected.DELETE("/download-history/:id", controllers.DeleteDownloadHistory)
			protected.DELETE("/download-history", controllers.ClearAllDownloadHistory)

			protected.POST("/community-posts", controllers.CreateCommunityPost)
			protected.GET("/community-posts", controllers.GetCommunityPosts)
			protected.GET("/community-posts/:id", controllers.GetCommunityPostByID)
			protected.GET("/users/:id/community-posts", controllers.GetUserCommunityPosts)
			protected.PUT("/community-posts/:id", controllers.UpdateCommunityPost)
			protected.DELETE("/community-posts/:id", controllers.DeleteCommunityPost)

			protected.POST("/community-posts/:id/like", controllers.ToggleCommunityPostLike)
			protected.GET("/community-posts/:id/like-status", controllers.CheckCommunityPostLikeStatus)

			protected.POST("/community-posts/:id/comments", controllers.CreateCommunityPostComment)
			protected.GET("/community-posts/:id/comments", controllers.GetCommunityPostComments)
			protected.DELETE("/community-comments/:id", controllers.DeleteCommunityPostComment)

			protected.POST("/community-comments/:id/like", controllers.ToggleCommunityCommentLike)
			protected.GET("/community-comments/:id/like-status", controllers.CheckCommunityCommentLikeStatus)
			protected.GET("/community-comments/:id/replies", controllers.GetCommunityCommentReplies)

			protected.POST("/rooms/:id/record-listen", controllers.RecordUniqueListenIfNew)

			protected.POST("/rooms/:id/report", controllers.ReportRoom)
			protected.GET("/rooms/:id/reports", controllers.GetRoomReports)
			protected.GET("/rooms/:id/report-status", controllers.CheckIfReported)

			protected.GET("/notifications", controllers.GetNotifications)
			protected.GET("/notifications/unread-count", controllers.GetUnreadCount)
			protected.PUT("/notifications/mark-all-read", controllers.MarkAllNotificationsAsRead)
			protected.DELETE("/notifications/:id", controllers.DeleteNotification)
		}
	}

	router.GET("/", func(c *gin.Context) {
		c.JSON(200, gin.H{
			"message": "VoxArena API v1.0",
			"status":  "running",
		})
	})
}
