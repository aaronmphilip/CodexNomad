package config

import (
	"errors"
	"net/url"
	"os"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
)

const (
	DefaultRelayURL = "wss://relay.codexnomad.pro/v1/relay"
	appDirName      = "codexnomad"
)

type Config struct {
	RelayURL     string
	RelayToken   string
	ConfigDir    string
	RuntimeDir   string
	LogDir       string
	CodexBin     string
	ClaudeBin    string
	Mode         string
	RequireRelay bool
}

func Load() (Config, error) {
	configDir, err := userConfigDir()
	if err != nil {
		return Config{}, err
	}
	runtimeDir, err := userRuntimeDir()
	if err != nil {
		return Config{}, err
	}

	cfg := Config{
		RelayURL:     env("CODEXNOMAD_RELAY_URL", DefaultRelayURL),
		RelayToken:   os.Getenv("CODEXNOMAD_RELAY_TOKEN"),
		ConfigDir:    configDir,
		RuntimeDir:   runtimeDir,
		LogDir:       filepath.Join(configDir, "logs"),
		CodexBin:     env("CODEXNOMAD_CODEX_BIN", "codex"),
		ClaudeBin:    env("CODEXNOMAD_CLAUDE_BIN", "claude"),
		Mode:         env("CODEXNOMAD_MODE", detectMode()),
		RequireRelay: envBool("CODEXNOMAD_REQUIRE_RELAY"),
	}
	if err := validateRelay(cfg.RelayURL); err != nil {
		return Config{}, err
	}
	for _, dir := range []string{cfg.ConfigDir, cfg.RuntimeDir, cfg.LogDir} {
		if err := os.MkdirAll(dir, 0o700); err != nil {
			return Config{}, err
		}
	}
	return cfg, nil
}

func (c Config) ServicePIDPath() string {
	return filepath.Join(c.RuntimeDir, "daemon.pid")
}

func (c Config) ServiceStatusPath() string {
	return filepath.Join(c.RuntimeDir, "daemon.status")
}

func (c Config) ServiceLogPath() string {
	return filepath.Join(c.LogDir, "daemon.log")
}

func (c Config) SessionLogPath(sessionID string) string {
	return filepath.Join(c.LogDir, "session-"+sessionID+".log")
}

func env(key, fallback string) string {
	if v := strings.TrimSpace(os.Getenv(key)); v != "" {
		return v
	}
	return fallback
}

func envBool(key string) bool {
	v := strings.ToLower(strings.TrimSpace(os.Getenv(key)))
	return v == "1" || v == "true" || v == "yes" || v == "on"
}

func validateRelay(raw string) error {
	u, err := url.Parse(raw)
	if err != nil {
		return err
	}
	if u.Scheme != "wss" && u.Scheme != "ws" {
		return errors.New("CODEXNOMAD_RELAY_URL must start with ws:// or wss://")
	}
	if u.Host == "" {
		return errors.New("CODEXNOMAD_RELAY_URL is missing a host")
	}
	return nil
}

func userConfigDir() (string, error) {
	if runtime.GOOS == "windows" {
		base := os.Getenv("APPDATA")
		if base == "" {
			home, err := os.UserHomeDir()
			if err != nil {
				return "", err
			}
			base = filepath.Join(home, "AppData", "Roaming")
		}
		return filepath.Join(base, "CodexNomad"), nil
	}
	base, err := os.UserConfigDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(base, appDirName), nil
}

func userRuntimeDir() (string, error) {
	if runtime.GOOS == "windows" {
		base := os.Getenv("LOCALAPPDATA")
		if base == "" {
			home, err := os.UserHomeDir()
			if err != nil {
				return "", err
			}
			base = filepath.Join(home, "AppData", "Local")
		}
		return filepath.Join(base, "CodexNomad", "run"), nil
	}
	if xdg := os.Getenv("XDG_RUNTIME_DIR"); xdg != "" {
		return filepath.Join(xdg, appDirName), nil
	}
	return filepath.Join(os.TempDir(), appDirName+"-"+strconv.Itoa(os.Getuid())), nil
}

func detectMode() string {
	if os.Getenv("DIGITALOCEAN_DROPLET_ID") != "" || fileExists("/var/lib/codexnomad/cloud.json") {
		return "cloud"
	}
	return "local"
}

func fileExists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}
