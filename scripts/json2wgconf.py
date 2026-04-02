#!/usr/bin/env python3
"""
json2wgconf.py - Convert TUNNEL_CONFIG_JSON secret to standard WireGuard .conf format.

Usage:
    python3 scripts/json2wgconf.py <input.json> <output.conf>

The input JSON may be in one of several formats:
  1. WireGuardKit format (iOS/Swift):
     { "privateKey": "...", "addresses": [...], "dns": [...],
       "peers": [{ "publicKey": "...", "endpoint": "...", "allowedIPs": [...] }] }

  2. Simple flat format:
     { "interface": { "privateKey": "...", "address": "...", "dns": "..." },
       "peer": { "publicKey": "...", "endpoint": "...", "allowedIPs": "...", "presharedKey": "..." } }

  3. Already in .conf format (starts with "[Interface]") - passed through unchanged.
"""
import json
import sys
import os


def parse_json_to_wgconf(data: dict) -> str:
    """Convert various JSON tunnel config formats to WireGuard .conf text."""

    lines_iface = ["[Interface]"]
    lines_peer = ["[Peer]"]

    # ─── Format 1: WireGuardKit / wireguard-apple style ──────────────────────
    if "peers" in data or ("privateKey" in data and "addresses" in data):
        private_key = data.get("privateKey", data.get("private_key", ""))
        addresses = data.get("addresses", [])
        if isinstance(addresses, str):
            addresses = [addresses]
        dns_list = data.get("dns", data.get("dnsServers", []))
        if isinstance(dns_list, str):
            dns_list = [dns_list]
        mtu = data.get("mtu", 0)

        lines_iface.append(f"PrivateKey = {private_key}")
        if addresses:
            lines_iface.append("Address = " + ", ".join(addresses))
        if dns_list:
            lines_iface.append("DNS = " + ", ".join(dns_list))
        if mtu:
            lines_iface.append(f"MTU = {mtu}")

        peers = data.get("peers", [])
        for peer in peers:
            public_key = peer.get("publicKey", peer.get("public_key", ""))
            preshared_key = peer.get("presharedKey", peer.get("preshared_key", ""))
            endpoint = peer.get("endpoint", "")
            allowed_ips = peer.get("allowedIPs", peer.get("allowed_ips", ["0.0.0.0/0", "::/0"]))
            if isinstance(allowed_ips, str):
                allowed_ips = [x.strip() for x in allowed_ips.split(",")]
            keepalive = peer.get("persistentKeepalive", peer.get("persistent_keepalive", 25))

            lines_peer.append(f"PublicKey = {public_key}")
            if preshared_key:
                lines_peer.append(f"PresharedKey = {preshared_key}")
            if endpoint:
                lines_peer.append(f"Endpoint = {endpoint}")
            lines_peer.append("AllowedIPs = " + ", ".join(allowed_ips))
            if keepalive:
                lines_peer.append(f"PersistentKeepalive = {keepalive}")
        break_after = True

    # ─── Format 2: nested interface/peer objects ──────────────────────────────
    elif "interface" in data or "peer" in data:
        iface = data.get("interface", {})
        peer = data.get("peer", {})

        private_key = iface.get("privateKey", iface.get("private_key", ""))
        address = iface.get("address", iface.get("addresses", ""))
        if isinstance(address, list):
            address = ", ".join(address)
        dns = iface.get("dns", iface.get("dnsServers", ""))
        if isinstance(dns, list):
            dns = ", ".join(dns)
        mtu = iface.get("mtu", 0)

        lines_iface.append(f"PrivateKey = {private_key}")
        if address:
            lines_iface.append(f"Address = {address}")
        if dns:
            lines_iface.append(f"DNS = {dns}")
        if mtu:
            lines_iface.append(f"MTU = {mtu}")

        public_key = peer.get("publicKey", peer.get("public_key", ""))
        preshared_key = peer.get("presharedKey", peer.get("preshared_key", ""))
        endpoint = peer.get("endpoint", "")
        allowed_ips = peer.get("allowedIPs", peer.get("allowed_ips", "0.0.0.0/0, ::/0"))
        if isinstance(allowed_ips, list):
            allowed_ips = ", ".join(allowed_ips)
        keepalive = peer.get("persistentKeepalive", peer.get("persistent_keepalive", 25))

        lines_peer.append(f"PublicKey = {public_key}")
        if preshared_key:
            lines_peer.append(f"PresharedKey = {preshared_key}")
        if endpoint:
            lines_peer.append(f"Endpoint = {endpoint}")
        lines_peer.append(f"AllowedIPs = {allowed_ips}")
        if keepalive:
            lines_peer.append(f"PersistentKeepalive = {keepalive}")
        break_after = True

    else:
        raise ValueError(f"Unknown JSON format. Keys: {list(data.keys())}")

    _ = break_after  # used as flow marker above
    return "\n".join(lines_iface) + "\n\n" + "\n".join(lines_peer) + "\n"


def main():
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} <input.json> <output.conf>", file=sys.stderr)
        sys.exit(1)

    input_path = sys.argv[1]
    output_path = sys.argv[2]

    with open(input_path, "r", encoding="utf-8") as f:
        raw = f.read().strip()

    # If it already looks like a .conf file, pass through
    if raw.startswith("[Interface]"):
        print(f"[json2wgconf] Input is already WireGuard .conf format — copying as-is.")
        conf_text = raw
    else:
        data = json.loads(raw)
        conf_text = parse_json_to_wgconf(data)
        print(f"[json2wgconf] Converted JSON → WireGuard .conf")

    os.makedirs(os.path.dirname(os.path.abspath(output_path)), exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as f:
        f.write(conf_text)

    print(f"[json2wgconf] Written to: {output_path}")

    # Print summary (no private key!)
    for line in conf_text.splitlines():
        if "PrivateKey" in line or "PresharedKey" in line:
            key_name = line.split("=")[0].strip()
            print(f"  {key_name} = <hidden>")
        else:
            print(f"  {line}")


if __name__ == "__main__":
    main()
