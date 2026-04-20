package logx

import (
	"io"
	"log"
	"os"
	"path/filepath"
)

type Logger struct {
	*log.Logger
	file *os.File
	Path string
}

func New(path string, also io.Writer) (*Logger, error) {
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return nil, err
	}
	f, err := os.OpenFile(path, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o600)
	if err != nil {
		return nil, err
	}
	w := io.Writer(f)
	if also != nil {
		w = io.MultiWriter(f, also)
	}
	return &Logger{
		Logger: log.New(w, "", log.LstdFlags|log.Lmicroseconds),
		file:   f,
		Path:   path,
	}, nil
}

func (l *Logger) Close() error {
	if l == nil || l.file == nil {
		return nil
	}
	return l.file.Close()
}
