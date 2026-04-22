package app

import (
	"testing"

	"github.com/codexnomad/codexnomad/daemon/internal/cliwrap"
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
