package config

import (
	"fmt"
	"log"
	"os"

	"gorm.io/driver/postgres"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"
)

var DB *gorm.DB

func InitDB() error {
	var dsn string

	// ✅ PRODUCTION / RAILWAY
	if databaseURL := os.Getenv("DATABASE_URL"); databaseURL != "" {
		dsn = databaseURL
		log.Println("✓ Using DATABASE_URL for database connection")
	} else {
		// ✅ LOCAL DEVELOPMENT FALLBACK
		host := GetEnv("DB_HOST", "localhost")
		port := GetEnv("DB_PORT", "5432")
		user := GetEnv("DB_USER", "postgres")
		password := GetEnv("DB_PASSWORD", "")
		dbname := GetEnv("DB_NAME", "voxarena")
		sslmode := GetEnv("DB_SSLMODE", "disable")

		dsn = fmt.Sprintf(
			"host=%s port=%s user=%s password=%s dbname=%s sslmode=%s",
			host, port, user, password, dbname, sslmode,
		)

		log.Println("✓ Using local database environment variables")
	}

	var err error
	DB, err = gorm.Open(postgres.Open(dsn), &gorm.Config{
		Logger: logger.Default.LogMode(logger.Info),
	})

	if err != nil {
		return fmt.Errorf("failed to connect to database: %v", err)
	}

	log.Println("✓ Database connected successfully!")
	return nil
}

func GetDB() *gorm.DB {
	return DB
}

func GetEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}
