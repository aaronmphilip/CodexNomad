package qr

import (
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"strings"

	qrcode "github.com/skip2/go-qrcode"
)

type PairingPayload struct {
	Version   int    `json:"v"`
	SessionID string `json:"sid"`
	Agent     string `json:"agent"`
	Mode      string `json:"mode"`
	RelayURL  string `json:"relay_url"`
	PublicKey string `json:"public_key"`
	CreatedAt string `json:"created_at"`
	ExpiresAt string `json:"expires_at"`
}

func EncodePayload(payload PairingPayload) (string, error) {
	raw, err := json.Marshal(payload)
	if err != nil {
		return "", err
	}
	return "codexnomad://pair?data=" + base64.RawURLEncoding.EncodeToString(raw), nil
}

func RenderTerminal(w io.Writer, content string) error {
	code, err := qrcode.New(content, qrcode.Medium)
	if err != nil {
		return err
	}
	bitmap := code.Bitmap()
	fmt.Fprintln(w)
	for _, row := range bitmap {
		var b strings.Builder
		for _, dark := range row {
			if dark {
				b.WriteString("██")
			} else {
				b.WriteString("  ")
			}
		}
		fmt.Fprintln(w, b.String())
	}
	fmt.Fprintln(w)
	return nil
}

func WritePNG(content, path string, size int) error {
	if size <= 0 {
		size = 768
	}
	return qrcode.WriteFile(content, qrcode.Medium, size, path)
}
