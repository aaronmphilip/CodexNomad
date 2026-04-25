package app

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/codexnomad/codexnomad/daemon/internal/cliwrap"
	"github.com/codexnomad/codexnomad/daemon/internal/config"
)

func TestRelayHealthURL(t *testing.T) {
	t.Parallel()
	cases := []struct {
		name string
		in   string
		want string
	}{
		{
			name: "local websocket relay",
			in:   "ws://127.0.0.1:8080/v1/relay?ticket=secret",
			want: "http://127.0.0.1:8080/healthz",
		},
		{
			name: "hosted secure relay",
			in:   "wss://relay.codexnomad.pro/v1/relay",
			want: "https://relay.codexnomad.pro/healthz",
		},
	}
	for _, tc := range cases {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			got, err := relayHealthURL(tc.in)
			if err != nil {
				t.Fatalf("relayHealthURL returned error: %v", err)
			}
			if got != tc.want {
				t.Fatalf("relayHealthURL(%q) = %q, want %q", tc.in, got, tc.want)
			}
		})
	}
}

func TestRelayHealthURLRejectsHTTP(t *testing.T) {
	t.Parallel()
	if _, err := relayHealthURL("http://127.0.0.1:8080/v1/relay"); err == nil {
		t.Fatal("relayHealthURL accepted a non-websocket URL")
	}
}

func TestMissingRequiredAgentCLIFailsDoctor(t *testing.T) {
	t.Parallel()
	check := checkOneAgentCLI(cliwrap.AgentCodex, "missing cli", "codexnomad-definitely-missing-binary", true)
	if check.Status != doctorFail {
		t.Fatalf("missing required CLI status = %s, want %s", check.Status, doctorFail)
	}
	if !check.Fatal {
		t.Fatal("missing required CLI should be fatal")
	}
}

func TestMissingOptionalAgentCLIWarnsDoctor(t *testing.T) {
	t.Parallel()
	check := checkOneAgentCLI(cliwrap.AgentCodex, "missing cli", "codexnomad-definitely-missing-binary", false)
	if check.Status != doctorWarn {
		t.Fatalf("missing optional CLI status = %s, want %s", check.Status, doctorWarn)
	}
	if check.Fatal {
		t.Fatal("missing optional CLI should not be fatal")
	}
}

func TestCheckRelayHealthWarnsWhenOptionalAndUnreachable(t *testing.T) {
	t.Parallel()
	cfg := config.Config{
		RelayURL:      "ws://127.0.0.1:1/v1/relay",
		RequireRelay:  false,
		RelayToken:    "",
		CloudServerID: "",
	}
	check := checkRelayHealth(cfg)
	if check.Status != doctorWarn {
		t.Fatalf("relay status = %s, want %s", check.Status, doctorWarn)
	}
	if check.Fatal {
		t.Fatal("optional relay check should not be fatal")
	}
	if !strings.Contains(strings.ToLower(check.Detail), "optional") {
		t.Fatalf("relay detail missing optional hint: %q", check.Detail)
	}
}

func TestCheckRelayHealthFailsWhenRequiredAndUnreachable(t *testing.T) {
	t.Parallel()
	cfg := config.Config{
		RelayURL:      "ws://127.0.0.1:1/v1/relay",
		RequireRelay:  true,
		RelayToken:    "",
		CloudServerID: "",
	}
	check := checkRelayHealth(cfg)
	if check.Status != doctorFail {
		t.Fatalf("relay status = %s, want %s", check.Status, doctorFail)
	}
	if !check.Fatal {
		t.Fatal("required relay check should be fatal")
	}
}

func TestCheckRelayHealthOKWhenReachable(t *testing.T) {
	t.Parallel()
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/healthz" {
			t.Fatalf("unexpected health path: %s", r.URL.Path)
		}
		w.WriteHeader(http.StatusOK)
	}))
	defer server.Close()

	relayURL := strings.Replace(server.URL, "http://", "ws://", 1) + "/v1/relay"
	check := checkRelayHealth(config.Config{RelayURL: relayURL})
	if check.Status != doctorOK {
		t.Fatalf("relay status = %s, want %s (detail=%q)", check.Status, doctorOK, check.Detail)
	}
	if check.Fatal {
		t.Fatal("successful relay check should not be fatal")
	}
}
