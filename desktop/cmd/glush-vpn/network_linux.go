//go:build !windows && !darwin
// +build !windows,!darwin

package main

import (
	"fmt"
	"os/exec"

	"golang.zx2c4.com/wireguard/tun"
)

func assignAddress(td tun.Device, cfg *WGConfig) error {
	name, err := td.Name()
	if err != nil {
		return err
	}
	for _, addr := range cfg.Addresses {
		cmd := exec.Command("ip", "addr", "add", addr, "dev", name)
		if out, err := cmd.CombinedOutput(); err != nil {
			return fmt.Errorf("ip addr add: %v (%s)", err, out)
		}
	}
	exec.Command("ip", "link", "set", name, "up").Run()
	for _, cidr := range cfg.AllowedIPs {
		exec.Command("ip", "route", "add", cidr, "dev", name).Run()
	}
	return nil
}

func setDNS(dns []string) {}
func restoreDNS()         {}
