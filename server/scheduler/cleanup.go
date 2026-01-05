package scheduler

import (
	"log"
	"time"
	"voxarena_server/controllers"

	"gorm.io/gorm"
)

func StartCleanupScheduler(db *gorm.DB) {
	ticker := time.NewTicker(24 * time.Hour)

	go func() {
		log.Println("Running initial cleanup of hidden rooms...")
		if err := controllers.CleanupHiddenRooms(db); err != nil {
			log.Printf("Error during initial cleanup: %v", err)
		} else {
			log.Println("Initial cleanup completed successfully")
		}
	}()

	go func() {
		for range ticker.C {
			log.Println("Running scheduled cleanup of hidden rooms...")
			if err := controllers.CleanupHiddenRooms(db); err != nil {
				log.Printf("Error during scheduled cleanup: %v", err)
			} else {
				log.Println("Scheduled cleanup completed successfully")
			}
		}
	}()
}
