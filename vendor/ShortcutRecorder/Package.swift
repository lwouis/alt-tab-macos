// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ShortcutRecorder",
    defaultLocalization: "en",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(name: "ShortcutRecorder", type: .static, targets: ["ShortcutRecorder"]),
    ],
    targets: [
        .target(
            name: "ShortcutRecorder",
            path: "Sources/ShortcutRecorder",
            resources: [.process("Images.xcassets")],
            publicHeadersPath: "include",
            cSettings: [
                // Lets .m files use `#import "SRCommon.h"` as well as `<ShortcutRecorder/SRCommon.h>`.
                .headerSearchPath("include/ShortcutRecorder"),
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
            ]
        ),
    ]
)
