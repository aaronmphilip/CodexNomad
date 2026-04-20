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

type SupabaseClaims struct {
	Subject string `json:"sub"`
	Email   string `json:"email"`
	Expiry  int64  `json:"exp"`
	Issuer  string `json:"iss"`
}

func VerifySupabaseJWT(token, secret string) (SupabaseClaims, error) {
	if secret == "" {
		return SupabaseClaims{}, errors.New("SUPABASE_JWT_SECRET is not configured")
	}
	parts := strings.Split(token, ".")
	if len(parts) != 3 {
		return SupabaseClaims{}, errors.New("invalid JWT format")
	}
	headerRaw, err := base64.RawURLEncoding.DecodeString(parts[0])
	if err != nil {
		return SupabaseClaims{}, err
	}
	var header struct {
		Alg string `json:"alg"`
		Typ string `json:"typ"`
	}
	if err := json.Unmarshal(headerRaw, &header); err != nil {
		return SupabaseClaims{}, err
	}
	if header.Alg != "HS256" {
		return SupabaseClaims{}, errors.New("unsupported JWT algorithm")
	}
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write([]byte(parts[0] + "." + parts[1]))
	expected := base64.RawURLEncoding.EncodeToString(mac.Sum(nil))
	if subtle.ConstantTimeCompare([]byte(expected), []byte(parts[2])) != 1 {
		return SupabaseClaims{}, errors.New("invalid JWT signature")
	}
	claimsRaw, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		return SupabaseClaims{}, err
	}
	var claims SupabaseClaims
	if err := json.Unmarshal(claimsRaw, &claims); err != nil {
		return SupabaseClaims{}, err
	}
	if claims.Subject == "" {
		return SupabaseClaims{}, errors.New("JWT subject is empty")
	}
	if claims.Expiry != 0 && time.Now().UTC().Unix() > claims.Expiry {
		return SupabaseClaims{}, errors.New("JWT expired")
	}
	return claims, nil
}
