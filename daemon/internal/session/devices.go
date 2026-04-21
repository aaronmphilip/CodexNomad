package session

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"time"
)

type AuthorizedDevice struct {
	ID        string    `json:"id"`
	Name      string    `json:"name"`
	PublicKey string    `json:"public_key"`
	FirstSeen time.Time `json:"first_seen"`
	LastSeen  time.Time `json:"last_seen"`
}

type deviceRegistry struct {
	path string
}

func newDeviceRegistry(configDir string) deviceRegistry {
	return deviceRegistry{path: filepath.Join(configDir, "authorized-devices.json")}
}

func ListAuthorizedDevices(configDir string) ([]AuthorizedDevice, error) {
	return newDeviceRegistry(configDir).load()
}

func RevokeAuthorizedDevice(configDir, id string) (bool, error) {
	return newDeviceRegistry(configDir).Revoke(id)
}

func (r deviceRegistry) IsAuthorized(id, publicKey string) bool {
	if id == "" || publicKey == "" {
		return false
	}
	devices, err := r.load()
	if err != nil {
		return false
	}
	for _, device := range devices {
		if device.ID == id && device.PublicKey == publicKey {
			return true
		}
	}
	return false
}

func (r deviceRegistry) Authorize(id, name, publicKey string) error {
	if id == "" || publicKey == "" {
		return nil
	}
	devices, err := r.load()
	if err != nil {
		return err
	}
	now := time.Now().UTC()
	for i := range devices {
		if devices[i].ID == id {
			devices[i].Name = firstNonEmpty(name, devices[i].Name)
			devices[i].PublicKey = publicKey
			devices[i].LastSeen = now
			return r.save(devices)
		}
	}
	devices = append(devices, AuthorizedDevice{
		ID:        id,
		Name:      firstNonEmpty(name, "Mobile device"),
		PublicKey: publicKey,
		FirstSeen: now,
		LastSeen:  now,
	})
	return r.save(devices)
}

func (r deviceRegistry) Touch(id string) error {
	if id == "" {
		return nil
	}
	devices, err := r.load()
	if err != nil {
		return err
	}
	now := time.Now().UTC()
	for i := range devices {
		if devices[i].ID == id {
			devices[i].LastSeen = now
			return r.save(devices)
		}
	}
	return nil
}

func (r deviceRegistry) Revoke(id string) (bool, error) {
	id = strings.TrimSpace(id)
	if id == "" {
		return false, nil
	}
	devices, err := r.load()
	if err != nil {
		return false, err
	}
	next := devices[:0]
	removed := false
	for _, device := range devices {
		if device.ID == id {
			removed = true
			continue
		}
		next = append(next, device)
	}
	if !removed {
		return false, nil
	}
	return true, r.save(next)
}

func (r deviceRegistry) load() ([]AuthorizedDevice, error) {
	raw, err := os.ReadFile(r.path)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, nil
		}
		return nil, err
	}
	var devices []AuthorizedDevice
	if err := json.Unmarshal(raw, &devices); err != nil {
		return nil, err
	}
	return devices, nil
}

func (r deviceRegistry) save(devices []AuthorizedDevice) error {
	raw, err := json.MarshalIndent(devices, "", "  ")
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(r.path), 0o700); err != nil {
		return err
	}
	return os.WriteFile(r.path, raw, 0o600)
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if value != "" {
			return value
		}
	}
	return ""
}
