package ws

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"sync"
	"time"

	"github.com/codexnomad/codexnomad/services/relay/internal/config"
	"nhooyr.io/websocket"
)

type WireMessage struct {
	Type      string          `json:"type"`
	SessionID string          `json:"sid"`
	Role      string          `json:"role,omitempty"`
	PublicKey string          `json:"public_key,omitempty"`
	Payload   json.RawMessage `json:"payload,omitempty"`
}

type Hub struct {
	cfg      config.Config
	mu       sync.RWMutex
	sessions map[string]map[*client]struct{}
}

type client struct {
	hub       *Hub
	conn      *websocket.Conn
	sessionID string
	role      string
	send      chan []byte
}

func NewHub(cfg config.Config) *Hub {
	return &Hub{cfg: cfg, sessions: map[string]map[*client]struct{}{}}
}

func (h *Hub) Handle(w http.ResponseWriter, r *http.Request) {
	conn, err := websocket.Accept(w, r, &websocket.AcceptOptions{
		InsecureSkipVerify: false,
		CompressionMode:    websocket.CompressionDisabled,
	})
	if err != nil {
		log.Printf("ws accept failed: %v", err)
		return
	}
	c := &client{hub: h, conn: conn, send: make(chan []byte, 256)}
	ctx := r.Context()
	defer c.close()

	go c.writeLoop(ctx)
	c.readLoop(ctx)
}

func (c *client) readLoop(ctx context.Context) {
	for {
		_, raw, err := c.conn.Read(ctx)
		if err != nil {
			return
		}
		var msg WireMessage
		if err := json.Unmarshal(raw, &msg); err != nil {
			continue
		}
		if msg.SessionID == "" {
			continue
		}
		if c.sessionID == "" {
			c.sessionID = msg.SessionID
			c.role = msg.Role
			c.hub.register(c)
		}
		if msg.SessionID != c.sessionID {
			continue
		}
		if msg.Type == "ping" {
			c.writeJSON(WireMessage{Type: "pong", SessionID: c.sessionID, Role: "relay"})
			continue
		}
		c.hub.forward(c, raw)
	}
}

func (c *client) writeLoop(ctx context.Context) {
	ping := time.NewTicker(25 * time.Second)
	defer ping.Stop()
	for {
		select {
		case raw, ok := <-c.send:
			if !ok {
				return
			}
			if err := c.conn.Write(ctx, websocket.MessageText, raw); err != nil {
				return
			}
		case <-ping.C:
			_ = c.conn.Ping(ctx)
		case <-ctx.Done():
			return
		}
	}
}

func (c *client) writeJSON(msg WireMessage) {
	raw, err := json.Marshal(msg)
	if err != nil {
		return
	}
	select {
	case c.send <- raw:
	default:
	}
}

func (c *client) close() {
	if c.sessionID != "" {
		c.hub.unregister(c)
	}
	_ = c.conn.Close(websocket.StatusNormalClosure, "closed")
}

func (h *Hub) register(c *client) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if h.sessions[c.sessionID] == nil {
		h.sessions[c.sessionID] = map[*client]struct{}{}
	}
	h.sessions[c.sessionID][c] = struct{}{}
}

func (h *Hub) unregister(c *client) {
	h.mu.Lock()
	defer h.mu.Unlock()
	peers := h.sessions[c.sessionID]
	delete(peers, c)
	if len(peers) == 0 {
		delete(h.sessions, c.sessionID)
	}
}

func (h *Hub) forward(sender *client, raw []byte) {
	h.mu.RLock()
	defer h.mu.RUnlock()
	for peer := range h.sessions[sender.sessionID] {
		if peer == sender {
			continue
		}
		select {
		case peer.send <- raw:
		default:
			log.Printf("relay queue full sid=%s role=%s", sender.sessionID, peer.role)
		}
	}
}
