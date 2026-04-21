package e2ee

import (
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"errors"
	"time"

	"golang.org/x/crypto/chacha20poly1305"
	"golang.org/x/crypto/curve25519"
)

const (
	Version = 1
)

var b64 = base64.RawURLEncoding

type KeyPair struct {
	Public  [32]byte
	Private [32]byte
}

type Envelope struct {
	Version    int    `json:"v"`
	SessionID  string `json:"sid"`
	Sender     string `json:"sender"`
	Seq        uint64 `json:"seq"`
	Nonce      string `json:"nonce"`
	Ciphertext string `json:"ciphertext"`
}

type PlainMessage struct {
	Type      string          `json:"type"`
	SessionID string          `json:"sid"`
	Seq       uint64          `json:"seq"`
	SentAt    time.Time       `json:"sent_at"`
	Data      json.RawMessage `json:"data,omitempty"`
}

func GenerateKeyPair() (KeyPair, error) {
	var priv [32]byte
	if _, err := rand.Read(priv[:]); err != nil {
		return KeyPair{}, err
	}
	pubRaw, err := curve25519.X25519(priv[:], curve25519.Basepoint)
	if err != nil {
		return KeyPair{}, err
	}
	var pub [32]byte
	copy(pub[:], pubRaw)
	return KeyPair{Public: pub, Private: priv}, nil
}

func ParsePublicKey(encoded string) ([32]byte, error) {
	raw, err := b64.DecodeString(encoded)
	if err != nil {
		return [32]byte{}, err
	}
	if len(raw) != 32 {
		return [32]byte{}, errors.New("public key must decode to 32 bytes")
	}
	var key [32]byte
	copy(key[:], raw)
	return key, nil
}

func EncodePublicKey(key [32]byte) string {
	return b64.EncodeToString(key[:])
}

func Seal(sessionID, sender string, seq uint64, kp KeyPair, peer [32]byte, msgType string, data any) (Envelope, error) {
	rawData, err := json.Marshal(data)
	if err != nil {
		return Envelope{}, err
	}
	plain, err := json.Marshal(PlainMessage{
		Type:      msgType,
		SessionID: sessionID,
		Seq:       seq,
		SentAt:    time.Now().UTC(),
		Data:      rawData,
	})
	if err != nil {
		return Envelope{}, err
	}
	var nonce [chacha20poly1305.NonceSizeX]byte
	if _, err := rand.Read(nonce[:]); err != nil {
		return Envelope{}, err
	}
	key, err := sharedKey(kp, peer)
	if err != nil {
		return Envelope{}, err
	}
	aead, err := chacha20poly1305.NewX(key)
	if err != nil {
		return Envelope{}, err
	}
	ciphertext := aead.Seal(nil, nonce[:], plain, nil)
	return Envelope{
		Version:    Version,
		SessionID:  sessionID,
		Sender:     sender,
		Seq:        seq,
		Nonce:      b64.EncodeToString(nonce[:]),
		Ciphertext: b64.EncodeToString(ciphertext),
	}, nil
}

func Open(kp KeyPair, peer [32]byte, env Envelope) (PlainMessage, error) {
	if env.Version != Version {
		return PlainMessage{}, errors.New("unsupported encrypted envelope version")
	}
	nonceRaw, err := b64.DecodeString(env.Nonce)
	if err != nil {
		return PlainMessage{}, err
	}
	if len(nonceRaw) != chacha20poly1305.NonceSizeX {
		return PlainMessage{}, errors.New("nonce must decode to 24 bytes")
	}
	cipherRaw, err := b64.DecodeString(env.Ciphertext)
	if err != nil {
		return PlainMessage{}, err
	}
	key, err := sharedKey(kp, peer)
	if err != nil {
		return PlainMessage{}, err
	}
	aead, err := chacha20poly1305.NewX(key)
	if err != nil {
		return PlainMessage{}, err
	}
	plain, err := aead.Open(nil, nonceRaw, cipherRaw, nil)
	if err != nil {
		return PlainMessage{}, errors.New("failed to decrypt envelope")
	}
	var msg PlainMessage
	if err := json.Unmarshal(plain, &msg); err != nil {
		return PlainMessage{}, err
	}
	if msg.SessionID != "" && msg.SessionID != env.SessionID {
		return PlainMessage{}, errors.New("encrypted session id does not match envelope")
	}
	if msg.Seq != env.Seq {
		return PlainMessage{}, errors.New("encrypted sequence does not match envelope")
	}
	return msg, nil
}

func sharedKey(kp KeyPair, peer [32]byte) ([]byte, error) {
	return curve25519.X25519(kp.Private[:], peer[:])
}
