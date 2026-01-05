package websocket

import (
	"encoding/json"
	"log"
	"sync"

	"github.com/gorilla/websocket"
)

type Client struct {
	UserID uint
	Conn   *websocket.Conn
	Send   chan []byte
	Hub    *Hub
}

type Hub struct {
	Clients    map[uint]*Client
	Register   chan *Client
	Unregister chan *Client
	mu         sync.RWMutex
}

var GlobalHub *Hub

func NewHub() *Hub {
	return &Hub{
		Clients:    make(map[uint]*Client),
		Register:   make(chan *Client),
		Unregister: make(chan *Client),
	}
}

func (h *Hub) Run() {
	log.Println("🔌 WebSocket Hub started")
	
	for {
		select {
		case client := <-h.Register:
			h.mu.Lock()
			h.Clients[client.UserID] = client
			h.mu.Unlock()
			log.Printf("✓ User %d connected (Total: %d)", client.UserID, len(h.Clients))

		case client := <-h.Unregister:
			h.mu.Lock()
			if _, ok := h.Clients[client.UserID]; ok {
				delete(h.Clients, client.UserID)
				close(client.Send)
				log.Printf("✗ User %d disconnected (Total: %d)", client.UserID, len(h.Clients))
			}
			h.mu.Unlock()
		}
	}
}

func (h *Hub) SendToUsers(userIDs []uint, message interface{}) {
	data, err := json.Marshal(message)
	if err != nil {
		log.Printf("❌ Failed to marshal message: %v", err)
		return
	}

	h.mu.RLock()
	defer h.mu.RUnlock()

	sent := 0
	for _, userID := range userIDs {
		if client, ok := h.Clients[userID]; ok {
			select {
			case client.Send <- data:
				sent++
			default:
				log.Printf("⚠️ Failed to send to user %d", userID)
			}
		}
	}

	log.Printf("📤 Sent notification to %d/%d users", sent, len(userIDs))
}

func InitHub() {
	GlobalHub = NewHub()
	go GlobalHub.Run()
}