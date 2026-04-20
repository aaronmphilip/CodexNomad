package auth

import (
	"crypto/subtle"
	"net/http"
	"strings"
)

func CheckSharedToken(r *http.Request, expected string) bool {
	if expected == "" {
		return true
	}
	candidates := []string{
		r.Header.Get("X-CodexNomad-Token"),
		r.Header.Get("X-CodexNomad-Relay-Token"),
	}
	if h := r.Header.Get("Authorization"); strings.HasPrefix(strings.ToLower(h), "bearer ") {
		candidates = append(candidates, strings.TrimSpace(h[7:]))
	}
	for _, got := range candidates {
		if got != "" && subtle.ConstantTimeCompare([]byte(got), []byte(expected)) == 1 {
			return true
		}
	}
	return false
}
