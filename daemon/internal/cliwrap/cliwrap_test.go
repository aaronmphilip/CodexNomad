package cliwrap

import (
	"path/filepath"
	"runtime"
	"strings"
	"testing"
)

func TestIsBareCommand(t *testing.T) {
	t.Parallel()
	cases := []struct {
		in   string
		want bool
	}{
		{in: "codex", want: true},
		{in: "codex.exe", want: true},
		{in: "codex.cmd", want: true},
		{in: filepath.Join("bin", "codex"), want: false},
	}
	for _, tc := range cases {
		if got := isBareCommand(tc.in, "codex"); got != tc.want {
			t.Fatalf("isBareCommand(%q) = %v, want %v", tc.in, got, tc.want)
		}
	}
}

func TestResolveExecutableRejectsWindowsCodexAppBinary(t *testing.T) {
	if runtime.GOOS != "windows" {
		t.Skip("Windows-specific app binary path")
	}
	path := `C:\Program Files\WindowsApps\OpenAI.Codex_26.417.5275.0_x64__2p2nqsd0c76g0\app\resources\codex.exe`
	if !isWindowsCodexAppBinary(path) {
		t.Fatal("expected Windows Codex app binary to be detected")
	}
	err := notFoundError(AgentCodex, "codex")
	if err == nil || !strings.Contains(err.Error(), "npm.cmd install -g @openai/codex") {
		t.Fatalf("Codex install hint missing from error: %v", err)
	}
	if !strings.Contains(err.Error(), "codex.cmd login") {
		t.Fatalf("Windows login hint missing from error: %v", err)
	}
}
