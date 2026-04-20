package relay

import (
	"context"
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"time"

	"nhooyr.io/websocket"
)

type WireMessage struct {
	Type      string          `json:"type"`
	SessionID string          `json:"sid"`
	Role      string          `json:"role,omitempty"`
	PublicKey string          `json:"public_key,omitempty"`
	Payload   json.RawMessage `json:"payload,omitempty"`
}

type Client struct {
	URL       string
	SessionID string
	PublicKey string
	Token     string
	Logger    *log.Logger
}

func (c Client) Run(ctx context.Context, inbound chan<- WireMessage, outbound <-chan WireMessage) error {
	headers := http.Header{"User-Agent": []string{"codexnomad-daemon/0.1"}}
	if c.Token != "" {
		headers.Set("Authorization", "Bearer "+c.Token)
		headers.Set("X-CodexNomad-Relay-Token", c.Token)
	}
	conn, _, err := websocket.Dial(ctx, c.URL, &websocket.DialOptions{HTTPHeader: headers})
	if err != nil {
		return err
	}
	defer conn.Close(websocket.StatusNormalClosure, "daemon shutdown")

	if err := c.writeJSON(ctx, conn, WireMessage{
		Type:      "daemon_hello",
		SessionID: c.SessionID,
		Role:      "daemon",
		PublicKey: c.PublicKey,
	}); err != nil {
		return err
	}

	errCh := make(chan error, 2)
	go func() {
		errCh <- c.readLoop(ctx, conn, inbound)
	}()
	go func() {
		errCh <- c.writeLoop(ctx, conn, outbound)
	}()

	select {
	case <-ctx.Done():
		return ctx.Err()
	case err := <-errCh:
		return err
	}
}

func (c Client) readLoop(ctx context.Context, conn *websocket.Conn, inbound chan<- WireMessage) error {
	for {
		_, data, err := conn.Read(ctx)
		if err != nil {
			return err
		}
		var msg WireMessage
		if err := json.Unmarshal(data, &msg); err != nil {
			if c.Logger != nil {
				c.Logger.Printf("relay: ignored invalid json frame: %v", err)
			}
			continue
		}
		if msg.SessionID != "" && msg.SessionID != c.SessionID {
			if c.Logger != nil {
				c.Logger.Printf("relay: ignored frame for session %q", msg.SessionID)
			}
			continue
		}
		select {
		case inbound <- msg:
		case <-ctx.Done():
			return ctx.Err()
		}
	}
}

func (c Client) writeLoop(ctx context.Context, conn *websocket.Conn, outbound <-chan WireMessage) error {
	ping := time.NewTicker(25 * time.Second)
	defer ping.Stop()
	for {
		select {
		case msg, ok := <-outbound:
			if !ok {
				return nil
			}
			if err := c.writeJSON(ctx, conn, msg); err != nil {
				return err
			}
		case <-ping.C:
			if err := c.writeJSON(ctx, conn, WireMessage{Type: "ping", SessionID: c.SessionID, Role: "daemon"}); err != nil {
				return err
			}
		case <-ctx.Done():
			return ctx.Err()
		}
	}
}

func (c Client) writeJSON(ctx context.Context, conn *websocket.Conn, msg WireMessage) error {
	if msg.SessionID == "" {
		return errors.New("relay message missing session id")
	}
	raw, err := json.Marshal(msg)
	if err != nil {
		return err
	}
	return conn.Write(ctx, websocket.MessageText, raw)
}
