package cliwrap

import (
	"errors"
	"os/exec"
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
	if _, err := exec.LookPath(bin); err != nil {
		return nil, errors.New("could not find " + bin + " on PATH; install the official CLI or set CODEXNOMAD_" + envName(agent) + "_BIN")
	}
	return exec.Command(bin, args...), nil
}

func envName(agent Agent) string {
	if agent == AgentClaude {
		return "CLAUDE"
	}
	return "CODEX"
}
