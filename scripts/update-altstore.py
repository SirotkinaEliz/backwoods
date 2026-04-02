#!/usr/bin/env python3
"""
Update docs/apps.json with the latest GLUSH release.

Positional (legacy iOS) usage:
  update-altstore.py <download_url> <version> <ipa_size> <build_date> [apps_json_path]

Flag-based (multi-platform) usage:
  update-altstore.py [--ios-url URL --ios-size N --ios-version VER --ios-date DATE]
                     [--android-url URL --android-size N]
                     [--windows-url URL --windows-size N]
                     [--macos-url URL --macos-size N]
                     <apps_json_path>
"""
import json
import sys
import os
import argparse
from datetime import datetime, timezone


def now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def main():
    # ── Detect legacy positional mode ─────────────────────────────────────────
    if len(sys.argv) >= 5 and not sys.argv[1].startswith("--"):
        # Legacy: update-altstore.py <url> <version> <size> <date> [path]
        download_url = sys.argv[1]
        version      = sys.argv[2]
        ipa_size     = int(sys.argv[3]) if sys.argv[3].isdigit() else 0
        build_date   = sys.argv[4]
        apps_json    = sys.argv[5] if len(sys.argv) > 5 else "docs/apps.json"
        _update_ios(apps_json, download_url, version, ipa_size, build_date)
        return

    # ── Flag-based mode ────────────────────────────────────────────────────────
    parser = argparse.ArgumentParser()
    # iOS (IPA)
    parser.add_argument("--ios-url")
    parser.add_argument("--ios-size", type=int)
    parser.add_argument("--ios-version")
    parser.add_argument("--ios-date")
    # Android
    parser.add_argument("--android-url")
    parser.add_argument("--android-size", type=int)
    # Windows
    parser.add_argument("--windows-url")
    parser.add_argument("--windows-size", type=int)
    # macOS
    parser.add_argument("--macos-url")
    parser.add_argument("--macos-size", type=int)
    # positional: path to apps.json
    parser.add_argument("apps_json", nargs="?", default="docs/apps.json")

    args = parser.parse_args()

    if not os.path.exists(args.apps_json):
        print(f"ERROR: {args.apps_json} not found", file=sys.stderr)
        sys.exit(1)

    with open(args.apps_json, encoding="utf-8") as f:
        data = json.load(f)

    app = data["apps"][0]

    if args.ios_url:
        _update_ios_in_place(app, args.ios_url,
                             args.ios_size or 0,
                             args.ios_version or "1.0",
                             args.ios_date or now_iso())

    if args.android_url:
        app.setdefault("platforms", {})
        app["platforms"]["android"] = {
            "downloadURL": args.android_url,
            "size": args.android_size or 0,
            "minOSVersion": "5.0",
            "date": now_iso(),
        }
        print(f"✅ Android → {args.android_url}")

    if args.windows_url:
        app.setdefault("platforms", {})
        app["platforms"]["windows"] = {
            "downloadURL": args.windows_url,
            "size": args.windows_size or 0,
            "minOSVersion": "10",
            "date": now_iso(),
        }
        print(f"✅ Windows → {args.windows_url}")

    if args.macos_url:
        app.setdefault("platforms", {})
        app["platforms"]["macos"] = {
            "downloadURL": args.macos_url,
            "size": args.macos_size or 0,
            "minOSVersion": "10.13",
            "date": now_iso(),
        }
        print(f"✅ macOS → {args.macos_url}")

    with open(args.apps_json, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)

    print(f"✅ Saved {args.apps_json}")


def _update_ios(apps_json, download_url, version, ipa_size, build_date):
    with open(apps_json, encoding="utf-8") as f:
        data = json.load(f)
    _update_ios_in_place(data["apps"][0], download_url, ipa_size, version, build_date)
    with open(apps_json, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
    print(f"✅ Updated {apps_json}: {version} → {download_url}")


def _update_ios_in_place(app: dict, download_url, ipa_size, version, build_date):
    new_version = {
        "version": version,
        "date": build_date,
        "size": ipa_size,
        "downloadURL": download_url,
        "minOSVersion": "16.0",
    }
    app.setdefault("versions", []).insert(0, new_version)
    app["versions"] = app["versions"][:10]

    # Top-level fields for Scarlet
    app["version"]            = version
    app["versionDate"]        = build_date
    app["versionDescription"] = f"Telegram + WireGuard VPN {version}"
    app["downloadURL"]        = download_url
    app["size"]               = ipa_size
    app["minOSVersion"]       = "16.0"
    print(f"✅ iOS IPA → {download_url}")


if __name__ == "__main__":
    main()
