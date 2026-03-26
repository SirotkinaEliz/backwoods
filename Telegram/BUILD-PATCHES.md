# Backwoods: BUILD patches for main Telegram app
# ==============================================================================
# This file documents all changes needed in the upstream Telegram/BUILD file.
# Apply these changes after forking the Telegram-iOS repository.
#
# IMPORTANT: This is a REFERENCE file, not an executable BUILD file.
# The actual changes must be applied to the existing Telegram/BUILD.
# ==============================================================================

# --- PATCH 1: Add TUNNEL_DEPS variable ---
# Location: Top of Telegram/BUILD, after existing variable definitions
#
# TUNNEL_DEPS = [
#     "//submodules/TunnelKit:TunnelKit",
#     "//submodules/TunnelManager:TunnelManager",
#     "//submodules/TunnelUI:TunnelUI",
# ]

# --- PATCH 2: Add WireGuardKit xcframework ---
# Location: After existing xcframework imports
#
# apple_static_xcframework_import(
#     name = "WireGuardKit",
#     xcframework = "//third-party/WireGuardKit:WireGuardKit",
# )

# --- PATCH 3: Add PacketTunnel extension to ios_application ---
# Location: In the ios_application() rule for Telegram app
#
# ios_application(
#     name = "Telegram",
#     ...
#     extensions = [
#         ... existing extensions ...,
#         "//Telegram/PacketTunnel:PacketTunnelExtension",  # Backwoods VPN
#     ],
#     entitlements = "Backwoods-App-Entitlements.plist",  # Backwoods: merged entitlements
#     ...
#     deps = [
#         ... existing deps ...,
#     ] + TUNNEL_DEPS,  # Backwoods
# )

# --- PATCH 4: Add provisioning profile mapping (if using paid dev account) ---
# Location: In the ios_application() rule
#
# provisioning_profile = select({
#     "//build-system/bazel-utils:debug": None,  # Automatic signing
#     "//conditions:default": "//Telegram:BackwoodsProvisioningProfile",
# }),

# --- PATCH 5: Bundle the embedded WireGuard configuration ---
# Location: New filegroup target
#
# filegroup(
#     name = "BackwoodsResources",
#     srcs = [
#         "backwoods-tunnel.json",  # Embedded WireGuard config
#     ],
# )
#
# Then add to ios_application resources:
#   resources = [
#       ... existing resources ...,
#       ":BackwoodsResources",  # Backwoods
#   ],
