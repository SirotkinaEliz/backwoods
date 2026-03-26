load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

# Backwoods: TunnelManager — main app-side tunnel management
# This module is linked into the main Telegram app target.
# It manages VPN configuration, status monitoring, IPC, and auto-reconnect.

TUNNEL_MANAGER_DEPS = [
    "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
    "//submodules/TunnelKit:TunnelKit",
]

swift_library(
    name = "TunnelManager",
    module_name = "TunnelManager",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = TUNNEL_MANAGER_DEPS,
    visibility = [
        "//visibility:public",
    ],
)
