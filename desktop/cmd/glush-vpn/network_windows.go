//go:build windows
// +build windows

package main

import (
	"fmt"
	"os/exec"
	"strings"

	"golang.zx2c4.com/wireguard/tun"
)

// assignAddress sets the tunnel interface IP address on Windows via netsh.
func assignAddress(td tun.Device, cfg *WGConfig) error {
	name, err := td.Name()
	if err != nil {
		return err
	}
	for _, addr := range cfg.Addresses {
		// addr is like "10.0.0.2/32"
		parts := strings.SplitN(addr, "/", 2)
		ip := parts[0]
		mask := "255.255.255.255"
		if len(parts) == 2 {
			mask = cidrToMask(parts[1])
		}
		cmd := exec.Command("netsh", "interface", "ip", "set", "address",
			fmt.Sprintf("name=%s", name), "static", ip, mask)
		if out, err := cmd.CombinedOutput(); err != nil {
			return fmt.Errorf("netsh address: %v (%s)", err, out)
		}
	}
	return nil
}

// setDNS configures DNS on Windows via netsh.
func setDNS(dns []string) {
	// Best-effort
	exec.Command("netsh", "interface", "ip", "set", "dns",
		"name=GLUSH", "static", dns[0]).Run()
	for i, d := range dns[1:] {
		exec.Command("netsh", "interface", "ip", "add", "dns",
			"name=GLUSH", d, fmt.Sprintf("index=%d", i+2)).Run()
	}
}

// restoreDNS restores automatic DNS on Windows.
func restoreDNS() {
	exec.Command("netsh", "interface", "ip", "set", "dns",
		"name=GLUSH", "dhcp").Run()
}

// cidrToMask converts prefix length string to dotted mask.
func cidrToMask(prefix string) string {
	var bits int
	fmt.Sscanf(prefix, "%d", &bits)
	mask := strings.Repeat("1", bits) + strings.Repeat("0", 32-bits)
	octets := make([]int, 4)
	for i := range octets {
		for j := 0; j < 8; j++ {
			octets[i] = octets[i]*2 + int(mask[i*8+j]-'0')
		}
	}
	return fmt.Sprintf("%d.%d.%d.%d", octets[0], octets[1], octets[2], octets[3])
}
