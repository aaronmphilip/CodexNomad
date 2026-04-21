package session

import (
	"crypto/sha1"
	"encoding/hex"
	"regexp"
	"strings"
	"time"
)

type permissionDetector struct {
	agent     Agent
	recent    string
	lastID    string
	lastAt    time.Time
	patterns  []*regexp.Regexp
	extractor *regexp.Regexp
}

type permissionEvent struct {
	ID     string
	Title  string
	Detail string
	Risk   string
}

func newPermissionDetector(agent Agent) *permissionDetector {
	return &permissionDetector{
		agent: agent,
		patterns: []*regexp.Regexp{
			regexp.MustCompile(`(?i)\b(permission|approve|allow|deny|confirmation|required|proceed|continue)\b`),
			regexp.MustCompile(`(?i)\b(y\/n|yes\/no|accept|reject)\b`),
			regexp.MustCompile(`(?i)\b(run|execute|modify|write|edit|delete|install|apply)\b`),
		},
		extractor: regexp.MustCompile("(?i)(run|execute|modify|write|edit|delete|install|apply|proceed|continue)[^\\r\\n]{0,220}"),
	}
}

func (d *permissionDetector) Observe(chunk []byte) (permissionEvent, bool) {
	text := stripANSI(string(chunk))
	if strings.TrimSpace(text) == "" {
		return permissionEvent{}, false
	}
	d.recent += text
	if len(d.recent) > 6000 {
		d.recent = d.recent[len(d.recent)-6000:]
	}
	window := strings.TrimSpace(d.recent)
	if !d.looksLikePermission(window) {
		return permissionEvent{}, false
	}
	detail := d.extractDetail(window)
	id := stablePromptID(string(d.agent), detail)
	if id == d.lastID && time.Since(d.lastAt) < 2*time.Minute {
		return permissionEvent{}, false
	}
	d.lastID = id
	d.lastAt = time.Now()
	return permissionEvent{
		ID:     id,
		Title:  "Permission requested",
		Detail: detail,
		Risk:   riskFor(detail),
	}, true
}

func (d *permissionDetector) looksLikePermission(text string) bool {
	lower := strings.ToLower(text)
	if strings.Contains(lower, "permission") && (strings.Contains(lower, "allow") || strings.Contains(lower, "approve")) {
		return true
	}
	if strings.Contains(lower, "do you want to") && (strings.Contains(lower, "y/n") || strings.Contains(lower, "yes")) {
		return true
	}
	if strings.Contains(lower, "continue?") || strings.Contains(lower, "proceed?") {
		return true
	}
	matches := 0
	for _, pattern := range d.patterns {
		if pattern.MatchString(text) {
			matches++
		}
	}
	return matches >= 2
}

func (d *permissionDetector) extractDetail(text string) string {
	lines := compactLines(text)
	for i := len(lines) - 1; i >= 0; i-- {
		line := lines[i]
		if d.extractor.MatchString(line) || strings.Contains(strings.ToLower(line), "permission") {
			return clamp(line, 240)
		}
	}
	if len(lines) > 0 {
		return clamp(lines[len(lines)-1], 240)
	}
	return "The agent is waiting for approval."
}

func compactLines(text string) []string {
	raw := strings.FieldsFunc(text, func(r rune) bool {
		return r == '\n' || r == '\r'
	})
	lines := make([]string, 0, len(raw))
	for _, line := range raw {
		line = strings.Join(strings.Fields(line), " ")
		if line != "" {
			lines = append(lines, line)
		}
	}
	return lines
}

func stablePromptID(agent, detail string) string {
	sum := sha1.Sum([]byte(agent + ":" + detail))
	return "perm_" + hex.EncodeToString(sum[:8])
}

func riskFor(detail string) string {
	lower := strings.ToLower(detail)
	for _, token := range []string{"delete", "remove", "rm ", "drop", "reset", "checkout", "install", "sudo", "chmod", "chown"} {
		if strings.Contains(lower, token) {
			return "high"
		}
	}
	for _, token := range []string{"write", "edit", "modify", "apply", "patch"} {
		if strings.Contains(lower, token) {
			return "medium"
		}
	}
	return "low"
}

func clamp(text string, limit int) string {
	if len(text) <= limit {
		return text
	}
	return strings.TrimSpace(text[:limit]) + "..."
}

var ansiRE = regexp.MustCompile(`\x1b\[[0-9;?]*[ -/]*[@-~]`)

func stripANSI(text string) string {
	return ansiRE.ReplaceAllString(text, "")
}
