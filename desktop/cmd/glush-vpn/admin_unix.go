//go:build !windows
// +build !windows

package main

import (
	"fmt"
	"os"
)

// isAdmin checks if running as root (required for WireGuard on macOS/Linux).
func isAdmin() bool {
	return os.Getuid() == 0
}

// ensureAdmin завершает процесс если нет прав root.
func ensureAdmin() {
	if !isAdmin() {
		fmt.Fprintln(os.Stderr, "GLUSH VPN требует прав root. Запустите через sudo.")
		os.Exit(1)
	}
}
