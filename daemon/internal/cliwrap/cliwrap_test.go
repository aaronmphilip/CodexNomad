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

func TestWithCodexDefaultsInjectsDisableApps(t *testing.T) {
	t.Setenv("CODEXNOMAD_ALLOW_APPS_MCP", "")
	got := withCodexDefaults([]string{"--model", "gpt-5.4", "hi"})
	wantPrefix := []string{"--disable", "apps"}
	if len(got) < len(wantPrefix) {
		t.Fatalf("withCodexDefaults returned too few args: %v", got)
	}
	if got[0] != wantPrefix[0] || got[1] != wantPrefix[1] {
		t.Fatalf("expected args to start with %v, got %v", wantPrefix, got)
	}
}

func TestWithCodexDefaultsRespectsExplicitAppsFlags(t *testing.T) {
	t.Setenv("CODEXNOMAD_ALLOW_APPS_MCP", "")
	cases := [][]string{
		{"--disable", "apps", "prompt"},
		{"--disable=apps", "prompt"},
		{"--enable", "apps", "prompt"},
		{"--enable=apps", "prompt"},
		{"--disable", "all,apps", "prompt"},
	}
	for _, args := range cases {
		got := withCodexDefaults(args)
		if len(got) != len(args) {
			t.Fatalf("expected args to be unchanged for %v, got %v", args, got)
		}
		for i := range args {
			if got[i] != args[i] {
				t.Fatalf("expected args to be unchanged for %v, got %v", args, got)
			}
		}
	}
}

func TestWithCodexDefaultsAllowsAppsViaEnv(t *testing.T) {
	t.Setenv("CODEXNOMAD_ALLOW_APPS_MCP", "1")
	args := []string{"prompt"}
	got := withCodexDefaults(args)
	if len(got) != len(args) || got[0] != args[0] {
		t.Fatalf("expected args to be unchanged, got %v", got)
	}
}
