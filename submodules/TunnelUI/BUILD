# Backwoods: TunnelUI module
# UI components for tunnel status display and settings

load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "TunnelUI",
    srcs = glob(["Sources/**/*.swift"]),
    module_name = "TunnelUI",
    visibility = ["//visibility:public"],
    deps = [
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/TunnelKit:TunnelKit",
        "//submodules/TunnelManager:TunnelManager",
    ],
)
