#!/usr/bin/env python3
"""Patch nicegram Make.py to call set_disable_provisioning_profiles() when xcodeManagedCodesigning is used."""
import sys, re

path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

# Add set_disable_provisioning_profiles() before invoke_build() in build()
# Original:
#     bazel_command_line.invoke_build()
# Patched:
#     if getattr(arguments, 'xcodeManagedCodesigning', False):
#         bazel_command_line.set_disable_provisioning_profiles()
#     bazel_command_line.invoke_build()

old = '    bazel_command_line.invoke_build()'
new = ('    if getattr(arguments, "xcodeManagedCodesigning", False):\n'
       '        bazel_command_line.set_disable_provisioning_profiles()\n'
       '    bazel_command_line.invoke_build()')

patched = content.replace(old, new)
if patched == content:
    print("WARNING: patch not applied - pattern not found")
    sys.exit(0)

with open(path, 'w') as f:
    f.write(patched)
print("Make.py patched: set_disable_provisioning_profiles() added for xcodeManagedCodesigning")
