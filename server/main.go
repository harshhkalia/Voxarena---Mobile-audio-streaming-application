package main

import (
	"fmt"
	"log"
	"voxarena_server/config"
	"voxarena_server/models"
	"voxarena_server/routes"
	"voxarena_server/scheduler"
	"voxarena_server/utils"
	"voxarena_server/websocket"

	"github.com/gin-gonic/gin"
	"github.com/joho/godotenv"
)

func main() {
	if err := godotenv.Load(); err != nil {
		log.Println("No .env file found, using environment variables")
	}

	if err := config.InitDB(); err != nil {
		log.Fatal("Failed to initialize database:", err)
	}

	if err := config.DB.AutoMigrate(
		&models.User{},
		&models.Room{},
		&models.ListenHistory{},
		&models.RoomLike{},
		&models.Comment{},
		&models.CommentLike{},
		&models.Follow{},
		&models.HiddenUser{},
		&models.DownloadHistory{},
		&models.CommunityPost{},
		&models.CommunityPostImage{},
		&models.CommunityPostLike{},
		&models.CommunityPostComment{},
		&models.CommunityCommentLike{},
		&models.UniqueRoomListen{},
		&models.RoomReport{},
		&models.Notification{},
	); err != nil {
		log.Fatal("Failed to migrate database:", err)
	}

	if err := config.DB.Exec(`
		CREATE UNIQUE INDEX IF NOT EXISTS idx_comment_user_unique 
		ON comment_likes(comment_id, user_id)
	`).Error; err != nil {
		log.Println("⚠️  Warning: Failed to create unique index on comment_likes:", err)
	} else {
		log.Println("✓ Comment system indexes created successfully")
	}

	if err := config.DB.Exec(`
	CREATE UNIQUE INDEX IF NOT EXISTS idx_unique_room_listen ON unique_room_listens(room_id, user_id) WHERE deleted_at IS NULL
	`).Error; err != nil {
		log.Println("⚠️  Warning: Failed to create unique index on unique_room_listens:", err)
	} else {
		log.Println("✓ UniqueRoomListen indexes created successfully")
	}

	if err := config.DB.Exec(`
    CREATE UNIQUE INDEX IF NOT EXISTS idx_room_report_unique
    ON room_reports(room_id, reporter_id)
    WHERE deleted_at IS NULL
`).Error; err != nil {
		log.Println("⚠️  Warning: Failed to create unique index on room_reports:", err)
	} else {
		log.Println("✓ Room report unique index created successfully")
	}

	if err := config.DB.Exec(`
		CREATE INDEX IF NOT EXISTS idx_notification_user_unread 
		ON notifications(user_id, is_read) 
		WHERE deleted_at IS NULL
	`).Error; err != nil {
		log.Println("⚠️  Warning: Failed to create index on notifications:", err)
	} else {
		log.Println("✓ Notification indexes created successfully")
	}

	if err := utils.InitCloudinary(); err != nil {
		log.Println("⚠️  Warning: Cloudinary not initialized:", err)
		log.Println("Profile picture uploads will use Google URLs as fallback")
	} else {
		log.Println("✓ Cloudinary initialized successfully")
	}

	websocket.InitHub()
log.Println("✓ WebSocket hub initialized")

	router := gin.Default()
	routes.SetupRoutes(router)
	scheduler.StartCleanupScheduler(config.DB)

	// serverHost := config.GetEnv("SERVER_HOST", "0.0.0.0")
	// serverPort := config.GetEnv("SERVER_PORT", "8090")
	port := config.GetEnv("PORT", "8080")

	// addr := fmt.Sprintf("%s:%s", serverHost, serverPort)
	addr := fmt.Sprintf(":%s", port)
	log.Printf("🚀 VoxArena Server starting on %s", addr)

	if err := router.Run(addr); err != nil {
		log.Fatal("Failed to start server:", err)
	}
}
