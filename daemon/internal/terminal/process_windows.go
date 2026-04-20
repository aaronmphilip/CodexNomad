//go:build windows

package terminal

import (
	"context"
	"errors"
	"io"
	"os"
	"os/exec"
	"sync"
)

type Process struct {
	cmd   *exec.Cmd
	stdin io.WriteCloser
	done  chan error
	once  sync.Once
}

func Start(ctx context.Context, cmd *exec.Cmd, onOutput func([]byte)) (*Process, error) {
	stdin, err := cmd.StdinPipe()
	if err != nil {
		return nil, err
	}
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return nil, err
	}
	stderr, err := cmd.StderrPipe()
	if err != nil {
		return nil, err
	}
	if err := cmd.Start(); err != nil {
		return nil, err
	}
	p := &Process{cmd: cmd, stdin: stdin, done: make(chan error, 1)}

	copyOutput := func(r io.Reader) {
		buf := make([]byte, 32*1024)
		for {
			n, err := r.Read(buf)
			if n > 0 {
				chunk := make([]byte, n)
				copy(chunk, buf[:n])
				onOutput(chunk)
			}
			if err != nil {
				return
			}
		}
	}
	go copyOutput(stdout)
	go copyOutput(stderr)
	go func() {
		_, _ = io.Copy(stdin, os.Stdin)
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
	if p == nil || p.stdin == nil {
		return errors.New("process is not running")
	}
	_, err := p.stdin.Write(data)
	return err
}

func (p *Process) Interrupt() error {
	if p == nil || p.cmd == nil || p.cmd.Process == nil {
		return errors.New("process is not running")
	}
	return p.cmd.Process.Kill()
}

func (p *Process) Wait() error {
	err := <-p.done
	p.once.Do(func() {
		_ = p.stdin.Close()
	})
	return err
}
