package webhook

import (
	"crypto/hmac"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"strconv"
	"strings"
	"time"
)

func verifyRazorpay(raw []byte, signature, secret string) bool {
	if secret == "" || signature == "" {
		return false
	}
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write(raw)
	expected := hex.EncodeToString(mac.Sum(nil))
	return subtle.ConstantTimeCompare([]byte(expected), []byte(signature)) == 1
}

func verifyPolarStandardWebhook(raw []byte, webhookID, timestamp, signature, secret string) error {
	if secret == "" {
		return errors.New("POLAR_WEBHOOK_SECRET is not configured")
	}
	if webhookID == "" || timestamp == "" || signature == "" {
		return errors.New("missing Polar webhook signature headers")
	}
	ts, err := strconv.ParseInt(timestamp, 10, 64)
	if err != nil {
		return errors.New("invalid Polar webhook timestamp")
	}
	sentAt := time.Unix(ts, 0)
	if time.Since(sentAt) > 5*time.Minute || time.Until(sentAt) > 5*time.Minute {
		return errors.New("Polar webhook timestamp outside replay window")
	}
	key := decodeWebhookSecret(secret)
	signed := webhookID + "." + timestamp + "." + string(raw)
	mac := hmac.New(sha256.New, key)
	mac.Write([]byte(signed))
	expected := base64.StdEncoding.EncodeToString(mac.Sum(nil))
	for _, token := range strings.Fields(signature) {
		token = strings.TrimSpace(token)
		candidates := []string{token}
		if strings.HasPrefix(token, "v1,") {
			candidates = append(candidates, strings.TrimPrefix(token, "v1,"))
		}
		if strings.HasPrefix(token, "v1=") {
			candidates = append(candidates, strings.TrimPrefix(token, "v1="))
		}
		parts := strings.Split(token, ",")
		for i := 0; i < len(parts)-1; i++ {
			if strings.TrimSpace(parts[i]) == "v1" {
				candidates = append(candidates, strings.TrimSpace(parts[i+1]))
			}
		}
		for _, sig := range candidates {
			if sig != "" && subtle.ConstantTimeCompare([]byte(expected), []byte(sig)) == 1 {
				return nil
			}
		}
	}
	return errors.New("invalid Polar webhook signature")
}

func decodeWebhookSecret(secret string) []byte {
	trimmed := strings.TrimSpace(secret)
	candidates := []string{trimmed}
	if i := strings.LastIndex(trimmed, "_"); i >= 0 && i+1 < len(trimmed) {
		candidates = append(candidates, trimmed[i+1:])
	}
	for _, c := range candidates {
		if raw, err := base64.StdEncoding.DecodeString(c); err == nil {
			return raw
		}
		if raw, err := base64.RawStdEncoding.DecodeString(c); err == nil {
			return raw
		}
	}
	return []byte(trimmed)
}
