//go:build windows

package terminal

import (
	"context"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"sort"
	"strings"
	"sync"
	"unicode/utf16"
	"unsafe"

	"golang.org/x/sys/windows"
)

type Process struct {
	process windows.Handle
	thread  windows.Handle
	console windows.Handle
	stdin   windows.Handle
	stdout  windows.Handle
	done    chan error
	once    sync.Once
}

func Start(ctx context.Context, cmd *exec.Cmd, onOutput func([]byte)) (*Process, error) {
	inRead, inWrite, err := createPipe()
	if err != nil {
		return nil, err
	}
	outRead, outWrite, err := createPipe()
	if err != nil {
		closeHandle(inRead)
		closeHandle(inWrite)
		return nil, err
	}

	var console windows.Handle
	size := windows.Coord{X: 120, Y: 40}
	if err := windows.CreatePseudoConsole(size, inRead, outWrite, 0, &console); err != nil {
		closeHandle(inRead)
		closeHandle(inWrite)
		closeHandle(outRead)
		closeHandle(outWrite)
		return nil, fmt.Errorf("create Windows pseudo-terminal: %w", err)
	}

	attr, err := windows.NewProcThreadAttributeList(1)
	if err != nil {
		closeHandle(inRead)
		closeHandle(inWrite)
		closeHandle(outRead)
		closeHandle(outWrite)
		windows.ClosePseudoConsole(console)
		return nil, err
	}
	defer attr.Delete()
	if err := attr.Update(
		windows.PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE,
		unsafe.Pointer(console),
		unsafe.Sizeof(console),
	); err != nil {
		closeHandle(inRead)
		closeHandle(inWrite)
		closeHandle(outRead)
		closeHandle(outWrite)
		windows.ClosePseudoConsole(console)
		return nil, err
	}

	cmdLine, err := windows.UTF16PtrFromString(windows.ComposeCommandLine(cmd.Args))
	if err != nil {
		closeHandle(inRead)
		closeHandle(inWrite)
		closeHandle(outRead)
		closeHandle(outWrite)
		windows.ClosePseudoConsole(console)
		return nil, err
	}
	var cwd *uint16
	if strings.TrimSpace(cmd.Dir) != "" {
		cwd, err = windows.UTF16PtrFromString(cmd.Dir)
		if err != nil {
			closeHandle(inRead)
			closeHandle(inWrite)
			closeHandle(outRead)
			closeHandle(outWrite)
			windows.ClosePseudoConsole(console)
			return nil, err
		}
	}
	envBlock, err := createEnvironmentBlock(cmd.Env)
	if err != nil {
		closeHandle(inRead)
		closeHandle(inWrite)
		closeHandle(outRead)
		closeHandle(outWrite)
		windows.ClosePseudoConsole(console)
		return nil, err
	}
	var env *uint16
	if len(envBlock) > 0 {
		env = &envBlock[0]
	}

	si := &windows.StartupInfoEx{
		StartupInfo: windows.StartupInfo{
			Cb:    uint32(unsafe.Sizeof(windows.StartupInfoEx{})),
			Flags: windows.STARTF_USESTDHANDLES,
		},
		ProcThreadAttributeList: attr.List(),
	}
	pi := new(windows.ProcessInformation)
	flags := uint32(windows.EXTENDED_STARTUPINFO_PRESENT | windows.CREATE_UNICODE_ENVIRONMENT | windows.CREATE_DEFAULT_ERROR_MODE)
	if err := windows.CreateProcess(nil, cmdLine, nil, nil, false, flags, env, cwd, &si.StartupInfo, pi); err != nil {
		closeHandle(inRead)
		closeHandle(inWrite)
		closeHandle(outRead)
		closeHandle(outWrite)
		windows.ClosePseudoConsole(console)
		return nil, err
	}
	closeHandle(inRead)
	closeHandle(outWrite)

	p := &Process{
		process: pi.Process,
		thread:  pi.Thread,
		console: console,
		stdin:   inWrite,
		stdout:  outRead,
		done:    make(chan error, 1),
	}

	go func() {
		_, _ = p.copyInput(os.Stdin)
	}()
	go func() {
		buf := make([]byte, 32*1024)
		for {
			n, err := readHandle(p.stdout, buf)
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
		p.done <- waitProcess(pi.Process)
	}()
	go func() {
		<-ctx.Done()
		_ = p.Interrupt()
	}()

	return p, nil
}

func (p *Process) Write(data []byte) error {
	if p == nil || p.stdin == 0 {
		return errors.New("process is not running")
	}
	return writeAll(p.stdin, normalizeInput(data))
}

func (p *Process) Interrupt() error {
	if p == nil || p.process == 0 {
		return errors.New("process is not running")
	}
	return windows.TerminateProcess(p.process, 1)
}

func (p *Process) Wait() error {
	err := <-p.done
	p.once.Do(func() {
		closeHandle(p.stdin)
		closeHandle(p.stdout)
		if p.console != 0 {
			windows.ClosePseudoConsole(p.console)
		}
		closeHandle(p.thread)
		closeHandle(p.process)
	})
	return err
}

func (p *Process) copyInput(input *os.File) (int64, error) {
	buf := make([]byte, 32*1024)
	var total int64
	for {
		n, err := input.Read(buf)
		if n > 0 {
			if writeErr := writeAll(p.stdin, buf[:n]); writeErr != nil {
				return total, writeErr
			}
			total += int64(n)
		}
		if err != nil {
			return total, err
		}
	}
}

func createPipe() (windows.Handle, windows.Handle, error) {
	var read, write windows.Handle
	if err := windows.CreatePipe(&read, &write, nil, 0); err != nil {
		return 0, 0, err
	}
	return read, write, nil
}

func closeHandle(handle windows.Handle) {
	if handle != 0 {
		_ = windows.CloseHandle(handle)
	}
}

func waitProcess(process windows.Handle) error {
	status, err := windows.WaitForSingleObject(process, windows.INFINITE)
	if err != nil {
		return err
	}
	if status != windows.WAIT_OBJECT_0 {
		return fmt.Errorf("wait failed: status %d", status)
	}
	var code uint32
	if err := windows.GetExitCodeProcess(process, &code); err != nil {
		return err
	}
	if code != 0 {
		return fmt.Errorf("exit status %d", code)
	}
	return nil
}

func readHandle(handle windows.Handle, buf []byte) (int, error) {
	var read uint32
	err := windows.ReadFile(handle, buf, &read, nil)
	if err != nil {
		return int(read), err
	}
	return int(read), nil
}

func writeAll(handle windows.Handle, data []byte) error {
	for len(data) > 0 {
		var written uint32
		if err := windows.WriteFile(handle, data, &written, nil); err != nil {
			return err
		}
		if written == 0 {
			return errors.New("wrote zero bytes to pseudo-terminal")
		}
		data = data[written:]
	}
	return nil
}

func createEnvironmentBlock(env []string) ([]uint16, error) {
	if len(env) == 0 {
		env = os.Environ()
	}
	next := make([]string, 0, len(env))
	for _, item := range env {
		if item == "" || strings.HasPrefix(item, "=") || !strings.Contains(item, "=") {
			continue
		}
		next = append(next, item)
	}
	sort.SliceStable(next, func(i, j int) bool {
		return strings.ToUpper(next[i]) < strings.ToUpper(next[j])
	})
	block := make([]uint16, 0)
	for _, item := range next {
		block = append(block, utf16.Encode([]rune(item))...)
		block = append(block, 0)
	}
	block = append(block, 0)
	return block, nil
}

func normalizeInput(data []byte) []byte {
	if len(data) == 0 {
		return data
	}
	out := make([]byte, 0, len(data))
	for _, b := range data {
		if b == '\n' {
			out = append(out, '\r')
			continue
		}
		out = append(out, b)
	}
	return out
}
