//go:build !windows
// +build !windows

package main

import "os"

// isAdmin checks if running as root (required for WireGuard on macOS/Linux).
func isAdmin() bool {
	return os.Getuid() == 0
}
