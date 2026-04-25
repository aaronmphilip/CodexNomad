package session

import (
	"bytes"
	"context"
	"crypto/rand"
	"encoding/base64"
	"encoding/csv"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"sort"
	"strconv"
	"strings"
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
	peerKey   string
	peerDevID string
	hasPeer   bool
	seq       uint64
	lastRecv  uint64
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
	devices := newDeviceRegistry(cfg.ConfigDir)
	sender := &secureSender{
		sessionID: sessionID,
		kp:        kp,
		outbound:  outbound,
		logger:    logger.Logger,
	}
	permissions := newPermissionDetector(agent)
	preview, err := startPreviewProxy(ctx, logger.Logger)
	if err != nil {
		logger.Printf("preview proxy unavailable: %v", err)
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
		if event, ok := permissions.Observe(chunk); ok {
			sender.Send("permission_requested", map[string]any{
				"id":      event.ID,
				"agent":   agent,
				"title":   event.Title,
				"detail":  event.Detail,
				"risk":    event.Risk,
				"actions": []string{"approve_once", "reject", "interrupt"},
			}, true)
		}
	})
	if err != nil {
		return err
	}

	go handleInbound(ctx, inbound, outbound, sender, proc, workdir, expires, devices, logger.Logger, preview)
	go files.Poll(ctx, workdir, 2*time.Second, func(snap files.Snapshot) {
		sender.Send("file_snapshot", snap, true)
		if len(snap.Files) == 0 {
			return
		}
		patch, err := files.GitDiff(workdir, 256*1024)
		if err != nil || len(patch) == 0 {
			return
		}
		sender.Send("diff_ready", map[string]any{
			"file_path": "Working tree",
			"summary":   fmt.Sprintf("%d changed %s", len(snap.Files), plural("file", len(snap.Files))),
			"encoding":  "base64",
			"patch":     base64.RawStdEncoding.EncodeToString(patch),
			"files":     snap.Files,
		}, true)
	})

	sender.Send("session_started", map[string]any{
		"session_id": sessionID,
		"agent":      agent,
		"mode":       cfg.Mode,
		"server_id":  opts.ServerID,
		"cwd":        workdir,
		"relay_url":  cfg.RelayURL,
		"machine": map[string]any{
			"id":   cfg.MachineID,
			"name": cfg.MachineName,
			"os":   cfg.MachineOS,
		},
		"cloud": cloudInfo(),
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
		Version:     1,
		SessionID:   sessionID,
		Agent:       string(agent),
		Mode:        cfg.Mode,
		RelayURL:    cfg.RelayURL,
		PublicKey:   publicKey,
		MachineID:   cfg.MachineID,
		MachineName: cfg.MachineName,
		MachineOS:   cfg.MachineOS,
		CreatedAt:   time.Now().UTC().Format(time.RFC3339),
		ExpiresAt:   expires.Format(time.RFC3339),
	}
}

func printPairingQR(payload qr.PairingPayload) error {
	content, err := qr.EncodePayload(payload)
	if err != nil {
		return err
	}
	if os.Getenv("CODEXNOMAD_PRINT_PAIRING_URI") == "1" {
		fmt.Printf("Pairing URI: %s\n", content)
	}
	pngPath := filepath.Join(os.TempDir(), "codexnomad-"+payload.SessionID+".png")
	if err := qr.WritePNG(content, pngPath, 768); err == nil {
		fmt.Printf("QR image: %s\n", pngPath)
		fmt.Println("If the terminal QR is not scannable, scan the QR image instead.")
		if os.Getenv("CODEXNOMAD_OPEN_QR") == "1" {
			_ = openFile(pngPath)
		}
	} else {
		fmt.Printf("Could not write QR image: %v\n", err)
	}
	fmt.Println()
	fmt.Println("Codex Nomad session ready")
	fmt.Println("Scan this QR in the Android app. Pairing expires in 10 minutes.")
	fmt.Printf("Session: %s  Agent: %s  Mode: %s\n", payload.SessionID, payload.Agent, payload.Mode)
	if payload.MachineName != "" {
		fmt.Printf("Machine: %s  OS: %s  ID: %s\n", payload.MachineName, payload.MachineOS, payload.MachineID)
	}
	if os.Getenv("CODEXNOMAD_SUPPRESS_TERMINAL_QR") == "1" {
		return nil
	}
	return qr.RenderTerminal(os.Stdout, content)
}

func openFile(path string) error {
	var cmd *exec.Cmd
	switch runtime.GOOS {
	case "windows":
		cmd = exec.Command("rundll32", "url.dll,FileProtocolHandler", path)
	case "darwin":
		cmd = exec.Command("open", path)
	default:
		cmd = exec.Command("xdg-open", path)
	}
	return cmd.Start()
}

func handleInbound(ctx context.Context, inbound <-chan relay.WireMessage, outbound chan<- relay.WireMessage, sender *secureSender, proc *terminal.Process, root string, expires time.Time, devices deviceRegistry, logger *log.Logger, preview *previewProxy) {
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
				pub := msg.PublicKey
				if pub == "" && len(msg.Payload) > 0 {
					var p struct {
						PublicKey  string `json:"public_key"`
						DeviceID   string `json:"device_id"`
						DeviceName string `json:"device_name"`
					}
					_ = json.Unmarshal(msg.Payload, &p)
					pub = p.PublicKey
					msg.DeviceID = p.DeviceID
					msg.DeviceName = p.DeviceName
				}
				if msg.DeviceID == "" {
					queue(outbound, relay.WireMessage{Type: "device_identity_required", SessionID: sender.sessionID, Role: "daemon"}, logger)
					continue
				}
				knownDevice := devices.IsAuthorized(msg.DeviceID, pub)
				if time.Now().UTC().After(expires) && !knownDevice {
					queue(outbound, relay.WireMessage{Type: "pairing_expired", SessionID: sender.sessionID, Role: "daemon"}, logger)
					continue
				}
				if _, err := e2ee.ParsePublicKey(pub); err != nil {
					logger.Printf("invalid mobile public key: %v", err)
					continue
				}
				if !knownDevice {
					if err := devices.Authorize(msg.DeviceID, msg.DeviceName, pub); err != nil {
						logger.Printf("authorize mobile device failed: %v", err)
						queue(outbound, relay.WireMessage{Type: "device_authorization_failed", SessionID: sender.sessionID, Role: "daemon"}, logger)
						continue
					}
				} else if err := devices.Touch(msg.DeviceID); err != nil {
					logger.Printf("touch mobile device failed: %v", err)
				}
				if err := sender.SetPeer(pub, msg.DeviceID); err != nil {
					logger.Printf("invalid mobile public key: %v", err)
					continue
				}
				queue(outbound, relay.WireMessage{
					Type:      "daemon_ready",
					SessionID: sender.sessionID,
					Role:      "daemon",
					PublicKey: e2ee.EncodePublicKey(sender.kp.Public),
					DeviceID:  msg.DeviceID,
				}, logger)
				sender.Send("session_ready", map[string]any{
					"session_id":  sender.sessionID,
					"device_id":   msg.DeviceID,
					"device_name": msg.DeviceName,
				}, false)
			case "ciphertext":
				if err := handleCiphertext(msg, sender, proc, root, devices, preview); err != nil {
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

func handleCiphertext(msg relay.WireMessage, sender *secureSender, proc *terminal.Process, root string, devices deviceRegistry, preview *previewProxy) error {
	deviceID, peerKey, ok := sender.PeerIdentity()
	if !ok || !devices.IsAuthorized(deviceID, peerKey) {
		return errors.New("mobile device is not authorized")
	}
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
		id := commandID(plain.Data)
		if err := proc.Interrupt(); err != nil {
			return err
		}
		sender.Send("permission_resolved", map[string]any{
			"id":     id,
			"action": "interrupt",
		}, false)
	case "approve":
		id := commandID(plain.Data)
		if err := proc.Write([]byte("y\n")); err != nil {
			return err
		}
		sender.Send("permission_resolved", map[string]any{
			"id":     id,
			"action": "approve_once",
		}, false)
	case "reject":
		id := commandID(plain.Data)
		if err := proc.Write([]byte("n\n")); err != nil {
			return err
		}
		sender.Send("permission_resolved", map[string]any{
			"id":     id,
			"action": "reject",
		}, false)
	case "file_list":
		snap, err := files.ProjectSnapshot(root)
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
	case "file_delete":
		var p struct {
			Path string `json:"path"`
		}
		if err := json.Unmarshal(plain.Data, &p); err != nil {
			return err
		}
		if strings.TrimSpace(p.Path) == "" {
			return errors.New("file path is required")
		}
		if err := files.Delete(root, p.Path); err != nil {
			return err
		}
		sender.Send("file_deleted", map[string]any{"path": p.Path}, false)
	case "file_rename":
		var p struct {
			From string `json:"from"`
			To   string `json:"to"`
		}
		if err := json.Unmarshal(plain.Data, &p); err != nil {
			return err
		}
		if strings.TrimSpace(p.From) == "" || strings.TrimSpace(p.To) == "" {
			return errors.New("rename requires source and target paths")
		}
		if err := files.Rename(root, p.From, p.To); err != nil {
			return err
		}
		sender.Send("file_renamed", map[string]any{
			"from": p.From,
			"to":   p.To,
		}, false)
	case "folder_create":
		var p struct {
			Path string `json:"path"`
		}
		if err := json.Unmarshal(plain.Data, &p); err != nil {
			return err
		}
		if strings.TrimSpace(p.Path) == "" {
			return errors.New("folder path is required")
		}
		if err := files.Mkdir(root, p.Path); err != nil {
			return err
		}
		sender.Send("folder_created", map[string]any{"path": p.Path}, false)
	case "workspace_tools":
		sender.Send("workspace_tools", workspaceTools(root, preview), false)
	case "git_action":
		var p struct {
			Action  string `json:"action"`
			Message string `json:"message"`
			Branch  string `json:"branch"`
		}
		if err := json.Unmarshal(plain.Data, &p); err != nil {
			return err
		}
		result := runGitAction(root, p.Action, p.Message, p.Branch)
		sender.Send("git_action_result", result, false)
		if ok, _ := result["ok"].(bool); ok {
			sender.Send("workspace_tools", workspaceTools(root, preview), false)
			if snap, err := files.ProjectSnapshot(root); err == nil {
				sender.Send("file_snapshot", snap, false)
			}
		}
	case "ping":
		sender.Send("pong", map[string]any{"time": time.Now().UTC()}, false)
	default:
		return errors.New("unsupported mobile command " + plain.Type)
	}
	return nil
}

func commandID(raw json.RawMessage) string {
	var p struct {
		ID string `json:"id"`
	}
	if len(raw) == 0 {
		return ""
	}
	_ = json.Unmarshal(raw, &p)
	return p.ID
}

type previewProxy struct {
	mu       sync.Mutex
	token    string
	host     string
	port     int
	server   *http.Server
	logger   *log.Logger
	requests []previewRequestLog
}

type previewRequestLog struct {
	Time       string `json:"time"`
	Method     string `json:"method"`
	Path       string `json:"path"`
	Status     int    `json:"status"`
	DurationMs int64  `json:"duration_ms"`
	Error      string `json:"error,omitempty"`
}

type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (w *statusRecorder) WriteHeader(code int) {
	w.status = code
	w.ResponseWriter.WriteHeader(code)
}

func startPreviewProxy(ctx context.Context, logger *log.Logger) (*previewProxy, error) {
	token, err := newSessionID()
	if err != nil {
		return nil, err
	}
	host := localLANIP()
	if host == "" {
		host = "127.0.0.1"
	}
	proxy := &previewProxy{
		token:  token,
		host:   host,
		logger: logger,
	}
	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok"))
	})
	mux.HandleFunc("/v1/preview/", proxy.handle)
	proxy.server = &http.Server{
		Handler:           mux,
		ReadHeaderTimeout: 5 * time.Second,
	}
	ln, err := net.Listen("tcp", "0.0.0.0:0")
	if err != nil {
		return nil, err
	}
	addr, ok := ln.Addr().(*net.TCPAddr)
	if !ok {
		_ = ln.Close()
		return nil, errors.New("preview proxy failed to resolve tcp listener")
	}
	proxy.port = addr.Port

	go func() {
		<-ctx.Done()
		closeCtx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		defer cancel()
		_ = proxy.server.Shutdown(closeCtx)
	}()
	go func() {
		err := proxy.server.Serve(ln)
		if err != nil && !errors.Is(err, http.ErrServerClosed) && proxy.logger != nil {
			proxy.logger.Printf("preview proxy stopped: %v", err)
		}
	}()
	if logger != nil {
		logger.Printf("preview proxy listening at http://%s:%d/v1/preview/<token>/<port>/", proxy.host, proxy.port)
	}
	return proxy, nil
}

func (p *previewProxy) handle(w http.ResponseWriter, r *http.Request) {
	started := time.Now()
	token, port, suffix, ok := parsePreviewRequest(r.URL.Path)
	if !ok {
		http.NotFound(w, r)
		p.recordRequest(r.Method, r.URL.Path, http.StatusNotFound, time.Since(started), "invalid preview path")
		return
	}
	if token != p.token {
		http.Error(w, "forbidden", http.StatusForbidden)
		p.recordRequest(r.Method, r.URL.Path, http.StatusForbidden, time.Since(started), "invalid preview token")
		return
	}
	target := &url.URL{
		Scheme: "http",
		Host:   net.JoinHostPort("127.0.0.1", strconv.Itoa(port)),
	}
	proxy := httputil.NewSingleHostReverseProxy(target)
	logged := false
	originalDirector := proxy.Director
	proxy.Director = func(req *http.Request) {
		originalDirector(req)
		req.URL.Path = suffix
		req.URL.RawPath = ""
		req.Host = target.Host
	}
	proxy.ErrorHandler = func(w http.ResponseWriter, _ *http.Request, err error) {
		if p.logger != nil {
			p.logger.Printf("preview proxy error on port %d: %v", port, err)
		}
		logged = true
		p.recordRequest(
			r.Method,
			requestPathWithQuery(suffix, r.URL.RawQuery),
			http.StatusBadGateway,
			time.Since(started),
			err.Error(),
		)
		http.Error(w, "preview target unavailable", http.StatusBadGateway)
	}
	recorder := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
	proxy.ServeHTTP(recorder, r)
	if !logged {
		p.recordRequest(
			r.Method,
			requestPathWithQuery(suffix, r.URL.RawQuery),
			recorder.status,
			time.Since(started),
			"",
		)
	}
}

func (p *previewProxy) urlFor(port int) string {
	if p == nil || port <= 0 {
		return ""
	}
	return fmt.Sprintf("http://%s:%d/v1/preview/%s/%d/", p.host, p.port, p.token, port)
}

func parsePreviewRequest(path string) (token string, port int, suffix string, ok bool) {
	const prefix = "/v1/preview/"
	if !strings.HasPrefix(path, prefix) {
		return "", 0, "", false
	}
	raw := strings.TrimPrefix(path, prefix)
	parts := strings.Split(raw, "/")
	if len(parts) < 2 || parts[0] == "" {
		return "", 0, "", false
	}
	value, err := strconv.Atoi(parts[1])
	if err != nil || value < 1 || value > 65535 {
		return "", 0, "", false
	}
	next := "/"
	if len(parts) > 2 {
		next = "/" + strings.Join(parts[2:], "/")
	}
	next = "/" + strings.TrimLeft(next, "/")
	return parts[0], value, next, true
}

func requestPathWithQuery(path, query string) string {
	if strings.TrimSpace(query) == "" {
		return path
	}
	return path + "?" + query
}

func (p *previewProxy) recordRequest(method, path string, status int, duration time.Duration, requestErr string) {
	if p == nil {
		return
	}
	if status == 0 {
		status = http.StatusOK
	}
	entry := previewRequestLog{
		Time:       time.Now().UTC().Format(time.RFC3339),
		Method:     method,
		Path:       path,
		Status:     status,
		DurationMs: duration.Milliseconds(),
		Error:      requestErr,
	}
	p.mu.Lock()
	defer p.mu.Unlock()
	p.requests = append(p.requests, entry)
	if len(p.requests) > 40 {
		p.requests = p.requests[len(p.requests)-40:]
	}
}

func (p *previewProxy) recentRequests() []previewRequestLog {
	if p == nil {
		return nil
	}
	p.mu.Lock()
	defer p.mu.Unlock()
	count := len(p.requests)
	if count > 20 {
		count = 20
	}
	out := make([]previewRequestLog, 0, count)
	for i := len(p.requests) - 1; i >= 0 && len(out) < count; i-- {
		out = append(out, p.requests[i])
	}
	return out
}

func (p *previewProxy) baseURL() string {
	if p == nil || p.port <= 0 || p.host == "" {
		return ""
	}
	return fmt.Sprintf("http://%s:%d/v1/preview/%s/", p.host, p.port, p.token)
}

type portEntry struct {
	Port     int    `json:"port"`
	Protocol string `json:"protocol"`
	Address  string `json:"address"`
	PID      string `json:"pid,omitempty"`
	Process  string `json:"process,omitempty"`
	URL      string `json:"url,omitempty"`
	Direct   string `json:"direct_url,omitempty"`
}

func workspaceTools(root string, preview *previewProxy) map[string]any {
	ports := listeningPorts(preview)
	previewMeta := map[string]any{
		"enabled":         preview != nil,
		"proxy_url":       "",
		"recent_requests": []previewRequestLog{},
	}
	if preview != nil {
		previewMeta["proxy_url"] = preview.baseURL()
		previewMeta["recent_requests"] = preview.recentRequests()
	}
	return map[string]any{
		"git":         gitSummary(root),
		"ports":       ports,
		"preview_url": bestPreviewURL(ports),
		"preview":     previewMeta,
		"updated_at":  time.Now().UTC().Format(time.RFC3339),
	}
}

func gitSummary(root string) map[string]any {
	out, err := exec.Command("git", "-C", root, "status", "-sb", "--porcelain=v1").Output()
	if err != nil {
		return map[string]any{}
	}
	first := ""
	for _, line := range strings.Split(string(out), "\n") {
		line = strings.TrimSpace(line)
		if strings.HasPrefix(line, "## ") {
			first = strings.TrimPrefix(line, "## ")
			break
		}
	}
	branch, remote, ahead, behind := parseGitStatusHeader(first)
	lastCommit := strings.TrimSpace(runGit(root, "log", "-1", "--pretty=format:%h %s"))
	branchesOut := strings.TrimSpace(runGit(root, "branch", "--format=%(refname:short)"))
	var branches []string
	if branchesOut != "" {
		for _, value := range strings.Split(branchesOut, "\n") {
			trimmed := strings.TrimSpace(value)
			if trimmed != "" {
				branches = append(branches, trimmed)
			}
		}
	}
	snap, _ := files.GitSnapshot(root)
	return map[string]any{
		"branch":      branch,
		"remote":      remote,
		"ahead":       ahead,
		"behind":      behind,
		"branches":    branches,
		"last_commit": lastCommit,
		"changed":     snap.Files,
	}
}

func runGit(root string, args ...string) string {
	cmdArgs := append([]string{"-C", root}, args...)
	out, err := exec.Command("git", cmdArgs...).Output()
	if err != nil {
		return ""
	}
	return string(out)
}

func parseGitStatusHeader(header string) (branch, remote string, ahead, behind int) {
	main := header
	if index := strings.Index(main, " ["); index >= 0 {
		meta := strings.TrimSuffix(main[index+2:], "]")
		main = main[:index]
		for _, part := range strings.Split(meta, ",") {
			part = strings.TrimSpace(part)
			switch {
			case strings.HasPrefix(part, "ahead "):
				ahead, _ = strconv.Atoi(strings.TrimSpace(strings.TrimPrefix(part, "ahead ")))
			case strings.HasPrefix(part, "behind "):
				behind, _ = strconv.Atoi(strings.TrimSpace(strings.TrimPrefix(part, "behind ")))
			}
		}
	}
	if before, after, ok := strings.Cut(main, "..."); ok {
		return before, after, ahead, behind
	}
	return main, "", ahead, behind
}

func listeningPorts(preview *previewProxy) []portEntry {
	if runtime.GOOS == "windows" {
		return listeningPortsWindows(preview)
	}
	return listeningPortsUnix(preview)
}

func listeningPortsWindows(preview *previewProxy) []portEntry {
	out, err := exec.Command("netstat", "-ano", "-p", "tcp").Output()
	if err != nil {
		return nil
	}
	names := map[string]string{}
	lanIP := localLANIP()
	var ports []portEntry
	for _, raw := range strings.Split(string(out), "\n") {
		fields := strings.Fields(raw)
		if len(fields) < 5 || !strings.EqualFold(fields[0], "TCP") || !strings.EqualFold(fields[3], "LISTENING") {
			continue
		}
		address, port, ok := splitListenAddress(fields[1])
		if !ok || port == 0 {
			continue
		}
		pid := fields[4]
		if _, ok := names[pid]; !ok {
			names[pid] = windowsProcessName(pid)
		}
		direct := directPreviewURL(address, port, lanIP)
		url := direct
		if preview != nil {
			url = preview.urlFor(port)
		}
		ports = append(ports, portEntry{
			Port:     port,
			Protocol: "tcp",
			Address:  address,
			PID:      pid,
			Process:  names[pid],
			URL:      url,
			Direct:   direct,
		})
	}
	return dedupePorts(ports)
}

func listeningPortsUnix(preview *previewProxy) []portEntry {
	out, err := exec.Command("sh", "-lc", "lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null || netstat -ltnp 2>/dev/null || true").Output()
	if err != nil {
		return nil
	}
	lanIP := localLANIP()
	var ports []portEntry
	for _, raw := range strings.Split(string(out), "\n") {
		fields := strings.Fields(raw)
		if len(fields) < 4 {
			continue
		}
		target := fields[len(fields)-2]
		if strings.Contains(strings.ToUpper(raw), "LISTEN") {
			target = fields[len(fields)-2]
		}
		address, port, ok := splitListenAddress(target)
		if !ok || port == 0 {
			continue
		}
		process := ""
		pid := ""
		if len(fields) > 1 {
			process = fields[0]
			pid = fields[1]
		}
		direct := directPreviewURL(address, port, lanIP)
		url := direct
		if preview != nil {
			url = preview.urlFor(port)
		}
		ports = append(ports, portEntry{
			Port:     port,
			Protocol: "tcp",
			Address:  address,
			PID:      pid,
			Process:  process,
			URL:      url,
			Direct:   direct,
		})
	}
	return dedupePorts(ports)
}

func splitListenAddress(value string) (string, int, bool) {
	value = strings.TrimSpace(value)
	value = strings.Trim(value, "[]")
	if value == "" {
		return "", 0, false
	}
	index := strings.LastIndex(value, ":")
	if index < 0 || index == len(value)-1 {
		return "", 0, false
	}
	host := strings.Trim(value[:index], "[]")
	port, err := strconv.Atoi(value[index+1:])
	if err != nil {
		return "", 0, false
	}
	if host == "" || host == "*" {
		host = "0.0.0.0"
	}
	return host, port, true
}

func windowsProcessName(pid string) string {
	out, err := exec.Command("tasklist", "/FI", "PID eq "+pid, "/FO", "CSV", "/NH").Output()
	if err != nil {
		return ""
	}
	reader := csv.NewReader(bytes.NewReader(out))
	rows, err := reader.ReadAll()
	if err != nil || len(rows) == 0 || len(rows[0]) == 0 {
		return ""
	}
	name := strings.TrimSpace(rows[0][0])
	if strings.EqualFold(name, "INFO: No tasks are running which match the specified criteria.") {
		return ""
	}
	return name
}

func dedupePorts(in []portEntry) []portEntry {
	seen := map[string]bool{}
	out := make([]portEntry, 0, len(in))
	for _, port := range in {
		if port.Port < 1024 && port.Port != 80 && port.Port != 443 {
			continue
		}
		key := fmt.Sprintf("%s:%d:%s", port.Address, port.Port, port.PID)
		if seen[key] {
			continue
		}
		seen[key] = true
		out = append(out, port)
	}
	sort.SliceStable(out, func(i, j int) bool {
		if out[i].Port == out[j].Port {
			return out[i].Address < out[j].Address
		}
		return out[i].Port < out[j].Port
	})
	if len(out) > 40 {
		return out[:40]
	}
	return out
}

func directPreviewURL(address string, port int, lanIP string) string {
	host := strings.Trim(address, "[]")
	switch host {
	case "", "0.0.0.0", "::", "[::]", "*":
		host = lanIP
	}
	if host == "" {
		host = "127.0.0.1"
	}
	return fmt.Sprintf("http://%s:%d", host, port)
}

func bestPreviewURL(ports []portEntry) string {
	preferred := map[int]bool{3000: true, 4173: true, 5173: true, 5174: true, 8000: true, 8080: true}
	for _, port := range ports {
		if preferred[port.Port] && port.URL != "" {
			return port.URL
		}
	}
	for _, port := range ports {
		if port.URL != "" {
			return port.URL
		}
	}
	return ""
}

func runGitAction(root, action, message, branch string) map[string]any {
	action = strings.TrimSpace(strings.ToLower(action))
	switch action {
	case "stage_all":
		out, err := runGitCommand(root, "add", "-A")
		return gitActionResult(action, err, "Staged all changes.", out)
	case "unstage_all":
		out, err := runGitCommand(root, "reset", "HEAD", "--", ".")
		return gitActionResult(action, err, "Unstaged all files.", out)
	case "commit":
		msg := strings.TrimSpace(message)
		if msg == "" {
			return map[string]any{
				"ok":      false,
				"action":  action,
				"summary": "Commit message is required.",
			}
		}
		out, err := runGitCommand(root, "commit", "-m", msg)
		return gitActionResult(action, err, "Commit created.", out)
	case "push":
		out, err := runGitCommand(root, "push")
		return gitActionResult(action, err, "Push complete.", out)
	case "pull":
		out, err := runGitCommand(root, "pull", "--ff-only")
		return gitActionResult(action, err, "Pull complete.", out)
	case "checkout":
		next := strings.TrimSpace(branch)
		if next == "" {
			return map[string]any{
				"ok":      false,
				"action":  action,
				"summary": "Branch name is required for checkout.",
			}
		}
		out, err := runGitCommand(root, "checkout", next)
		return gitActionResult(action, err, "Switched branch.", out)
	default:
		return map[string]any{
			"ok":      false,
			"action":  action,
			"summary": "Unsupported git action.",
		}
	}
}

func runGitCommand(root string, args ...string) (string, error) {
	cmdArgs := append([]string{"-C", root}, args...)
	out, err := exec.Command("git", cmdArgs...).CombinedOutput()
	text := strings.TrimSpace(string(out))
	if err != nil {
		if text == "" {
			return "", err
		}
		return text, fmt.Errorf("%w: %s", err, text)
	}
	return text, nil
}

func gitActionResult(action string, err error, successSummary, output string) map[string]any {
	if err != nil {
		summary := strings.TrimSpace(err.Error())
		if summary == "" {
			summary = "Git command failed."
		}
		return map[string]any{
			"ok":      false,
			"action":  action,
			"summary": summary,
			"output":  output,
		}
	}
	return map[string]any{
		"ok":      true,
		"action":  action,
		"summary": successSummary,
		"output":  output,
	}
}

func localLANIP() string {
	ifaces, err := net.Interfaces()
	if err != nil {
		return ""
	}
	for _, iface := range ifaces {
		if iface.Flags&net.FlagUp == 0 || iface.Flags&net.FlagLoopback != 0 {
			continue
		}
		addrs, err := iface.Addrs()
		if err != nil {
			continue
		}
		for _, addr := range addrs {
			var ip net.IP
			switch value := addr.(type) {
			case *net.IPNet:
				ip = value.IP
			case *net.IPAddr:
				ip = value.IP
			}
			ip = ip.To4()
			if ip == nil || ip.IsLoopback() {
				continue
			}
			return ip.String()
		}
	}
	return ""
}

func (s *secureSender) SetPeer(encoded, deviceID string) error {
	peer, err := e2ee.ParsePublicKey(encoded)
	if err != nil {
		return err
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if !s.hasPeer || s.peerKey != encoded {
		s.lastRecv = 0
	}
	s.peer = peer
	s.peerKey = encoded
	s.peerDevID = deviceID
	s.hasPeer = true
	for _, ev := range s.buffer {
		s.sendLocked(ev.typ, ev.data)
	}
	s.buffer = nil
	return nil
}

func (s *secureSender) PeerIdentity() (string, string, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.peerDevID, s.peerKey, s.hasPeer
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
	plain, err := e2ee.Open(s.kp, s.peer, env)
	if err != nil {
		return e2ee.PlainMessage{}, err
	}
	if env.Seq <= s.lastRecv {
		return e2ee.PlainMessage{}, errors.New("replayed or out-of-order mobile message")
	}
	s.lastRecv = env.Seq
	return plain, nil
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

func plural(word string, count int) string {
	if count == 1 {
		return word
	}
	return word + "s"
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
