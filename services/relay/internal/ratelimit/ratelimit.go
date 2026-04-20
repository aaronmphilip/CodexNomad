package ratelimit

import (
	"net"
	"net/http"
	"strings"
	"sync"
	"time"
)

type Limiter struct {
	mu     sync.Mutex
	window time.Time
	counts map[string]int
	limit  int
}

func New(limitPerMinute int) *Limiter {
	return &Limiter{counts: map[string]int{}, limit: limitPerMinute}
}

func (l *Limiter) Allow(r *http.Request) bool {
	ip := ClientIP(r)
	now := time.Now().UTC().Truncate(time.Minute)
	l.mu.Lock()
	defer l.mu.Unlock()
	if !l.window.Equal(now) {
		l.window = now
		l.counts = map[string]int{}
	}
	l.counts[ip]++
	return l.counts[ip] <= l.limit
}

func ClientIP(r *http.Request) string {
	for _, h := range []string{"CF-Connecting-IP", "Fly-Client-IP", "X-Real-IP"} {
		if v := strings.TrimSpace(r.Header.Get(h)); v != "" {
			return v
		}
	}
	if fwd := r.Header.Get("X-Forwarded-For"); fwd != "" {
		return strings.TrimSpace(strings.Split(fwd, ",")[0])
	}
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err == nil {
		return host
	}
	return r.RemoteAddr
}
