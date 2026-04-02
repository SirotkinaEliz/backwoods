// GLUSH VPN — Desktop tray application for Windows and macOS
// Establishes a WireGuard tunnel and shows status in the system tray.
//
// Build:
//   Windows: GOOS=windows GOARCH=amd64 go build -ldflags="-H windowsgui" -o GLUSH-VPN.exe ./cmd/glush-vpn
//   macOS:   GOOS=darwin  GOARCH=amd64 go build -o GLUSH-VPN ./cmd/glush-vpn

package main

import (
	_ "embed"
	"fmt"
	"log"
	"net"
	"os"
	"runtime"
	"sync"

	"github.com/fyne-io/systray"
	"golang.zx2c4.com/wireguard/conn"
	"golang.zx2c4.com/wireguard/device"
	"golang.zx2c4.com/wireguard/tun"
)

// tunnel.conf is embedded at build time by the CI pipeline.
//
//go:embed tunnel.conf
var tunnelConfText string

// ─── Icon assets (16×16 ICO/PNG, embedded) ───────────────────────────────────
//
//go:embed assets/icon_connected.ico
var iconConnected []byte

//go:embed assets/icon_disconnected.ico
var iconDisconnected []byte

// ─── Global tunnel state ─────────────────────────────────────────────────────

var (
	mu          sync.Mutex
	wgDevice    *device.Device
	tunDev      tun.Device
	uapiSocket  net.Listener
	connected   bool
	mConnected  *systray.MenuItem
	mDisconnect *systray.MenuItem
	mConnect    *systray.MenuItem
)

func main() {
	if !isAdmin() {
		showElevationError()
		os.Exit(1)
	}

	logFile, err := os.OpenFile(logPath(), os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0644)
	if err == nil {
		log.SetOutput(logFile)
		defer logFile.Close()
	}

	systray.Run(onReady, onExit)
}

func onReady() {
	systray.SetIcon(iconDisconnected)
	systray.SetTitle("GLUSH VPN")
	systray.SetTooltip("GLUSH — WireGuard VPN (отключено)")

	mConnected = systray.AddMenuItem("○  Отключено", "Статус VPN")
	mConnected.Disable()

	systray.AddSeparator()

	mConnect = systray.AddMenuItem("⚡  Подключить", "Включить VPN")
	mDisconnect = systray.AddMenuItem("✖  Отключить", "Выключить VPN")
	mDisconnect.Hide()

	systray.AddSeparator()
	mVersion := systray.AddMenuItem(fmt.Sprintf("GLUSH v1.0 · %s", runtime.GOOS), "")
	mVersion.Disable()

	systray.AddSeparator()
	mQuit := systray.AddMenuItem("Выход", "Закрыть GLUSH VPN")

	// Auto-connect on launch
	go connectVPN()

	// Handle menu clicks
	go func() {
		for {
			select {
			case <-mConnect.ClickedCh:
				go connectVPN()
			case <-mDisconnect.ClickedCh:
				disconnectVPN()
			case <-mQuit.ClickedCh:
				disconnectVPN()
				systray.Quit()
			}
		}
	}()
}

func onExit() {
	disconnectVPN()
}

// ─── VPN connect / disconnect ─────────────────────────────────────────────────

func connectVPN() {
	mu.Lock()
	if connected {
		mu.Unlock()
		return
	}
	mu.Unlock()

	setStatus("◌  Подключение…", false)

	cfg, err := ParseWGConf(tunnelConfText)
	if err != nil {
		log.Printf("config parse error: %v", err)
		setStatus("✗  Ошибка конфига", false)
		return
	}

	// Create TUN device
	td, err := tun.CreateTUN("utun" /*macOS/linux*/, cfg.MTU)
	if err != nil {
		// On Windows the tun interface name must be specific
		td, err = tun.CreateTUN("GLUSH", cfg.MTU)
		if err != nil {
			log.Printf("tun create error: %v", err)
			setStatus("✗  Ошибка TUN", false)
			return
		}
	}

	// Assign interface address
	if err := assignAddress(td, cfg); err != nil {
		log.Printf("address assign error: %v", err)
		// non-fatal: continue
	}

	logger := device.NewLogger(device.LogLevelSilent, "GLUSH: ")
	dev := device.NewDevice(td, conn.NewDefaultBind(), logger)

	// Configure via UAPI
	uapiConf := cfg.ToWGUserspace()
	if err := dev.IpcSet(uapiConf); err != nil {
		log.Printf("UAPI set error: %v", err)
		dev.Close()
		td.Close()
		setStatus("✗  Ошибка настройки", false)
		return
	}

	if err := dev.Up(); err != nil {
		log.Printf("device up error: %v", err)
		dev.Close()
		td.Close()
		setStatus("✗  Ошибка запуска", false)
		return
	}

	// Set DNS if specified
	if len(cfg.DNS) > 0 {
		setDNS(cfg.DNS)
	}

	mu.Lock()
	wgDevice = dev
	tunDev = td
	connected = true
	mu.Unlock()

	endpoint := cfg.Endpoint
	setStatus(fmt.Sprintf("●  Подключено · %s", endpoint), true)
	log.Printf("WireGuard tunnel up, endpoint=%s", endpoint)
}

func disconnectVPN() {
	mu.Lock()
	defer mu.Unlock()

	if !connected {
		return
	}

	if wgDevice != nil {
		wgDevice.Close()
		wgDevice = nil
	}
	if tunDev != nil {
		tunDev.Close()
		tunDev = nil
	}
	if uapiSocket != nil {
		uapiSocket.Close()
		uapiSocket = nil
	}

	// Restore DNS
	restoreDNS()

	connected = false
	setStatusLocked("○  Отключено", false)
	log.Println("WireGuard tunnel down")
}

func setStatus(label string, isConnected bool) {
	mu.Lock()
	defer mu.Unlock()
	setStatusLocked(label, isConnected)
}

func setStatusLocked(label string, isConnected bool) {
	if mConnected != nil {
		mConnected.SetTitle(label)
	}
	if isConnected {
		systray.SetIcon(iconConnected)
		systray.SetTooltip("GLUSH — VPN активен")
		if mConnect != nil {
			mConnect.Hide()
		}
		if mDisconnect != nil {
			mDisconnect.Show()
		}
	} else {
		systray.SetIcon(iconDisconnected)
		systray.SetTooltip("GLUSH — WireGuard VPN (отключено)")
		if mConnect != nil {
			mConnect.Show()
		}
		if mDisconnect != nil {
			mDisconnect.Hide()
		}
	}
}

func showElevationError() {
	fmt.Fprintln(os.Stderr,
		"GLUSH VPN требует прав администратора.\n"+
			"Запустите приложение от имени администратора (Windows) или через sudo (macOS).")
}

func logPath() string {
	if runtime.GOOS == "windows" {
		return os.TempDir() + `\glush-vpn.log`
	}
	return "/tmp/glush-vpn.log"
}
