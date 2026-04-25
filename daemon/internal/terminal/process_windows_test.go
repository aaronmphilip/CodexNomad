//go:build windows

package terminal

import (
	"bytes"
	"context"
	"os/exec"
	"strings"
	"sync"
	"testing"
	"time"
)

func TestWindowsConPTYRunsInteractiveCommand(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	var mu sync.Mutex
	var out bytes.Buffer
	proc, err := Start(ctx, exec.Command("cmd.exe", "/Q", "/K", "echo READY"), func(chunk []byte) {
		mu.Lock()
		defer mu.Unlock()
		out.Write(chunk)
	})
	if err != nil {
		t.Fatalf("Start returned error: %v", err)
	}
	defer func() {
		_ = proc.Interrupt()
		_ = proc.Wait()
	}()

	waitForText(t, ctx, &mu, &out, "READY")
	if err := proc.Write([]byte("echo SMOKE_OK\n")); err != nil {
		t.Fatalf("Write returned error: %v", err)
	}
	waitForText(t, ctx, &mu, &out, "SMOKE_OK")
}

func TestNormalizeInputUsesCRLFForEnter(t *testing.T) {
	tests := map[string]string{
		"hello\n":        "hello\r\n",
		"hello\r\n":      "hello\r\n",
		"hello\nworld\n": "hello\r\nworld\r\n",
	}
	for input, want := range tests {
		if got := string(normalizeInput([]byte(input))); got != want {
			t.Fatalf("normalizeInput(%q) = %q, want %q", input, got, want)
		}
	}
}

func waitForText(t *testing.T, ctx context.Context, mu *sync.Mutex, out *bytes.Buffer, text string) {
	t.Helper()
	for {
		mu.Lock()
		got := out.String()
		mu.Unlock()
		if strings.Contains(got, text) {
			return
		}
		select {
		case <-ctx.Done():
			t.Fatalf("timed out waiting for %q in output:\n%s", text, got)
		case <-time.After(50 * time.Millisecond):
		}
	}
}
