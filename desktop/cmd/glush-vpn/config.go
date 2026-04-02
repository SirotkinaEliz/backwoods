package main

import (
	"bufio"
	"encoding/base64"
	"encoding/hex"
	"fmt"
	"net"
	"strings"
)

// WGConfig holds parsed WireGuard configuration
type WGConfig struct {
	// Interface section
	PrivateKey string
	Addresses  []string
	DNS        []string
	MTU        int

	// Peer section
	PublicKey           string
	PresharedKey        string
	Endpoint            string
	AllowedIPs          []string
	PersistentKeepalive int
}

// ParseWGConf parses a WireGuard .conf file text.
func ParseWGConf(text string) (*WGConfig, error) {
	cfg := &WGConfig{MTU: 1420}
	var section string

	scanner := bufio.NewScanner(strings.NewReader(text))
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}

		if strings.HasPrefix(line, "[") {
			section = strings.ToLower(strings.Trim(line, "[]"))
			continue
		}

		parts := strings.SplitN(line, "=", 2)
		if len(parts) != 2 {
			continue
		}
		key := strings.TrimSpace(parts[0])
		val := strings.TrimSpace(parts[1])

		switch section {
		case "interface":
			switch strings.ToLower(key) {
			case "privatekey":
				cfg.PrivateKey = val
			case "address":
				for _, addr := range strings.Split(val, ",") {
					cfg.Addresses = append(cfg.Addresses, strings.TrimSpace(addr))
				}
			case "dns":
				for _, d := range strings.Split(val, ",") {
					cfg.DNS = append(cfg.DNS, strings.TrimSpace(d))
				}
			case "mtu":
				fmt.Sscanf(val, "%d", &cfg.MTU)
			}
		case "peer":
			switch strings.ToLower(key) {
			case "publickey":
				cfg.PublicKey = val
			case "presharedkey":
				cfg.PresharedKey = val
			case "endpoint":
				cfg.Endpoint = val
			case "allowedips":
				for _, ip := range strings.Split(val, ",") {
					cfg.AllowedIPs = append(cfg.AllowedIPs, strings.TrimSpace(ip))
				}
			case "persistentkeepalive":
				fmt.Sscanf(val, "%d", &cfg.PersistentKeepalive)
			}
		}
	}

	if cfg.PrivateKey == "" {
		return nil, fmt.Errorf("missing PrivateKey in [Interface]")
	}
	if cfg.PublicKey == "" {
		return nil, fmt.Errorf("missing PublicKey in [Peer]")
	}
	if len(cfg.Addresses) == 0 {
		return nil, fmt.Errorf("missing Address in [Interface]")
	}
	return cfg, nil
}

// ToWGUserspace converts config to the UAPI format accepted by wireguard-go.
func (c *WGConfig) ToWGUserspace() string {
	var sb strings.Builder

	sb.WriteString(fmt.Sprintf("private_key=%s\n", keyToHex(c.PrivateKey)))
	sb.WriteString("replace_peers=true\n")
	sb.WriteString(fmt.Sprintf("public_key=%s\n", keyToHex(c.PublicKey)))

	if c.PresharedKey != "" {
		sb.WriteString(fmt.Sprintf("preshared_key=%s\n", keyToHex(c.PresharedKey)))
	}

	if c.Endpoint != "" {
		// Resolve endpoint to IP:port
		host, port, err := net.SplitHostPort(c.Endpoint)
		if err == nil {
			addrs, err2 := net.LookupHost(host)
			if err2 == nil && len(addrs) > 0 {
				sb.WriteString(fmt.Sprintf("endpoint=%s:%s\n", addrs[0], port))
			} else {
				sb.WriteString(fmt.Sprintf("endpoint=%s\n", c.Endpoint))
			}
		}
	}

	for _, ip := range c.AllowedIPs {
		ip = strings.TrimSpace(ip)
		if ip == "" {
			continue
		}
		sb.WriteString(fmt.Sprintf("allowed_ip=%s\n", ip))
	}

	if c.PersistentKeepalive > 0 {
		sb.WriteString(fmt.Sprintf("persistent_keepalive_interval=%d\n", c.PersistentKeepalive))
	}

	return sb.String()
}

// keyToHex converts a base64 WireGuard key to hex (required by UAPI protocol).
func keyToHex(b64key string) string {
	raw, err := base64.StdEncoding.DecodeString(b64key)
	if err != nil {
		return b64key
	}
	return hex.EncodeToString(raw)
}
