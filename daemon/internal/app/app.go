package app

import (
	"context"
	"errors"
	"fmt"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"text/tabwriter"

	"github.com/codexnomad/codexnomad/daemon/internal/config"
	"github.com/codexnomad/codexnomad/daemon/internal/service"
	"github.com/codexnomad/codexnomad/daemon/internal/session"
)

const usage = `Codex Nomad daemon

Usage:
  codexnomad pair [codex|claude]  Start a local agent session and show phone pairing QR
  codexnomad codex [args...]    Start a remote-controllable Codex session
  codexnomad claude [args...]   Start a remote-controllable Claude Code session
  codexnomad cloud-worker       Start a headless cloud Codex/Claude worker
  codexnomad install            Install/autostart the background daemon
  codexnomad start              Start the background daemon in the foreground
  codexnomad status             Show daemon status
  codexnomad stop               Stop the background daemon
  codexnomad logs               Show recent daemon logs
  codexnomad devices            List trusted mobile devices
  codexnomad devices revoke ID  Revoke a trusted mobile device

Environment:
  CODEXNOMAD_RELAY_URL          Relay WebSocket URL. Default: wss://relay.codexnomad.pro/v1/relay
  CODEXNOMAD_REQUIRE_RELAY=1    Fail the session if the relay cannot connect
  CODEXNOMAD_CODEX_BIN          Codex executable override. Default: codex
  CODEXNOMAD_CLAUDE_BIN         Claude executable override. Default: claude
  CODEXNOMAD_MODE=cloud         Mark this machine as a cloud runner
`

func Run(args []string) error {
	if len(args) == 0 {
		fmt.Print(usage)
		return nil
	}

	cfg, err := config.Load()
	if err != nil {
		return err
	}

	cmd := strings.ToLower(args[0])
	rest := args[1:]
	switch cmd {
	case "help", "-h", "--help":
		fmt.Print(usage)
		return nil
	case "pair":
		return handlePair(cfg, rest)
	case "codex":
		return session.Run(context.Background(), cfg, session.AgentCodex, rest)
	case "claude":
		return session.Run(context.Background(), cfg, session.AgentClaude, rest)
	case "cloud-worker":
		return session.RunCloudWorker(context.Background(), cfg, rest)
	case "install":
		return service.Install(cfg)
	case "start":
		ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
		defer stop()
		return service.RunForeground(ctx, cfg)
	case "status":
		return service.Status(cfg, os.Stdout)
	case "stop":
		return service.Stop(cfg)
	case "logs":
		return service.Logs(cfg, os.Stdout, 160)
	case "devices":
		return handleDevices(cfg, rest)
	default:
		return errors.New("unknown command " + cmd + "\n\n" + usage)
	}
}

func handlePair(cfg config.Config, args []string) error {
	agent := session.AgentCodex
	if len(args) > 0 {
		switch strings.ToLower(args[0]) {
		case "codex":
			args = args[1:]
		case "claude":
			agent = session.AgentClaude
			args = args[1:]
		}
	}
	return session.Run(context.Background(), cfg, agent, args)
}

func handleDevices(cfg config.Config, args []string) error {
	if len(args) == 0 || strings.EqualFold(args[0], "list") {
		return listDevices(cfg)
	}
	if strings.EqualFold(args[0], "revoke") {
		if len(args) < 2 {
			return errors.New("usage: codexnomad devices revoke DEVICE_ID")
		}
		removed, err := session.RevokeAuthorizedDevice(cfg.ConfigDir, args[1])
		if err != nil {
			return err
		}
		if !removed {
			return errors.New("trusted mobile device not found: " + args[1])
		}
		fmt.Fprintf(os.Stdout, "Revoked trusted mobile device: %s\n", args[1])
		return nil
	}
	return errors.New("unknown devices command " + args[0] + "\n\nusage: codexnomad devices [list|revoke DEVICE_ID]")
}

func listDevices(cfg config.Config) error {
	devices, err := session.ListAuthorizedDevices(cfg.ConfigDir)
	if err != nil {
		return err
	}
	if len(devices) == 0 {
		fmt.Fprintln(os.Stdout, "No trusted mobile devices.")
		return nil
	}
	w := tabwriter.NewWriter(os.Stdout, 0, 0, 2, ' ', 0)
	fmt.Fprintln(w, "ID\tNAME\tFIRST SEEN\tLAST SEEN")
	for _, device := range devices {
		fmt.Fprintf(
			w,
			"%s\t%s\t%s\t%s\n",
			device.ID,
			device.Name,
			device.FirstSeen.Local().Format("2006-01-02 15:04:05 MST"),
			device.LastSeen.Local().Format("2006-01-02 15:04:05 MST"),
		)
	}
	return w.Flush()
}
