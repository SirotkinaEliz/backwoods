# Backwoods: WireGuardKit XCFramework import
# Pre-built WireGuardKit (wireguard-go + wireguard-apple) as static xcframework.
#
# Build instructions:
#   1. Clone https://github.com/WireGuard/wireguard-apple
#   2. Build WireGuardKit.xcframework:
#      cd wireguard-apple
#      xcodebuild archive -scheme WireGuardKit \
#        -destination "generic/platform=iOS" \
#        -archivePath build/ios SKIP_INSTALL=NO BUILD_LIBRARY_FOR_DISTRIBUTION=YES
#      xcodebuild -create-xcframework \
#        -framework build/ios.xcarchive/Products/Library/Frameworks/WireGuardKit.framework \
#        -output WireGuardKit.xcframework
#   3. Copy WireGuardKit.xcframework to third-party/WireGuardKit/

load("@build_bazel_rules_apple//apple:apple.bzl", "apple_static_xcframework_import")

apple_static_xcframework_import(
    name = "WireGuardKit",
    xcframework = "WireGuardKit.xcframework",
    visibility = ["//visibility:public"],
)
