//go:build darwin
// +build darwin

package main

import (
	"fmt"
	"os/exec"
	"strings"

	"golang.zx2c4.com/wireguard/tun"
)

// assignAddress sets the tunnel interface IP address on macOS via ifconfig.
func assignAddress(td tun.Device, cfg *WGConfig) error {
	name, err := td.Name()
	if err != nil {
		return err
	}
	for _, addr := range cfg.Addresses {
		parts := strings.SplitN(addr, "/", 2)
		ip := parts[0]
		// For point-to-point, set dest = src
		cmd := exec.Command("ifconfig", name, ip, ip, "up")
		if out, err := cmd.CombinedOutput(); err != nil {
			return fmt.Errorf("ifconfig: %v (%s)", err, out)
		}
	}
	// Add routes for AllowedIPs
	for _, cidr := range cfg.AllowedIPs {
		exec.Command("route", "add", "-net", cidr, "-interface", name).Run()
	}
	return nil
}

// setDNS configures DNS on macOS via networksetup.
func setDNS(dns []string) {
	// Apply to Wi-Fi and Ethernet (best-effort)
	for _, iface := range []string{"Wi-Fi", "Ethernet", "USB 10/100 LAN"} {
		args := append([]string{"-setdnsservers", iface}, dns...)
		exec.Command("networksetup", args...).Run()
	}
}

// restoreDNS restores default DNS on macOS.
func restoreDNS() {
	for _, iface := range []string{"Wi-Fi", "Ethernet", "USB 10/100 LAN"} {
		exec.Command("networksetup", "-setdnsservers", iface, "empty").Run()
	}
}
