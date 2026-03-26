load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

# Backwoods: WireGuardTransport — WireGuard implementation of TransportProvider
# This module is linked into the Network Extension target only.

WIREGUARD_TRANSPORT_DEPS = [
    "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
    "//submodules/TunnelKit:TunnelKit",
    "//third-party/WireGuardKit:WireGuardKit",
]

swift_library(
    name = "WireGuardTransport",
    module_name = "WireGuardTransport",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = WIREGUARD_TRANSPORT_DEPS,
    visibility = [
        "//visibility:public",
    ],
)
