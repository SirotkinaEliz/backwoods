#!/usr/bin/env python3
"""
Update docs/apps.json with the latest GLUSH release.
Usage: update-altstore.py <download_url> <version> <ipa_size_bytes> <build_date_iso> <apps_json_path>
"""
import json
import sys
import os


def main():
    if len(sys.argv) < 5:
        print("Usage: update-altstore.py <download_url> <version> <ipa_size> <build_date> [apps_json_path]")
        sys.exit(1)

    download_url = sys.argv[1]
    version = sys.argv[2]
    ipa_size = int(sys.argv[3]) if sys.argv[3].isdigit() else 0
    build_date = sys.argv[4]
    apps_json_path = sys.argv[5] if len(sys.argv) > 5 else "docs/apps.json"

    if not os.path.exists(apps_json_path):
        print(f"ERROR: {apps_json_path} not found")
        sys.exit(1)

    with open(apps_json_path, encoding="utf-8") as f:
        data = json.load(f)

    new_version = {
        "version": version,
        "date": build_date,
        "size": ipa_size,
        "downloadURL": download_url,
        "minOSVersion": "16.0"
    }

    # Insert at the front of versions list
    data["apps"][0]["versions"].insert(0, new_version)
    # Keep only the last 10 versions
    data["apps"][0]["versions"] = data["apps"][0]["versions"][:10]

    # Also update top-level fields (required by Scarlet)
    data["apps"][0]["version"] = version
    data["apps"][0]["versionDate"] = build_date
    data["apps"][0]["versionDescription"] = f"Telegram + WireGuard VPN build {version}"
    data["apps"][0]["downloadURL"] = download_url
    data["apps"][0]["size"] = ipa_size
    data["apps"][0]["minOSVersion"] = "16.0"

    with open(apps_json_path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)

    print(f"✅ Updated {apps_json_path}: {version} → {download_url}")


if __name__ == "__main__":
    main()
