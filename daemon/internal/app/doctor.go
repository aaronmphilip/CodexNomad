package app

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"text/tabwriter"
	"time"

	"github.com/codexnomad/codexnomad/daemon/internal/cliwrap"
	"github.com/codexnomad/codexnomad/daemon/internal/config"
	"github.com/codexnomad/codexnomad/daemon/internal/session"
)

type doctorStatus string

const (
	doctorOK   doctorStatus = "OK"
	doctorWarn doctorStatus = "WARN"
	doctorFail doctorStatus = "FAIL"
)

type doctorCheck struct {
	Name   string
	Status doctorStatus
	Detail string
	Fatal  bool
}

func handleDoctor(cfg config.Config, args []string) error {
	target := "all"
	if len(args) > 0 && strings.TrimSpace(args[0]) != "" {
		target = strings.ToLower(strings.TrimSpace(args[0]))
	}
	if target != "all" && target != string(session.AgentCodex) && target != string(session.AgentClaude) {
		return errors.New("usage: codexnomad doctor [codex|claude|all]")
	}

	checks := []doctorCheck{
		checkMachineIdentity(cfg),
		checkWritableRuntime(cfg),
		checkRelayHealth(cfg),
		checkTrustedDevices(cfg),
	}
	checks = append(checks, checkAgentCLIs(cfg, target)...)
	printDoctorChecks(checks)

	var failed []string
	for _, check := range checks {
		if check.Status == doctorFail && check.Fatal {
			failed = append(failed, check.Name)
		}
	}
	if len(failed) > 0 {
		return fmt.Errorf("local setup is not ready: %s", strings.Join(failed, ", "))
	}
	fmt.Fprintln(os.Stdout, "\nLocal setup is ready.")
	return nil
}

func checkMachineIdentity(cfg config.Config) doctorCheck {
	if cfg.MachineID == "" {
		return doctorCheck{Name: "machine identity", Status: doctorFail, Detail: "missing machine id", Fatal: true}
	}
	return doctorCheck{
		Name:   "machine identity",
		Status: doctorOK,
		Detail: fmt.Sprintf("%s (%s)", cfg.MachineName, cfg.MachineID),
	}
}

func checkWritableRuntime(cfg config.Config) doctorCheck {
	if err := os.MkdirAll(cfg.RuntimeDir, 0o700); err != nil {
		return doctorCheck{Name: "runtime directory", Status: doctorFail, Detail: err.Error(), Fatal: true}
	}
	probe := filepath.Join(cfg.RuntimeDir, "doctor-write-test")
	if err := os.WriteFile(probe, []byte(time.Now().UTC().Format(time.RFC3339Nano)), 0o600); err != nil {
		return doctorCheck{Name: "runtime directory", Status: doctorFail, Detail: err.Error(), Fatal: true}
	}
	_ = os.Remove(probe)
	return doctorCheck{Name: "runtime directory", Status: doctorOK, Detail: cfg.RuntimeDir}
}

func checkRelayHealth(cfg config.Config) doctorCheck {
	healthURL, err := relayHealthURL(cfg.RelayURL)
	if err != nil {
		return doctorCheck{Name: "relay", Status: doctorFail, Detail: err.Error(), Fatal: true}
	}
	ctx, cancel := context.WithTimeout(context.Background(), 3500*time.Millisecond)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, healthURL, nil)
	if err != nil {
		return doctorCheck{Name: "relay", Status: doctorFail, Detail: err.Error(), Fatal: true}
	}
	if cfg.RelayToken != "" {
		req.Header.Set("Authorization", "Bearer "+cfg.RelayToken)
		req.Header.Set("X-CodexNomad-Relay-Token", cfg.RelayToken)
	}
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		return doctorCheck{Name: "relay", Status: doctorFail, Detail: fmt.Sprintf("%s is unreachable: %v", healthURL, err), Fatal: true}
	}
	defer res.Body.Close()
	if res.StatusCode < 200 || res.StatusCode >= 300 {
		return doctorCheck{Name: "relay", Status: doctorFail, Detail: fmt.Sprintf("%s returned %s", healthURL, res.Status), Fatal: true}
	}
	return doctorCheck{Name: "relay", Status: doctorOK, Detail: cfg.RelayURL}
}

func checkTrustedDevices(cfg config.Config) doctorCheck {
	devices, err := session.ListAuthorizedDevices(cfg.ConfigDir)
	if err != nil {
		return doctorCheck{Name: "trusted devices", Status: doctorWarn, Detail: err.Error()}
	}
	if len(devices) == 0 {
		return doctorCheck{Name: "trusted devices", Status: doctorWarn, Detail: "none yet; first QR scan will authorize this phone"}
	}
	return doctorCheck{Name: "trusted devices", Status: doctorOK, Detail: fmt.Sprintf("%d trusted", len(devices))}
}

func checkAgentCLIs(cfg config.Config, target string) []doctorCheck {
	checks := make([]doctorCheck, 0, 2)
	if target == "all" || target == string(session.AgentCodex) {
		checks = append(checks, checkOneAgentCLI(cliwrap.AgentCodex, "codex cli", cfg.CodexBin, target == string(session.AgentCodex)))
	}
	if target == "all" || target == string(session.AgentClaude) {
		checks = append(checks, checkOneAgentCLI(cliwrap.AgentClaude, "claude cli", cfg.ClaudeBin, target == string(session.AgentClaude)))
	}
	if target == "all" {
		found := false
		for _, check := range checks {
			if check.Status == doctorOK {
				found = true
				break
			}
		}
		if !found {
			for i := range checks {
				checks[i].Status = doctorFail
				checks[i].Fatal = true
			}
		}
	}
	return checks
}

func checkOneAgentCLI(agent cliwrap.Agent, name, bin string, fatal bool) doctorCheck {
	path, err := cliwrap.ResolveExecutable(agent, bin)
	if err != nil {
		status := doctorWarn
		if fatal {
			status = doctorFail
		}
		return doctorCheck{
			Name:   name,
			Status: status,
			Detail: err.Error(),
			Fatal:  fatal,
		}
	}
	ctx, cancel := context.WithTimeout(context.Background(), 3500*time.Millisecond)
	defer cancel()
	out, err := exec.CommandContext(ctx, path, "--version").CombinedOutput()
	if err != nil {
		status := doctorWarn
		if fatal {
			status = doctorFail
		}
		detail := strings.TrimSpace(string(out))
		if detail == "" {
			detail = err.Error()
		} else {
			detail = detail + ": " + err.Error()
		}
		return doctorCheck{
			Name:   name,
			Status: status,
			Detail: fmt.Sprintf("%s found but not runnable: %s", path, detail),
			Fatal:  fatal,
		}
	}
	version := firstLine(strings.TrimSpace(string(out)))
	if version == "" {
		version = "version check passed"
	}
	return doctorCheck{Name: name, Status: doctorOK, Detail: fmt.Sprintf("%s (%s)", path, version)}
}

func firstLine(text string) string {
	if i := strings.IndexAny(text, "\r\n"); i >= 0 {
		return strings.TrimSpace(text[:i])
	}
	return strings.TrimSpace(text)
}

func relayHealthURL(raw string) (string, error) {
	u, err := url.Parse(raw)
	if err != nil {
		return "", err
	}
	switch u.Scheme {
	case "ws":
		u.Scheme = "http"
	case "wss":
		u.Scheme = "https"
	default:
		return "", errors.New("relay URL must start with ws:// or wss://")
	}
	u.Path = "/healthz"
	u.RawQuery = ""
	u.Fragment = ""
	return u.String(), nil
}

func printDoctorChecks(checks []doctorCheck) {
	fmt.Fprintln(os.Stdout, "Codex Nomad local readiness")
	fmt.Fprintln(os.Stdout)
	w := tabwriter.NewWriter(os.Stdout, 0, 0, 2, ' ', 0)
	fmt.Fprintln(w, "CHECK\tSTATUS\tDETAIL")
	for _, check := range checks {
		fmt.Fprintf(w, "%s\t%s\t%s\n", check.Name, check.Status, check.Detail)
	}
	_ = w.Flush()
}
