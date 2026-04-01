#!/usr/bin/env python3
"""Patch Make.py for Backwoods CI: disable provisioning profiles and extensions."""
import sys

path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

patched = False

# Patch: inject CI flags into common_args (added after '--verbose_failures')
# This ensures --//Telegram:disableProvisioningProfiles is passed to every bazel invocation.
# Note: disableExtensions is NOT set so the PacketTunnel VPN extension is included.
old = "            '--verbose_failures',"
new = ("            '--verbose_failures',\n"
       "            '--//Telegram:disableProvisioningProfiles',  # Backwoods CI\n"
       "            '--action_env=DEVELOPER_DIR',               # Backwoods CI: fix ibtool iOS platform")

if old in content:
    content = content.replace(old, new, 1)
    patched = True
    print("Make.py patched: disableProvisioningProfiles + action_env added to common_args")
else:
    print("WARNING: '--verbose_failures' not found in common_args — trying fallback")
    # Fallback: patch invoke_build() to always set disable_provisioning_profiles
    old2 = '        if self.disable_provisioning_profiles:'
    new2 = ('        self.disable_provisioning_profiles = True  # Backwoods CI\n'
            '        if self.disable_provisioning_profiles:')
    if old2 in content:
        content = content.replace(old2, new2, 1)
        patched = True
        print("Make.py patched (fallback): disable_provisioning_profiles forced True")
    else:
        print("ERROR: no patch pattern found — Make.py not modified")

if patched:
    with open(path, 'w') as f:
        f.write(content)
    print("Make.py saved OK")
