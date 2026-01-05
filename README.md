VoxArena 🎙️
A scalable mobile audio streaming and social platform
VoxArena is a production-grade audio streaming application that combines real-time audio content delivery with social networking features. Built with Flutter and Go, it's designed for scalability, performance, and real-world deployment.

🎯 Overview
VoxArena enables users to:

Stream audio content in real-time
Engage with a community through likes, comments, and replies
Discover content through personalized feeds and smart recommendations
Build social connections through follows and interactions
Receive real-time notifications for platform activity

The platform is architected for high concurrency, efficient data handling, and seamless user experience across mobile devices.

✨ Core Features
Audio Streaming

Real-time audio delivery with live listener tracking
Unique listen tracking per user per room
Download management for offline listening
Listening history with search and filter capabilities

Social Engagement

Follow/Unfollow system with followers and following lists
Feed customization with user hiding options
Personalized content based on following preferences
User discovery through search and recommendations

Interaction System

Engagement mechanics: Like audio rooms and comments
Nested comments: Comment and reply with unlimited depth
Community posts: Share updates with followers (YouTube Community-style)
Real-time updates: WebSocket-based live activity feed

Discovery & Recommendations

Smart queue algorithm based on listening history and preferences
Trending content discovery
Advanced search for users and audio rooms
Category-based browsing

Notifications

Real-time push notifications for:

New followers
Likes and comments
Room activity
Community updates


Notification management: Mark as read, delete, bulk actions
Unread count tracking

Content Moderation

User reporting system for inappropriate content
Automated moderation: Auto-hide after report threshold
Scheduled cleanup jobs for stale reports
Admin controls (planned)


🏗️ Architecture
Technology Stack
Backend

Language: Go 1.21+
Framework: Gin (HTTP router)
ORM: GORM with PostgreSQL
Real-time: WebSocket connections
Authentication: JWT-based auth
Task Scheduling: Cron jobs for cleanup and maintenance
Media Storage: Cloudinary integration

Mobile

Framework: Flutter 3.x
Language: Dart
State Management: Provider/Riverpod
Networking: HTTP REST API client
Media Handling: Audio playback and caching

Infrastructure

Hosting: Render (backend + PostgreSQL)
Database: PostgreSQL 15+
CDN: Cloudinary for media assets
Version Control: Git/GitHub

Project Structure
voxarena/
├── backend/
│   ├── controllers/       # Request handlers
│   ├── models/           # Database models
│   ├── routes/           # API routing
│   ├── middleware/       # Auth, CORS, validation
│   ├── services/         # Business logic
│   ├── websocket/        # Real-time handlers
│   ├── scheduler/        # Cron jobs
│   ├── utils/            # Helpers and utilities
│   └── main.go
│
└── mobile/
    ├── lib/
    │   ├── models/       # Data models
    │   ├── services/     # API clients
    │   ├── screens/      # UI screens
    │   ├── widgets/      # Reusable components
    │   └── main.dart
    ├── assets/
    └── pubspec.yaml

🔐 Security

JWT Authentication: Secure token-based sessions
Middleware Protection: Route-level authentication
Password Hashing: bcrypt encryption
Input Validation: Server-side validation for all inputs
CORS Configuration: Controlled cross-origin access
Rate Limiting: API throttling (planned)


🚀 Deployment
Backend (Render)

Deployed as a web service on Render
PostgreSQL managed database
Automatic deployments from GitHub
Environment variables configured via Render dashboard

Mobile App

Android:

APK for testing and distribution
App Bundle for Google Play Store


iOS:

Requires macOS and Xcode
App Store deployment ready




📱 Build Instructions
Backend Setup
bash# Clone repository
git clone https://github.com/harshhkalia/voxarena.git
cd voxarena/backend

# Install dependencies
go mod download

# Set environment variables
export DATABASE_URL="postgresql://..."
export JWT_SECRET="your-secret-key"
export CLOUDINARY_URL="cloudinary://..."

# Run server
go run main.go
Mobile App Build
bashcd voxarena/mobile

# Clean previous builds
flutter clean

# Get dependencies
flutter pub get

# Build Android APK
flutter build apk --release

# Build Android App Bundle (for Play Store)
flutter build appbundle --release

# Build iOS (requires macOS)
flutter build ios --release
Output locations:

APK: build/app/outputs/flutter-apk/app-release.apk
App Bundle: build/app/outputs/bundle/release/app-release.aab


🧪 Current Status
ComponentStatusNotesBackend API✅ ProductionDeployed on RenderPostgreSQL✅ ProductionManaged databaseWebSocket✅ ProductionReal-time updates liveAndroid App✅ FunctionalTestable and deployableiOS App⏳ PendingRequires macOS buildAdmin Panel🔜 PlannedWeb-based dashboard

📊 API Endpoints
Authentication

POST /api/auth/register - User registration
POST /api/auth/login - User login
GET /api/auth/me - Get current user (protected)

Audio Rooms

GET /api/rooms - List audio rooms
GET /api/rooms/:id - Get room details
POST /api/rooms - Create room (protected)
POST /api/rooms/:id/listen - Track listen
POST /api/rooms/:id/like - Like/unlike room

Social

POST /api/users/:id/follow - Follow/unfollow user
GET /api/users/:id/followers - Get followers
GET /api/users/:id/following - Get following
POST /api/users/:id/hide - Hide user from feed

Notifications

GET /api/notifications - Get user notifications
PUT /api/notifications/read - Mark all as read
DELETE /api/notifications/:id - Delete notification


🎯 Roadmap

 Admin dashboard for moderation
 Live audio streaming (WebRTC)
 Voice rooms with real-time participation
 Analytics dashboard for creators
 Premium subscription tier
 Push notifications (FCM)
 Advanced recommendation algorithm
 Multi-language support


📌 Notes

Free Tier Limitations: Render's free tier may experience cold starts and periodic data resets
Scalability: Architecture supports horizontal scaling with load balancers
Code Quality: Emphasis on clean code, separation of concerns, and maintainability
Learning Project: Built to demonstrate production-grade development practices


👤 Author
Harsh Kalia
Backend-focused software engineer specializing in scalable systems, real-time applications, and production-ready architectures.

GitHub: @harshhkalia
LinkedIn: Connect


📜 License
This project is maintained for educational and portfolio purposes.
Commercial use requires explicit permission from the author.

Built with 🎙️ for audio lovers and tech enthusiasts