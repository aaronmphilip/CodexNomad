package main

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"net/http"
	"net/url"
	"os"
	"strings"
	"time"

	"github.com/codexnomad/codexnomad/daemon/internal/e2ee"
	"github.com/codexnomad/codexnomad/daemon/internal/qr"
	"nhooyr.io/websocket"
)

type wireMessage struct {
	Type       string          `json:"type"`
	SessionID  string          `json:"sid"`
	Role       string          `json:"role,omitempty"`
	PublicKey  string          `json:"public_key,omitempty"`
	DeviceID   string          `json:"device_id,omitempty"`
	DeviceName string          `json:"device_name,omitempty"`
	Payload    json.RawMessage `json:"payload,omitempty"`
}

func main() {
	if err := run(); err != nil {
		fmt.Fprintf(os.Stderr, "mobile smoke failed: %v\n", err)
		os.Exit(1)
	}
}

func run() error {
	pairingURI := flag.String("pairing-uri", "", "codexnomad://pair URI from daemon stdout")
	sendText := flag.String("send", "E2EE_SMOKE_MARKER", "text to send as mobile stdin")
	expectText := flag.String("expect", "", "terminal text expected after sending stdin")
	timeout := flag.Duration("timeout", 30*time.Second, "overall smoke timeout")
	flag.Parse()

	if strings.TrimSpace(*pairingURI) == "" {
		return errors.New("-pairing-uri is required")
	}
	payload, err := parsePairingURI(*pairingURI)
	if err != nil {
		return err
	}
	expected := *expectText
	if expected == "" {
		expected = *sendText
	}

	ctx, cancel := context.WithTimeout(context.Background(), *timeout)
	defer cancel()

	kp, err := e2ee.GenerateKeyPair()
	if err != nil {
		return err
	}
	peer, err := e2ee.ParsePublicKey(payload.PublicKey)
	if err != nil {
		return err
	}

	conn, _, err := websocket.Dial(ctx, payload.RelayURL, &websocket.DialOptions{
		HTTPHeader: http.Header{"User-Agent": []string{"codexnomad-mobile-smoke/0.1"}},
	})
	if err != nil {
		return err
	}
	defer conn.Close(websocket.StatusNormalClosure, "smoke complete")

	mobilePub := e2ee.EncodePublicKey(kp.Public)
	if err := writeJSON(ctx, conn, wireMessage{
		Type:       "mobile_hello",
		SessionID:  payload.SessionID,
		Role:       "mobile",
		PublicKey:  mobilePub,
		DeviceID:   "mobile_smoke_" + shortKey(mobilePub),
		DeviceName: "Codex Nomad smoke test",
	}); err != nil {
		return err
	}

	var sendSeq uint64
	var lastRecv uint64
	sent := false
	var terminal strings.Builder

	for {
		_, raw, err := conn.Read(ctx)
		if err != nil {
			return err
		}
		var msg wireMessage
		if err := json.Unmarshal(raw, &msg); err != nil {
			return err
		}
		switch msg.Type {
		case "daemon_ready":
			if msg.PublicKey != "" {
				peer, err = e2ee.ParsePublicKey(msg.PublicKey)
				if err != nil {
					return err
				}
			}
			if !sent {
				sendSeq++
				if err := sendCiphertext(ctx, conn, payload.SessionID, sendSeq, kp, peer, "stdin", map[string]any{
					"text": ensureLine(*sendText),
				}); err != nil {
					return err
				}
				sent = true
			}
		case "ciphertext":
			plain, err := openCiphertext(kp, peer, msg.Payload, &lastRecv)
			if err != nil {
				return err
			}
			if plain.Type == "terminal_output" {
				text := terminalText(plain.Data)
				if text != "" {
					terminal.WriteString(text)
					fmt.Print(text)
				}
				if strings.Contains(terminal.String(), expected) {
					sendSeq++
					_ = sendCiphertext(ctx, conn, payload.SessionID, sendSeq, kp, peer, "stdin", map[string]any{
						"text": "exit\n",
					})
					fmt.Printf("\nmobile smoke passed: observed %q\n", expected)
					return nil
				}
			}
		case "pairing_expired":
			return errors.New("pairing expired")
		case "device_authorization_failed":
			return errors.New("daemon rejected mobile smoke device")
		case "device_identity_required":
			return errors.New("daemon required mobile device identity")
		}
	}
}

func parsePairingURI(raw string) (qr.PairingPayload, error) {
	u, err := url.Parse(strings.TrimSpace(raw))
	if err != nil {
		return qr.PairingPayload{}, err
	}
	if u.Scheme != "codexnomad" || u.Host != "pair" {
		return qr.PairingPayload{}, errors.New("pairing URI must start with codexnomad://pair")
	}
	encoded := u.Query().Get("data")
	if encoded == "" {
		return qr.PairingPayload{}, errors.New("pairing URI is missing data")
	}
	data, err := base64.RawURLEncoding.DecodeString(encoded)
	if err != nil {
		return qr.PairingPayload{}, err
	}
	var payload qr.PairingPayload
	if err := json.Unmarshal(data, &payload); err != nil {
		return qr.PairingPayload{}, err
	}
	if payload.SessionID == "" || payload.RelayURL == "" || payload.PublicKey == "" {
		return qr.PairingPayload{}, errors.New("pairing payload is missing required fields")
	}
	return payload, nil
}

func sendCiphertext(ctx context.Context, conn *websocket.Conn, sessionID string, seq uint64, kp e2ee.KeyPair, peer [32]byte, typ string, data any) error {
	env, err := e2ee.Seal(sessionID, "mobile", seq, kp, peer, typ, data)
	if err != nil {
		return err
	}
	raw, err := json.Marshal(env)
	if err != nil {
		return err
	}
	return writeJSON(ctx, conn, wireMessage{
		Type:      "ciphertext",
		SessionID: sessionID,
		Role:      "mobile",
		Payload:   raw,
	})
}

func openCiphertext(kp e2ee.KeyPair, peer [32]byte, payload json.RawMessage, lastRecv *uint64) (e2ee.PlainMessage, error) {
	var env e2ee.Envelope
	if err := json.Unmarshal(payload, &env); err != nil {
		return e2ee.PlainMessage{}, err
	}
	plain, err := e2ee.Open(kp, peer, env)
	if err != nil {
		return e2ee.PlainMessage{}, err
	}
	if env.Seq <= *lastRecv {
		return e2ee.PlainMessage{}, errors.New("replayed or out-of-order daemon message")
	}
	*lastRecv = env.Seq
	return plain, nil
}

func terminalText(raw json.RawMessage) string {
	var data struct {
		Encoding string `json:"encoding"`
		Data     string `json:"data"`
	}
	if err := json.Unmarshal(raw, &data); err != nil {
		return ""
	}
	if data.Encoding == "base64" {
		decoded, err := base64.RawStdEncoding.DecodeString(data.Data)
		if err == nil {
			return string(decoded)
		}
	}
	return data.Data
}

func writeJSON(ctx context.Context, conn *websocket.Conn, msg wireMessage) error {
	raw, err := json.Marshal(msg)
	if err != nil {
		return err
	}
	return conn.Write(ctx, websocket.MessageText, raw)
}

func ensureLine(text string) string {
	if strings.HasSuffix(text, "\n") {
		return text
	}
	return text + "\n"
}

func shortKey(key string) string {
	if len(key) <= 18 {
		return key
	}
	return key[:18]
}
