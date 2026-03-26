# Backwoods: Test helpers module
# Provides mock implementations and Signal test utilities

load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "SwiftSignalKitTestHelpers",
    testonly = True,
    srcs = glob(["Sources/**/*.swift"]),
    module_name = "SwiftSignalKitTestHelpers",
    visibility = ["//visibility:public"],
    deps = [
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/TunnelKit:TunnelKit",
    ],
)
