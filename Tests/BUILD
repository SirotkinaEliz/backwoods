# Backwoods: Test targets

load("@build_bazel_rules_swift//swift:swift.bzl", "swift_test")

swift_test(
    name = "TunnelKitTests",
    srcs = glob(["TunnelKitTests/**/*.swift"]),
    deps = [
        "//submodules/TunnelKit:TunnelKit",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/SwiftSignalKitTestHelpers:SwiftSignalKitTestHelpers",
    ],
)

swift_test(
    name = "TunnelManagerTests",
    srcs = glob(["TunnelManagerTests/**/*.swift"]),
    deps = [
        "//submodules/TunnelManager:TunnelManager",
        "//submodules/TunnelKit:TunnelKit",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/SwiftSignalKitTestHelpers:SwiftSignalKitTestHelpers",
    ],
)

swift_test(
    name = "WireGuardTransportTests",
    srcs = glob(["WireGuardTransportTests/**/*.swift"]),
    deps = [
        "//submodules/WireGuardTransport:WireGuardTransport",
        "//submodules/TunnelKit:TunnelKit",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/SwiftSignalKitTestHelpers:SwiftSignalKitTestHelpers",
    ],
)
