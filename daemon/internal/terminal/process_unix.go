//go:build !windows

package terminal

import (
	"context"
	"errors"
	"io"
	"os"
	"os/exec"
	"sync"

	"github.com/creack/pty"
	"golang.org/x/term"
)

type Process struct {
	cmd     *exec.Cmd
	tty     *os.File
	done    chan error
	restore func() error
	once    sync.Once
}

func Start(ctx context.Context, cmd *exec.Cmd, onOutput func([]byte)) (*Process, error) {
	tty, err := pty.Start(cmd)
	if err != nil {
		return nil, err
	}

	restore := func() error { return nil }
	if term.IsTerminal(int(os.Stdin.Fd())) {
		oldState, err := term.MakeRaw(int(os.Stdin.Fd()))
		if err == nil {
			restore = func() error {
				return term.Restore(int(os.Stdin.Fd()), oldState)
			}
		}
	}

	p := &Process{
		cmd:     cmd,
		tty:     tty,
		done:    make(chan error, 1),
		restore: restore,
	}

	go func() {
		_, _ = io.Copy(tty, os.Stdin)
	}()
	go func() {
		buf := make([]byte, 32*1024)
		for {
			n, err := tty.Read(buf)
			if n > 0 {
				chunk := make([]byte, n)
				copy(chunk, buf[:n])
				onOutput(chunk)
			}
			if err != nil {
				return
			}
		}
	}()
	go func() {
		p.done <- cmd.Wait()
	}()
	go func() {
		<-ctx.Done()
		_ = p.Interrupt()
	}()

	return p, nil
}

func (p *Process) Write(data []byte) error {
	if p == nil || p.tty == nil {
		return errors.New("process is not running")
	}
	_, err := p.tty.Write(data)
	return err
}

func (p *Process) Interrupt() error {
	if p == nil || p.cmd == nil || p.cmd.Process == nil {
		return errors.New("process is not running")
	}
	return p.cmd.Process.Signal(os.Interrupt)
}

func (p *Process) Wait() error {
	err := <-p.done
	p.once.Do(func() {
		_ = p.restore()
		_ = p.tty.Close()
	})
	return err
}
