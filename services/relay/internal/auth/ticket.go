package auth

import (
	"crypto/hmac"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/base64"
	"encoding/json"
	"errors"
	"strings"
	"time"
)

type RelayTicket struct {
	Version   int    `json:"v"`
	SessionID string `json:"sid"`
	UserID    string `json:"uid,omitempty"`
	Role      string `json:"role"`
	ExpiresAt int64  `json:"exp"`
}

func SignRelayTicket(t RelayTicket, secret string) (string, error) {
	if secret == "" {
		return "", errors.New("relay ticket secret is not configured")
	}
	if t.Version == 0 {
		t.Version = 1
	}
	if t.ExpiresAt == 0 {
		t.ExpiresAt = time.Now().UTC().Add(10 * time.Minute).Unix()
	}
	raw, err := json.Marshal(t)
	if err != nil {
		return "", err
	}
	payload := base64.RawURLEncoding.EncodeToString(raw)
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write([]byte(payload))
	sig := base64.RawURLEncoding.EncodeToString(mac.Sum(nil))
	return payload + "." + sig, nil
}

func VerifyRelayTicket(token, secret string) (RelayTicket, error) {
	if secret == "" {
		return RelayTicket{}, errors.New("relay ticket secret is not configured")
	}
	parts := strings.Split(token, ".")
	if len(parts) != 2 {
		return RelayTicket{}, errors.New("invalid relay ticket format")
	}
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write([]byte(parts[0]))
	expected := base64.RawURLEncoding.EncodeToString(mac.Sum(nil))
	if subtle.ConstantTimeCompare([]byte(expected), []byte(parts[1])) != 1 {
		return RelayTicket{}, errors.New("invalid relay ticket signature")
	}
	raw, err := base64.RawURLEncoding.DecodeString(parts[0])
	if err != nil {
		return RelayTicket{}, err
	}
	var t RelayTicket
	if err := json.Unmarshal(raw, &t); err != nil {
		return RelayTicket{}, err
	}
	if t.Version != 1 {
		return RelayTicket{}, errors.New("unsupported relay ticket version")
	}
	if t.SessionID == "" || t.Role == "" {
		return RelayTicket{}, errors.New("relay ticket missing sid or role")
	}
	if time.Now().UTC().Unix() > t.ExpiresAt {
		return RelayTicket{}, errors.New("relay ticket expired")
	}
	return t, nil
}

func BearerToken(authHeader string) string {
	if strings.HasPrefix(strings.ToLower(authHeader), "bearer ") {
		return strings.TrimSpace(authHeader[7:])
	}
	return ""
}
