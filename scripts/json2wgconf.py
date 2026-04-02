#!/usr/bin/env python3
"""
json2wgconf.py - Convert TUNNEL_CONFIG_JSON secret to standard WireGuard .conf format.

Usage:
    python3 scripts/json2wgconf.py <input.json> <output.conf>

Supported input formats:
  1. Backwoods/iOS wrapper:
     { "type": "wireGuard", "wireGuard": { "interface": {...}, "peer": {...} } }

  2. WireGuardKit / wireguard-apple style:
     { "privateKey": "...", "addresses": [...], "dns": [...],
       "peers": [{ "publicKey": "...", "endpoint": "...", "allowedIPs": [...] }] }

  3. Nested interface/peer:
     { "interface": { "privateKey": "...", ... }, "peer": { "publicKey": "...", ... } }

  4. Already in .conf format (starts with "[Interface]") - passed through unchanged.

  The parser also accepts Python-style single-quoted dicts (uses ast.literal_eval as fallback).
  BOM and leading/trailing whitespace are stripped automatically.
"""
import json
import sys
import os
import ast


def _load_data(raw: str) -> dict:
    """Parse raw text as JSON or Python dict literal."""
    # Try standard JSON first
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        pass

    # Fallback: Python ast.literal_eval (handles single quotes, trailing commas, etc.)
    try:
        result = ast.literal_eval(raw)
        if isinstance(result, dict):
            return result
    except Exception:
        pass

    raise ValueError(
        "Could not parse input as JSON or Python dict. "
        f"First 80 chars: {repr(raw[:80])}"
    )


def parse_json_to_wgconf(data: dict) -> str:
    """Convert various JSON tunnel config formats to WireGuard .conf text."""

    lines_iface = ["[Interface]"]
    lines_peer  = ["[Peer]"]

    # ─── Format 0: Backwoods iOS wrapper ─────────────────────────────────────
    # { "type": "wireGuard", "wireGuard": { "interface": {...}, "peer": {...} } }
    if data.get("type") == "wireGuard" and "wireGuard" in data:
        data = data["wireGuard"]
        # fall through to Format 2 (nested interface/peer)

    # ─── Format 1: WireGuardKit / wireguard-apple style ──────────────────────
    # { "privateKey": "...", "addresses": [...], "peers": [...] }
    if "peers" in data or ("privateKey" in data and "addresses" in data):
        private_key = data.get("privateKey", data.get("private_key", ""))
        addresses   = data.get("addresses", [])
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
            lines_iface.append("DNS = " + ", ".join(str(d) for d in dns_list))
        if mtu:
            lines_iface.append(f"MTU = {mtu}")

        peers = data.get("peers", [])
        for peer in peers:
            _append_peer(lines_peer, peer)

    # ─── Format 2: nested interface/peer objects ──────────────────────────────
    # { "interface": {...}, "peer": {...} }
    elif "interface" in data or "peer" in data:
        iface = data.get("interface", {})
        peer  = data.get("peer", {})

        private_key = iface.get("privateKey", iface.get("private_key", ""))
        addresses   = iface.get("addresses", iface.get("address", []))
        if isinstance(addresses, str):
            addresses = [addresses]
        dns_list = iface.get("dns", iface.get("dnsServers", []))
        if isinstance(dns_list, str):
            dns_list = [dns_list]
        mtu = iface.get("mtu", 0)

        lines_iface.append(f"PrivateKey = {private_key}")
        if addresses:
            lines_iface.append("Address = " + ", ".join(str(a) for a in addresses))
        if dns_list:
            lines_iface.append("DNS = " + ", ".join(str(d) for d in dns_list))
        if mtu:
            lines_iface.append(f"MTU = {mtu}")

        _append_peer(lines_peer, peer)

    else:
        raise ValueError(f"Unknown JSON format. Top-level keys: {list(data.keys())}")

    return "\n".join(lines_iface) + "\n\n" + "\n".join(lines_peer) + "\n"


def _append_peer(lines_peer: list, peer: dict):
    public_key    = peer.get("publicKey",    peer.get("public_key",    ""))
    preshared_key = peer.get("presharedKey", peer.get("preshared_key", "")) or ""
    endpoint      = peer.get("endpoint", "")
    allowed_ips   = peer.get("allowedIPs",   peer.get("allowed_ips",   ["0.0.0.0/0", "::/0"]))
    keepalive     = peer.get("persistentKeepalive", peer.get("persistent_keepalive", 25)) or 0

    if isinstance(allowed_ips, str):
        allowed_ips = [x.strip() for x in allowed_ips.split(",")]

    lines_peer.append(f"PublicKey = {public_key}")
    if preshared_key:
        lines_peer.append(f"PresharedKey = {preshared_key}")
    if endpoint:
        lines_peer.append(f"Endpoint = {endpoint}")
    lines_peer.append("AllowedIPs = " + ", ".join(str(ip) for ip in allowed_ips))
    if keepalive:
        lines_peer.append(f"PersistentKeepalive = {keepalive}")


def main():
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} <input.json|input.conf> <output.conf>",
              file=sys.stderr)
        sys.exit(1)

    input_path  = sys.argv[1]
    output_path = sys.argv[2]

    with open(input_path, "r", encoding="utf-8-sig") as f:  # utf-8-sig strips BOM
        raw = f.read().strip()

    if not raw:
        print("[json2wgconf] ERROR: input file is empty (secret not set?)", file=sys.stderr)
        sys.exit(1)

    # If it already looks like a WireGuard .conf, pass through unchanged
    if raw.lstrip().startswith("[Interface]"):
        print("[json2wgconf] Input is already WireGuard .conf — copying as-is.")
        conf_text = raw
    else:
        data = _load_data(raw)
        conf_text = parse_json_to_wgconf(data)
        print("[json2wgconf] Converted JSON → WireGuard .conf")

    os.makedirs(os.path.dirname(os.path.abspath(output_path)), exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as f:
        f.write(conf_text)

    print(f"[json2wgconf] Written to: {output_path}")
    for line in conf_text.splitlines():
        key = line.split("=")[0].strip().lower()
        if key in ("privatekey", "presharedkey"):
            print(f"  {line.split('=')[0].strip()} = <hidden>")
        else:
            print(f"  {line}")


if __name__ == "__main__":
    main()
