package main

import (
	"context"
	"fmt"
	"log"
	"math/rand"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/nvoi/example-app/models"
	"gorm.io/driver/postgres"
	"gorm.io/gorm"
)

var db *gorm.DB

func main() {
	// Initialize database
	var err error
	db, err = initDB()
	if err != nil {
		log.Fatalf("Failed to initialize database: %v", err)
	}

	// Auto-migrate database schema
	if err := db.AutoMigrate(&models.User{}); err != nil {
		log.Fatalf("Failed to migrate database: %v", err)
	}

	// Setup router
	router := setupRouter()

	// Configure server
	srv := &http.Server{
		Addr:    ":3000",
		Handler: router,
	}

	// Start server in goroutine
	go func() {
		log.Println("Starting server on :3000")
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("Server failed to start: %v", err)
		}
	}()

	// Wait for interrupt signal for graceful shutdown
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	log.Println("Shutting down server...")

	// Graceful shutdown with 5 second timeout
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if err := srv.Shutdown(ctx); err != nil {
		log.Fatalf("Server forced to shutdown: %v", err)
	}

	log.Println("Server exited")
}

func initDB() (*gorm.DB, error) {
	// Get database URL from environment
	databaseURL := os.Getenv("DATABASE_URL")
	if databaseURL == "" {
		return nil, fmt.Errorf("DATABASE_URL environment variable not set")
	}

	// Connect to PostgreSQL
	db, err := gorm.Open(postgres.Open(databaseURL), &gorm.Config{})
	if err != nil {
		return nil, fmt.Errorf("failed to connect to database: %w", err)
	}

	// Test connection
	sqlDB, err := db.DB()
	if err != nil {
		return nil, fmt.Errorf("failed to get database instance: %w", err)
	}

	if err := sqlDB.Ping(); err != nil {
		return nil, fmt.Errorf("failed to ping database: %w", err)
	}

	// Configure connection pool
	sqlDB.SetMaxIdleConns(10)
	sqlDB.SetMaxOpenConns(100)
	sqlDB.SetConnMaxLifetime(time.Hour)

	log.Println("Database connected successfully")
	return db, nil
}

func setupRouter() *gin.Engine {
	// Set Gin mode from environment
	if mode := os.Getenv("GIN_MODE"); mode != "" {
		gin.SetMode(mode)
	}

	router := gin.Default()

	// Health check endpoint (required for deployment)
	router.GET("/health", healthCheck)

	// Main endpoint: creates user on every visit, returns all users
	router.GET("/", handleVisit)

	return router
}

// Health check handler (required for zero-downtime deployments)
func healthCheck(c *gin.Context) {
	// Check database connectivity
	sqlDB, err := db.DB()
	if err != nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{
			"status": "unhealthy",
			"error":  "database connection failed",
		})
		return
	}

	if err := sqlDB.Ping(); err != nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{
			"status": "unhealthy",
			"error":  "database ping failed",
		})
		return
	}

	// Get hostname to verify pod identity
	hostname, _ := os.Hostname()

	c.JSON(http.StatusOK, gin.H{
		"status":   "healthy",
		"service":  "golang-postgres-multi",
		"hostname": hostname,
		"time":     time.Now().Format(time.RFC3339),
	})
}

// Main handler: creates a new user on every visit and returns all users
func handleVisit(c *gin.Context) {
	// Create a new user with random name
	newUser := models.User{
		Name:  generateRandomName(),
		Email: fmt.Sprintf("user-%d@example.com", time.Now().UnixNano()),
	}

	if err := db.Create(&newUser).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error": "Failed to create user",
		})
		return
	}

	// Fetch all users
	var users []models.User
	if err := db.Find(&users).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error": "Failed to fetch users",
		})
		return
	}

	// Get deployment info
	hostname, _ := os.Hostname()

	// Return response
	c.JSON(http.StatusOK, gin.H{
		"hostname":    hostname,
		"message":     "User created on this visit!",
		"new_user":    newUser,
		"total_users": len(users),
		"all_users":   users,
	})
}

// Generate random name for demo purposes
func generateRandomName() string {
	firstNames := []string{"Alice", "Bob", "Charlie", "Diana", "Eve", "Frank", "Grace", "Henry", "Ivy", "Jack"}
	lastNames := []string{"Smith", "Johnson", "Williams", "Brown", "Jones", "Garcia", "Miller", "Davis", "Rodriguez", "Martinez"}

	rand.Seed(time.Now().UnixNano())
	firstName := firstNames[rand.Intn(len(firstNames))]
	lastName := lastNames[rand.Intn(len(lastNames))]

	return fmt.Sprintf("%s %s", firstName, lastName)
}
