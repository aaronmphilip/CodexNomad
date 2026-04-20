package service

import (
	"bufio"
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"time"

	"github.com/codexnomad/codexnomad/daemon/internal/config"
	"github.com/codexnomad/codexnomad/daemon/internal/logx"
)

func Install(cfg config.Config) error {
	exe, err := os.Executable()
	if err != nil {
		return err
	}
	switch runtime.GOOS {
	case "linux":
		return installSystemdUser(cfg, exe)
	case "darwin":
		return installLaunchd(cfg, exe)
	case "windows":
		return installWindowsTask(exe)
	default:
		return errors.New("unsupported OS for install; run codexnomad start manually")
	}
}

func RunForeground(ctx context.Context, cfg config.Config) error {
	logger, err := logx.New(cfg.ServiceLogPath(), nil)
	if err != nil {
		return err
	}
	defer logger.Close()

	pid := os.Getpid()
	if err := os.WriteFile(cfg.ServicePIDPath(), []byte(strconv.Itoa(pid)), 0o600); err != nil {
		return err
	}
	defer os.Remove(cfg.ServicePIDPath())

	writeStatus := func(state string) {
		body := fmt.Sprintf("state=%s\npid=%d\nmode=%s\nupdated_at=%s\n", state, pid, cfg.Mode, time.Now().UTC().Format(time.RFC3339))
		_ = os.WriteFile(cfg.ServiceStatusPath(), []byte(body), 0o600)
	}
	writeStatus("running")
	defer writeStatus("stopped")

	logger.Printf("codexnomad service started pid=%d mode=%s relay=%s", pid, cfg.Mode, cfg.RelayURL)
	tick := time.NewTicker(30 * time.Second)
	defer tick.Stop()

	for {
		select {
		case <-ctx.Done():
			logger.Printf("codexnomad service stopped: %v", ctx.Err())
			return nil
		case <-tick.C:
			writeStatus("running")
		}
	}
}

func Status(cfg config.Config, w io.Writer) error {
	fmt.Fprintf(w, "Config: %s\nLogs:   %s\n", cfg.ConfigDir, cfg.ServiceLogPath())
	status, err := os.ReadFile(cfg.ServiceStatusPath())
	if err != nil {
		fmt.Fprintln(w, "State:  not running")
		return nil
	}
	fmt.Fprintln(w, string(status))
	return nil
}

func Stop(cfg config.Config) error {
	raw, err := os.ReadFile(cfg.ServicePIDPath())
	if err != nil {
		return errors.New("codexnomad service is not running")
	}
	pid, err := strconv.Atoi(strings.TrimSpace(string(raw)))
	if err != nil {
		return err
	}
	proc, err := os.FindProcess(pid)
	if err != nil {
		return err
	}
	if err := proc.Kill(); err != nil {
		return err
	}
	return nil
}

func Logs(cfg config.Config, w io.Writer, lines int) error {
	fmt.Fprintf(w, "Log file: %s\n\n", cfg.ServiceLogPath())
	return tailFile(cfg.ServiceLogPath(), w, lines)
}

func installSystemdUser(cfg config.Config, exe string) error {
	dir := filepath.Join(os.Getenv("HOME"), ".config", "systemd", "user")
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return err
	}
	servicePath := filepath.Join(dir, "codexnomad.service")
	body := fmt.Sprintf(`[Unit]
Description=Codex Nomad daemon
After=network-online.target

[Service]
Type=simple
ExecStart=%s start
Restart=always
RestartSec=3
Environment=CODEXNOMAD_RELAY_URL=%s

[Install]
WantedBy=default.target
`, exe, cfg.RelayURL)
	if err := os.WriteFile(servicePath, []byte(body), 0o600); err != nil {
		return err
	}
	_ = exec.Command("systemctl", "--user", "daemon-reload").Run()
	_ = exec.Command("systemctl", "--user", "enable", "--now", "codexnomad.service").Run()
	fmt.Printf("Installed systemd user service: %s\n", servicePath)
	return nil
}

func installLaunchd(cfg config.Config, exe string) error {
	home, err := os.UserHomeDir()
	if err != nil {
		return err
	}
	dir := filepath.Join(home, "Library", "LaunchAgents")
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return err
	}
	plistPath := filepath.Join(dir, "pro.codexnomad.daemon.plist")
	body := fmt.Sprintf(`<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>pro.codexnomad.daemon</string>
  <key>ProgramArguments</key>
  <array><string>%s</string><string>start</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>%s</string>
  <key>StandardErrorPath</key><string>%s</string>
</dict>
</plist>
`, exe, cfg.ServiceLogPath(), cfg.ServiceLogPath())
	if err := os.WriteFile(plistPath, []byte(body), 0o600); err != nil {
		return err
	}
	_ = exec.Command("launchctl", "unload", plistPath).Run()
	_ = exec.Command("launchctl", "load", plistPath).Run()
	fmt.Printf("Installed launchd agent: %s\n", plistPath)
	return nil
}

func installWindowsTask(exe string) error {
	name := "CodexNomad"
	task := fmt.Sprintf(`"%s" start`, exe)
	cmd := exec.Command("schtasks", "/Create", "/TN", name, "/TR", task, "/SC", "ONLOGON", "/RL", "LIMITED", "/F")
	out, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("failed to create Windows startup task: %w: %s", err, strings.TrimSpace(string(out)))
	}
	_ = exec.Command("schtasks", "/Run", "/TN", name).Run()
	fmt.Println("Installed Windows logon task: CodexNomad")
	return nil
}

func tailFile(path string, w io.Writer, lines int) error {
	f, err := os.Open(path)
	if err != nil {
		return err
	}
	defer f.Close()
	var ring []string
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		ring = append(ring, scanner.Text())
		if len(ring) > lines {
			copy(ring, ring[1:])
			ring = ring[:lines]
		}
	}
	for _, line := range ring {
		fmt.Fprintln(w, line)
	}
	return scanner.Err()
}
