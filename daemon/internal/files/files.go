package files

import (
	"bufio"
	"context"
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

type Entry struct {
	Path     string    `json:"path"`
	Status   string    `json:"status"`
	Size     int64     `json:"size,omitempty"`
	Modified time.Time `json:"modified,omitempty"`
}

type Snapshot struct {
	Root  string  `json:"root"`
	Files []Entry `json:"files"`
}

func GitSnapshot(root string) (Snapshot, error) {
	cmd := exec.Command("git", "-C", root, "status", "--porcelain=v1", "-z")
	out, err := cmd.Output()
	if err != nil {
		return fallbackSnapshot(root)
	}
	parts := strings.Split(string(out), "\x00")
	entries := make([]Entry, 0, len(parts))
	for _, p := range parts {
		if p == "" || len(p) < 4 {
			continue
		}
		status := strings.TrimSpace(p[:2])
		path := strings.TrimSpace(p[3:])
		if strings.Contains(path, " -> ") {
			chunks := strings.Split(path, " -> ")
			path = chunks[len(chunks)-1]
		}
		entry := Entry{Path: filepath.ToSlash(path), Status: status}
		if st, err := os.Stat(filepath.Join(root, filepath.FromSlash(path))); err == nil && !st.IsDir() {
			entry.Size = st.Size()
			entry.Modified = st.ModTime().UTC()
		}
		entries = append(entries, entry)
	}
	return Snapshot{Root: root, Files: entries}, nil
}

func GitDiff(root string, limit int) ([]byte, error) {
	if limit <= 0 {
		limit = 512 * 1024
	}
	var combined []byte
	for _, args := range [][]string{
		{"-C", root, "diff", "--no-ext-diff", "--patch"},
		{"-C", root, "diff", "--cached", "--no-ext-diff", "--patch"},
	} {
		out, err := exec.Command("git", args...).Output()
		if err != nil {
			return nil, err
		}
		if len(out) == 0 {
			continue
		}
		combined = append(combined, out...)
		if len(combined) > 0 && combined[len(combined)-1] != '\n' {
			combined = append(combined, '\n')
		}
	}
	if len(combined) > limit {
		truncated := make([]byte, 0, limit+80)
		truncated = append(truncated, combined[:limit]...)
		truncated = append(truncated, []byte("\n\n[Codex Nomad truncated this diff for mobile review]\n")...)
		return truncated, nil
	}
	return combined, nil
}

func Poll(ctx context.Context, root string, interval time.Duration, emit func(Snapshot)) {
	t := time.NewTicker(interval)
	defer t.Stop()
	var last string
	for {
		snap, err := GitSnapshot(root)
		if err == nil {
			fingerprint := fingerprint(snap)
			if fingerprint != last {
				last = fingerprint
				emit(snap)
			}
		}
		select {
		case <-ctx.Done():
			return
		case <-t.C:
		}
	}
}

func Read(root, rel string, limit int64) ([]byte, error) {
	path, err := safePath(root, rel)
	if err != nil {
		return nil, err
	}
	st, err := os.Stat(path)
	if err != nil {
		return nil, err
	}
	if st.IsDir() {
		return nil, errors.New("cannot read directory")
	}
	if limit > 0 && st.Size() > limit {
		return nil, errors.New("file is too large for mobile read")
	}
	return os.ReadFile(path)
}

func Write(root, rel string, data []byte) error {
	path, err := safePath(root, rel)
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return err
	}
	return os.WriteFile(path, data, 0o600)
}

func safePath(root, rel string) (string, error) {
	if filepath.IsAbs(rel) {
		return "", errors.New("absolute paths are not allowed")
	}
	cleanRoot, err := filepath.Abs(root)
	if err != nil {
		return "", err
	}
	target, err := filepath.Abs(filepath.Join(cleanRoot, filepath.Clean(filepath.FromSlash(rel))))
	if err != nil {
		return "", err
	}
	if target != cleanRoot && !strings.HasPrefix(target, cleanRoot+string(os.PathSeparator)) {
		return "", errors.New("path escapes project root")
	}
	return target, nil
}

func fallbackSnapshot(root string) (Snapshot, error) {
	var entries []Entry
	err := filepath.WalkDir(root, func(path string, d os.DirEntry, err error) error {
		if err != nil {
			return nil
		}
		if d.IsDir() {
			name := d.Name()
			if name == ".git" || name == "node_modules" || name == ".dart_tool" || name == "build" {
				return filepath.SkipDir
			}
			return nil
		}
		rel, err := filepath.Rel(root, path)
		if err != nil {
			return nil
		}
		st, err := d.Info()
		if err != nil {
			return nil
		}
		entries = append(entries, Entry{
			Path:     filepath.ToSlash(rel),
			Status:   "tracked",
			Size:     st.Size(),
			Modified: st.ModTime().UTC(),
		})
		return nil
	})
	return Snapshot{Root: root, Files: entries}, err
}

func fingerprint(s Snapshot) string {
	var b strings.Builder
	w := bufio.NewWriter(&b)
	for _, f := range s.Files {
		_, _ = w.WriteString(f.Status)
		_, _ = w.WriteString(":")
		_, _ = w.WriteString(f.Path)
		_, _ = w.WriteString(":")
		_, _ = w.WriteString(f.Modified.Format(time.RFC3339Nano))
		_, _ = w.WriteString("\n")
	}
	_ = w.Flush()
	return b.String()
}
