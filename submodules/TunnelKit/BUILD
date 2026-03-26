load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

# Backwoods: TunnelKit — transport abstraction layer
# This module defines protocols and types shared between the main app and the tunnel extension.
# It has minimal dependencies (only SwiftSignalKit) and is designed to be linked into both targets.

TUNNEL_KIT_DEPS = [
    "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
]

swift_library(
    name = "TunnelKit",
    module_name = "TunnelKit",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = TUNNEL_KIT_DEPS,
    visibility = [
        "//visibility:public",
    ],
)
