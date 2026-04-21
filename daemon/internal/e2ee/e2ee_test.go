package e2ee

import "testing"

func TestSealOpenRoundTrip(t *testing.T) {
	t.Parallel()
	daemonKeys, err := GenerateKeyPair()
	if err != nil {
		t.Fatalf("GenerateKeyPair daemon: %v", err)
	}
	mobileKeys, err := GenerateKeyPair()
	if err != nil {
		t.Fatalf("GenerateKeyPair mobile: %v", err)
	}

	env, err := Seal("session-1", "daemon", 1, daemonKeys, mobileKeys.Public, "terminal_output", map[string]any{
		"encoding": "base64",
		"data":     "aGVsbG8",
	})
	if err != nil {
		t.Fatalf("Seal: %v", err)
	}
	plain, err := Open(mobileKeys, daemonKeys.Public, env)
	if err != nil {
		t.Fatalf("Open: %v", err)
	}
	if plain.Type != "terminal_output" {
		t.Fatalf("plain.Type = %q, want terminal_output", plain.Type)
	}
	if plain.SessionID != "session-1" {
		t.Fatalf("plain.SessionID = %q, want session-1", plain.SessionID)
	}
	if plain.Seq != 1 {
		t.Fatalf("plain.Seq = %d, want 1", plain.Seq)
	}
}

func TestOpenRejectsEnvelopeSessionMismatch(t *testing.T) {
	t.Parallel()
	daemonKeys, err := GenerateKeyPair()
	if err != nil {
		t.Fatalf("GenerateKeyPair daemon: %v", err)
	}
	mobileKeys, err := GenerateKeyPair()
	if err != nil {
		t.Fatalf("GenerateKeyPair mobile: %v", err)
	}

	env, err := Seal("session-1", "daemon", 1, daemonKeys, mobileKeys.Public, "ping", map[string]any{})
	if err != nil {
		t.Fatalf("Seal: %v", err)
	}
	env.SessionID = "session-2"
	if _, err := Open(mobileKeys, daemonKeys.Public, env); err == nil {
		t.Fatal("Open accepted an envelope with mismatched session id")
	}
}

func TestOpenRejectsWrongPeer(t *testing.T) {
	t.Parallel()
	daemonKeys, err := GenerateKeyPair()
	if err != nil {
		t.Fatalf("GenerateKeyPair daemon: %v", err)
	}
	mobileKeys, err := GenerateKeyPair()
	if err != nil {
		t.Fatalf("GenerateKeyPair mobile: %v", err)
	}
	wrongKeys, err := GenerateKeyPair()
	if err != nil {
		t.Fatalf("GenerateKeyPair wrong peer: %v", err)
	}

	env, err := Seal("session-1", "daemon", 1, daemonKeys, mobileKeys.Public, "ping", map[string]any{})
	if err != nil {
		t.Fatalf("Seal: %v", err)
	}
	if _, err := Open(wrongKeys, daemonKeys.Public, env); err == nil {
		t.Fatal("Open accepted ciphertext for the wrong recipient")
	}
}
