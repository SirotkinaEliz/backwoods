// wintun_embed_windows.go — embeds wintun.dll into the EXE at CI build time.
// On first launch the DLL is extracted next to the executable automatically,
// so users only need to distribute / run the single EXE file.
//
//go:build windows

package main

import (
	_ "embed"
	"os"
	"path/filepath"
)

// wintun.dll is downloaded by the CI workflow (from wintun.net) and placed
// in this package directory before `go build` runs.
//
//go:embed wintun.dll
var wintunDLL []byte

// extractWintun writes the embedded wintun.dll next to the running executable.
// It is called from main() before the WireGuard tunnel is started.
func extractWintun() {
	exePath, err := os.Executable()
	if err != nil {
		return
	}
	dllPath := filepath.Join(filepath.Dir(exePath), "wintun.dll")
	// Skip if already present (re-runs after first launch)
	if _, err := os.Stat(dllPath); err == nil {
		return
	}
	_ = os.WriteFile(dllPath, wintunDLL, 0o644)
}
