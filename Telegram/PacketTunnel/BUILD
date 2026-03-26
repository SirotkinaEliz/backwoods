# Backwoods: PacketTunnel Network Extension target
# This BUILD file defines the ios_extension for the WireGuard packet tunnel.
# It should be included as a dependency in the main Telegram ios_application target.
#
# Integration: Add to Telegram/BUILD ios_application extensions list:
#   extensions = [
#       ... existing extensions ...,
#       "//Telegram/PacketTunnel:PacketTunnelExtension",  # Backwoods
#   ],

load("@build_bazel_rules_apple//apple:apple.bzl", "ios_extension")
load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

# PacketTunnel Swift library
swift_library(
    name = "PacketTunnelLib",
    srcs = glob(["*.swift"]),
    module_name = "PacketTunnel",
    deps = [
        "//submodules/TunnelKit:TunnelKit",
        "//submodules/WireGuardTransport:WireGuardTransport",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
    ],
)

# PacketTunnel iOS Extension
ios_extension(
    name = "PacketTunnelExtension",
    bundle_id = "com.backwoods.app.PacketTunnel",
    entitlements = "Entitlements.plist",
    families = ["iphone", "ipad"],
    infoplists = ["Info.plist"],
    minimum_os_version = "15.0",
    visibility = ["//visibility:public"],
    deps = [
        ":PacketTunnelLib",
    ],
)
