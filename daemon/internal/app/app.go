package app

import (
	"context"
	"errors"
	"fmt"
	"os"
	"os/signal"
	"strings"
	"syscall"

	"github.com/codexnomad/codexnomad/daemon/internal/config"
	"github.com/codexnomad/codexnomad/daemon/internal/service"
	"github.com/codexnomad/codexnomad/daemon/internal/session"
)

const usage = `Codex Nomad daemon

Usage:
  codexnomad codex [args...]    Start a remote-controllable Codex session
  codexnomad claude [args...]   Start a remote-controllable Claude Code session
  codexnomad install            Install/autostart the background daemon
  codexnomad start              Start the background daemon in the foreground
  codexnomad status             Show daemon status
  codexnomad stop               Stop the background daemon
  codexnomad logs               Show recent daemon logs

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
	case "codex":
		return session.Run(context.Background(), cfg, session.AgentCodex, rest)
	case "claude":
		return session.Run(context.Background(), cfg, session.AgentClaude, rest)
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
	default:
		return errors.New("unknown command " + cmd + "\n\n" + usage)
	}
}
