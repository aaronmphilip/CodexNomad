package session

import (
	"context"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"os"
	"os/exec"
	"sync"
	"time"

	"github.com/codexnomad/codexnomad/daemon/internal/cliwrap"
	"github.com/codexnomad/codexnomad/daemon/internal/config"
	"github.com/codexnomad/codexnomad/daemon/internal/e2ee"
	"github.com/codexnomad/codexnomad/daemon/internal/files"
	"github.com/codexnomad/codexnomad/daemon/internal/logx"
	"github.com/codexnomad/codexnomad/daemon/internal/qr"
	"github.com/codexnomad/codexnomad/daemon/internal/relay"
	"github.com/codexnomad/codexnomad/daemon/internal/terminal"
)

type Agent string

const (
	AgentCodex  Agent = "codex"
	AgentClaude Agent = "claude"
)

type queuedEvent struct {
	typ  string
	data any
}

type RunOptions struct {
	Headless bool
	ServerID string
}

type secureSender struct {
	mu        sync.Mutex
	sessionID string
	kp        e2ee.KeyPair
	peer      [32]byte
	hasPeer   bool
	seq       uint64
	outbound  chan<- relay.WireMessage
	buffer    []queuedEvent
	logger    *log.Logger
}

func Run(parent context.Context, cfg config.Config, agent Agent, args []string) error {
	return run(parent, cfg, agent, args, RunOptions{})
}

func RunCloudWorker(parent context.Context, cfg config.Config, args []string) error {
	agent := Agent(os.Getenv("CODEXNOMAD_AGENT"))
	if agent == "" {
		agent = AgentCodex
	}
	if len(args) > 0 && (args[0] == string(AgentCodex) || args[0] == string(AgentClaude)) {
		agent = Agent(args[0])
		args = args[1:]
	}
	return run(parent, cfg, agent, args, RunOptions{Headless: true, ServerID: cfg.CloudServerID})
}

func run(parent context.Context, cfg config.Config, agent Agent, args []string, opts RunOptions) error {
	ctx, cancel := context.WithCancel(parent)
	defer cancel()

	sessionID, err := newSessionID()
	if err != nil {
		return err
	}
	logger, err := logx.New(cfg.SessionLogPath(sessionID), nil)
	if err != nil {
		return err
	}
	defer logger.Close()

	workdir, err := os.Getwd()
	if err != nil {
		return err
	}
	kp, err := e2ee.GenerateKeyPair()
	if err != nil {
		return err
	}
	publicKey := e2ee.EncodePublicKey(kp.Public)
	inbound := make(chan relay.WireMessage, 256)
	outbound := make(chan relay.WireMessage, 256)
	sender := &secureSender{
		sessionID: sessionID,
		kp:        kp,
		outbound:  outbound,
		logger:    logger.Logger,
	}

	relayErr := make(chan error, 1)
	client := relay.Client{
		URL:       cfg.RelayURL,
		SessionID: sessionID,
		PublicKey: publicKey,
		Token:     cfg.RelayToken,
		Logger:    logger.Logger,
	}
	go func() {
		err := client.Run(ctx, inbound, outbound)
		if err != nil && !errors.Is(err, context.Canceled) {
			logger.Printf("relay disconnected: %v", err)
			if cfg.RequireRelay {
				cancel()
			}
		}
		relayErr <- err
	}()

	resolver := cliwrap.Resolver{CodexBin: cfg.CodexBin, ClaudeBin: cfg.ClaudeBin}
	cmd, err := resolver.Command(cliwrap.Agent(agent), args)
	if err != nil {
		return err
	}
	cmd.Dir = workdir
	cmd.Env = append(os.Environ(),
		"CODEXNOMAD_SESSION_ID="+sessionID,
		"CODEXNOMAD_MODE="+cfg.Mode,
	)

	pairingTTL := 10 * time.Minute
	if opts.Headless {
		pairingTTL = 45 * time.Minute
	}
	expires := time.Now().UTC().Add(pairingTTL)
	pairingPayload := makePairingPayload(cfg, agent, sessionID, publicKey, expires)
	if opts.Headless {
		if err := registerCloudSession(ctx, cfg, pairingPayload); err != nil {
			logger.Printf("cloud session registration failed: %v", err)
			if cfg.RequireRelay {
				return err
			}
		}
	} else {
		if err := printPairingQR(pairingPayload); err != nil {
			return err
		}
	}

	proc, err := terminal.Start(ctx, cmd, func(chunk []byte) {
		_, _ = os.Stdout.Write(chunk)
		sender.Send("terminal_output", map[string]any{
			"encoding": "base64",
			"stream":   "pty",
			"data":     base64.RawStdEncoding.EncodeToString(chunk),
		}, true)
	})
	if err != nil {
		return err
	}

	go handleInbound(ctx, inbound, outbound, sender, proc, workdir, expires, logger.Logger)
	go files.Poll(ctx, workdir, 2*time.Second, func(snap files.Snapshot) {
		sender.Send("file_snapshot", snap, true)
	})

	sender.Send("session_started", map[string]any{
		"session_id": sessionID,
		"agent":      agent,
		"mode":       cfg.Mode,
		"server_id":  opts.ServerID,
		"cwd":        workdir,
		"relay_url":  cfg.RelayURL,
		"cloud":      cloudInfo(),
	}, true)

	err = proc.Wait()
	sender.Send("process_exit", map[string]any{
		"session_id": sessionID,
		"error":      errString(err),
	}, false)
	cancel()

	select {
	case <-relayErr:
	case <-time.After(500 * time.Millisecond):
	}
	return err
}

func makePairingPayload(cfg config.Config, agent Agent, sessionID, publicKey string, expires time.Time) qr.PairingPayload {
	return qr.PairingPayload{
		Version:   1,
		SessionID: sessionID,
		Agent:     string(agent),
		Mode:      cfg.Mode,
		RelayURL:  cfg.RelayURL,
		PublicKey: publicKey,
		CreatedAt: time.Now().UTC().Format(time.RFC3339),
		ExpiresAt: expires.Format(time.RFC3339),
	}
}

func printPairingQR(payload qr.PairingPayload) error {
	content, err := qr.EncodePayload(payload)
	if err != nil {
		return err
	}
	fmt.Println()
	fmt.Println("Codex Nomad session ready")
	fmt.Println("Scan this QR in the Android app. Pairing expires in 10 minutes.")
	fmt.Printf("Session: %s  Agent: %s  Mode: %s\n", payload.SessionID, payload.Agent, payload.Mode)
	return qr.RenderTerminal(os.Stdout, content)
}

func handleInbound(ctx context.Context, inbound <-chan relay.WireMessage, outbound chan<- relay.WireMessage, sender *secureSender, proc *terminal.Process, root string, expires time.Time, logger *log.Logger) {
	for {
		select {
		case <-ctx.Done():
			return
		case msg, ok := <-inbound:
			if !ok {
				return
			}
			switch msg.Type {
			case "mobile_hello":
				if time.Now().UTC().After(expires) {
					queue(outbound, relay.WireMessage{Type: "pairing_expired", SessionID: sender.sessionID, Role: "daemon"}, logger)
					continue
				}
				pub := msg.PublicKey
				if pub == "" && len(msg.Payload) > 0 {
					var p struct {
						PublicKey string `json:"public_key"`
					}
					_ = json.Unmarshal(msg.Payload, &p)
					pub = p.PublicKey
				}
				if err := sender.SetPeer(pub); err != nil {
					logger.Printf("invalid mobile public key: %v", err)
					continue
				}
				queue(outbound, relay.WireMessage{
					Type:      "daemon_ready",
					SessionID: sender.sessionID,
					Role:      "daemon",
					PublicKey: e2ee.EncodePublicKey(sender.kp.Public),
				}, logger)
				sender.Send("session_ready", map[string]any{"session_id": sender.sessionID}, false)
			case "ciphertext":
				if err := handleCiphertext(msg, sender, proc, root); err != nil {
					logger.Printf("mobile command failed: %v", err)
					sender.Send("error", map[string]any{"message": err.Error()}, false)
				}
			case "pong":
			default:
				logger.Printf("ignored relay frame type=%s", msg.Type)
			}
		}
	}
}

func handleCiphertext(msg relay.WireMessage, sender *secureSender, proc *terminal.Process, root string) error {
	var env e2ee.Envelope
	if err := json.Unmarshal(msg.Payload, &env); err != nil {
		return err
	}
	plain, err := sender.Open(env)
	if err != nil {
		return err
	}
	switch plain.Type {
	case "stdin":
		var p struct {
			Text string `json:"text"`
		}
		if err := json.Unmarshal(plain.Data, &p); err != nil {
			return err
		}
		return proc.Write([]byte(p.Text))
	case "interrupt":
		return proc.Interrupt()
	case "approve":
		return proc.Write([]byte("y\n"))
	case "reject":
		return proc.Write([]byte("n\n"))
	case "file_list":
		snap, err := files.GitSnapshot(root)
		if err != nil {
			return err
		}
		sender.Send("file_snapshot", snap, false)
	case "file_read":
		var p struct {
			Path string `json:"path"`
		}
		if err := json.Unmarshal(plain.Data, &p); err != nil {
			return err
		}
		raw, err := files.Read(root, p.Path, 2*1024*1024)
		if err != nil {
			return err
		}
		sender.Send("file_content", map[string]any{
			"path":     p.Path,
			"encoding": "base64",
			"content":  base64.RawStdEncoding.EncodeToString(raw),
		}, false)
	case "file_write":
		var p struct {
			Path     string `json:"path"`
			Encoding string `json:"encoding"`
			Content  string `json:"content"`
		}
		if err := json.Unmarshal(plain.Data, &p); err != nil {
			return err
		}
		var raw []byte
		if p.Encoding == "base64" {
			raw, err = base64.RawStdEncoding.DecodeString(p.Content)
			if err != nil {
				return err
			}
		} else {
			raw = []byte(p.Content)
		}
		if err := files.Write(root, p.Path, raw); err != nil {
			return err
		}
		sender.Send("file_saved", map[string]any{"path": p.Path}, false)
	case "ping":
		sender.Send("pong", map[string]any{"time": time.Now().UTC()}, false)
	default:
		return errors.New("unsupported mobile command " + plain.Type)
	}
	return nil
}

func (s *secureSender) SetPeer(encoded string) error {
	peer, err := e2ee.ParsePublicKey(encoded)
	if err != nil {
		return err
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	s.peer = peer
	s.hasPeer = true
	for _, ev := range s.buffer {
		s.sendLocked(ev.typ, ev.data)
	}
	s.buffer = nil
	return nil
}

func (s *secureSender) Send(typ string, data any, bufferUntilPaired bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if !s.hasPeer {
		if bufferUntilPaired {
			s.buffer = append(s.buffer, queuedEvent{typ: typ, data: data})
			if len(s.buffer) > 128 {
				copy(s.buffer, s.buffer[len(s.buffer)-128:])
				s.buffer = s.buffer[:128]
			}
		}
		return
	}
	s.sendLocked(typ, data)
}

func (s *secureSender) Open(env e2ee.Envelope) (e2ee.PlainMessage, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if !s.hasPeer {
		return e2ee.PlainMessage{}, errors.New("mobile peer has not completed handshake")
	}
	return e2ee.Open(s.kp, s.peer, env)
}

func (s *secureSender) sendLocked(typ string, data any) {
	s.seq++
	env, err := e2ee.Seal(s.sessionID, "daemon", s.seq, s.kp, s.peer, typ, data)
	if err != nil {
		if s.logger != nil {
			s.logger.Printf("encrypt %s failed: %v", typ, err)
		}
		return
	}
	raw, err := json.Marshal(env)
	if err != nil {
		if s.logger != nil {
			s.logger.Printf("marshal encrypted %s failed: %v", typ, err)
		}
		return
	}
	queue(s.outbound, relay.WireMessage{
		Type:      "ciphertext",
		SessionID: s.sessionID,
		Role:      "daemon",
		Payload:   raw,
	}, s.logger)
}

func queue(outbound chan<- relay.WireMessage, msg relay.WireMessage, logger *log.Logger) {
	select {
	case outbound <- msg:
	default:
		if logger != nil {
			logger.Printf("relay outbound queue full; dropped %s", msg.Type)
		}
	}
}

func newSessionID() (string, error) {
	var raw [16]byte
	if _, err := rand.Read(raw[:]); err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(raw[:]), nil
}

func errString(err error) string {
	if err == nil {
		return ""
	}
	return err.Error()
}

func cloudInfo() map[string]any {
	info := map[string]any{
		"tailscale": "unknown",
	}
	if _, err := exec.LookPath("tailscale"); err != nil {
		info["tailscale"] = "not_installed"
		return info
	}
	ctx, cancel := context.WithTimeout(context.Background(), 1500*time.Millisecond)
	defer cancel()
	out, err := exec.CommandContext(ctx, "tailscale", "status", "--json").Output()
	if err != nil {
		info["tailscale"] = "unavailable"
		return info
	}
	if len(out) > 4096 {
		out = out[:4096]
	}
	info["tailscale"] = "available"
	info["status_json_prefix"] = string(out)
	return info
}
