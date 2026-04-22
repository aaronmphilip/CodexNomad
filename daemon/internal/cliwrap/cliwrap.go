package cliwrap

import (
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
)

type Agent string

const (
	AgentCodex  Agent = "codex"
	AgentClaude Agent = "claude"
)

type Resolver struct {
	CodexBin  string
	ClaudeBin string
}

func (r Resolver) Command(agent Agent, args []string) (*exec.Cmd, error) {
	var bin string
	switch agent {
	case AgentCodex:
		bin = r.CodexBin
	case AgentClaude:
		bin = r.ClaudeBin
	default:
		return nil, errors.New("unsupported agent " + string(agent))
	}
	path, err := ResolveExecutable(agent, bin)
	if err != nil {
		return nil, err
	}
	return exec.Command(path, args...), nil
}

func envName(agent Agent) string {
	if agent == AgentClaude {
		return "CLAUDE"
	}
	return "CODEX"
}

func ResolveExecutable(agent Agent, bin string) (string, error) {
	if agent == AgentCodex && runtime.GOOS == "windows" && isBareCommand(bin, "codex") {
		if path := windowsNPMShim("codex.cmd"); path != "" {
			return path, nil
		}
	}

	path, err := exec.LookPath(bin)
	if err != nil {
		return "", notFoundError(agent, bin)
	}
	if agent == AgentCodex && isWindowsCodexAppBinary(path) {
		return "", fmt.Errorf(
			"found the Windows Codex app binary at %s, but that sandbox executable is not launchable by Codex Nomad. Install the Codex CLI with `npm.cmd install -g @openai/codex`, then run `codex.cmd --login`, or set CODEXNOMAD_CODEX_BIN to a runnable CLI path",
			path,
		)
	}
	return path, nil
}

func notFoundError(agent Agent, bin string) error {
	if agent == AgentCodex {
		if runtime.GOOS == "windows" {
			return fmt.Errorf("could not find runnable Codex CLI %q. Install it with `npm.cmd install -g @openai/codex`, then run `codex.cmd --login`, or set CODEXNOMAD_CODEX_BIN", bin)
		}
		return fmt.Errorf("could not find runnable Codex CLI %q on PATH; install the official CLI or set CODEXNOMAD_CODEX_BIN", bin)
	}
	return fmt.Errorf("could not find %s on PATH; install the official CLI or set CODEXNOMAD_%s_BIN", bin, envName(agent))
}

func windowsNPMShim(name string) string {
	appData := strings.TrimSpace(os.Getenv("APPDATA"))
	if appData == "" {
		return ""
	}
	path := filepath.Join(appData, "npm", name)
	if _, err := os.Stat(path); err == nil {
		return path
	}
	return ""
}

func isBareCommand(value, command string) bool {
	value = strings.TrimSpace(strings.Trim(value, `"'`))
	if value == "" {
		return false
	}
	base := strings.TrimSuffix(strings.ToLower(filepath.Base(value)), ".exe")
	base = strings.TrimSuffix(base, ".cmd")
	return base == command && !strings.ContainsAny(value, `/\`)
}

func isWindowsCodexAppBinary(path string) bool {
	if runtime.GOOS != "windows" {
		return false
	}
	normalized := strings.ToLower(filepath.Clean(path))
	return strings.Contains(normalized, `\windowsapps\openai.codex_`) &&
		strings.HasSuffix(normalized, `\app\resources\codex.exe`)
}
