package ws

import (
	"bytes"
	"context"
	"encoding/json"
	"log"
	"net/http"
	"sync"
	"time"

	"github.com/codexnomad/codexnomad/services/relay/internal/auth"
	"github.com/codexnomad/codexnomad/services/relay/internal/config"
	"nhooyr.io/websocket"
)

type WireMessage struct {
	Type       string          `json:"type"`
	SessionID  string          `json:"sid"`
	Role       string          `json:"role,omitempty"`
	PublicKey  string          `json:"public_key,omitempty"`
	DeviceID   string          `json:"device_id,omitempty"`
	DeviceName string          `json:"device_name,omitempty"`
	Payload    json.RawMessage `json:"payload,omitempty"`
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
		// Native mobile clients do not have a browser-origin security model.
		// Session routing is protected by relay tickets/shared tokens in prod
		// and payloads are still E2EE ciphertext, so strict Origin matching
		// would only break legitimate Android clients on local LAN relay URLs.
		InsecureSkipVerify: true,
		CompressionMode:    websocket.CompressionDisabled,
	})
	if err != nil {
		log.Printf("ws accept failed: %v", err)
		return
	}
	ticket, hasTicket := h.ticketFromRequest(r)
	c := &client{hub: h, conn: conn, send: make(chan []byte, 256)}
	if hasTicket {
		c.sessionID = ticket.SessionID
		c.role = ticket.Role
		c.hub.register(c)
	}
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
		c.hub.auditFrame(c, msg, raw)
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
		if c.role != "" && msg.Role != "" && msg.Role != c.role {
			continue
		}
		if msg.Type == "ping" {
			c.writeJSON(WireMessage{Type: "pong", SessionID: c.sessionID, Role: "relay"})
			continue
		}
		c.hub.forward(c, raw)
	}
}

func (h *Hub) auditFrame(c *client, msg WireMessage, raw []byte) {
	for _, marker := range h.cfg.RelayLeakMarkers {
		if marker == "" {
			continue
		}
		if bytes.Contains(raw, []byte(marker)) {
			log.Printf("POSSIBLE PLAINTEXT LEAK sid=%s role=%s marker=%q", msg.SessionID, msg.Role, marker)
		}
	}
	if !h.cfg.RelayDebugFrames {
		return
	}
	isCiphertext := msg.Type == "ciphertext"
	log.Printf(
		"relay frame sid=%s role=%s type=%s payload_bytes=%d ciphertext=%t registered_role=%s",
		msg.SessionID,
		msg.Role,
		msg.Type,
		len(msg.Payload),
		isCiphertext,
		c.role,
	)
}

func (h *Hub) ticketFromRequest(r *http.Request) (auth.RelayTicket, bool) {
	raw := r.URL.Query().Get("ticket")
	if raw == "" {
		raw = r.Header.Get("X-CodexNomad-Relay-Ticket")
	}
	if raw == "" {
		raw = auth.BearerToken(r.Header.Get("Authorization"))
	}
	if raw == "" || h.cfg.RelayTicketSecret == "" {
		return auth.RelayTicket{}, false
	}
	t, err := auth.VerifyRelayTicket(raw, h.cfg.RelayTicketSecret)
	if err != nil {
		log.Printf("invalid relay ticket: %v", err)
		return auth.RelayTicket{}, false
	}
	return t, true
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
