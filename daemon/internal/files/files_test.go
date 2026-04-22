package files

import (
	"os"
	"os/exec"
	"path/filepath"
	"testing"
)

func TestProjectSnapshotIncludesTrackedAndUntrackedFiles(t *testing.T) {
	if _, err := exec.LookPath("git"); err != nil {
		t.Skip("git is not available")
	}
	root := t.TempDir()
	runGit(t, root, "init")
	runGit(t, root, "config", "user.email", "test@example.com")
	runGit(t, root, "config", "user.name", "Codex Nomad Test")

	if err := os.WriteFile(filepath.Join(root, "tracked.txt"), []byte("tracked"), 0o600); err != nil {
		t.Fatal(err)
	}
	runGit(t, root, "add", "tracked.txt")
	runGit(t, root, "commit", "-m", "add tracked file")

	if err := os.WriteFile(filepath.Join(root, "untracked.txt"), []byte("untracked"), 0o600); err != nil {
		t.Fatal(err)
	}

	snap, err := ProjectSnapshot(root)
	if err != nil {
		t.Fatal(err)
	}

	statusByPath := make(map[string]string)
	for _, entry := range snap.Files {
		statusByPath[entry.Path] = entry.Status
	}
	if got := statusByPath["tracked.txt"]; got != "tracked" {
		t.Fatalf("tracked.txt status = %q, want tracked", got)
	}
	if got := statusByPath["untracked.txt"]; got != "??" {
		t.Fatalf("untracked.txt status = %q, want ??", got)
	}
}

func TestGitSnapshotIncludesOnlyChangedFiles(t *testing.T) {
	if _, err := exec.LookPath("git"); err != nil {
		t.Skip("git is not available")
	}
	root := t.TempDir()
	runGit(t, root, "init")
	runGit(t, root, "config", "user.email", "test@example.com")
	runGit(t, root, "config", "user.name", "Codex Nomad Test")

	if err := os.WriteFile(filepath.Join(root, "tracked.txt"), []byte("tracked"), 0o600); err != nil {
		t.Fatal(err)
	}
	runGit(t, root, "add", "tracked.txt")
	runGit(t, root, "commit", "-m", "add tracked file")

	if err := os.WriteFile(filepath.Join(root, "untracked.txt"), []byte("untracked"), 0o600); err != nil {
		t.Fatal(err)
	}

	snap, err := GitSnapshot(root)
	if err != nil {
		t.Fatal(err)
	}
	if len(snap.Files) != 1 {
		t.Fatalf("GitSnapshot returned %d files, want 1 changed file: %+v", len(snap.Files), snap.Files)
	}
	if snap.Files[0].Path != "untracked.txt" || snap.Files[0].Status != "??" {
		t.Fatalf("GitSnapshot changed file = %+v, want untracked.txt ??", snap.Files[0])
	}
}

func runGit(t *testing.T, root string, args ...string) {
	t.Helper()
	cmd := exec.Command("git", append([]string{"-C", root}, args...)...)
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("git %v failed: %v\n%s", args, err, out)
	}
}
