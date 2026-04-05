// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AppCenter",
    platforms: [.macOS(.v10_13)],
    products: [
        // Static (matching Microsoft's own Package.swift). Consumers `import AppCenter` /
        // `import AppCenterCrashes` and the linker pulls the .o files directly into the
        // host binary. The host target must list these with Embed = "Do Not Embed".
        .library(name: "AppCenter", type: .static, targets: ["AppCenter"]),
        .library(name: "AppCenterCrashes", type: .static, targets: ["AppCenterCrashes"]),
    ],
    targets: [
        .target(
            name: "AppCenter",
            path: "Sources/AppCenter",
            cSettings: [
                .define("APP_CENTER_C_VERSION", to: "\"4.3.0\""),
                .define("APP_CENTER_C_BUILD", to: "\"1\""),
                .headerSearchPath("include"),
                .headerSearchPath("Internals"),
                .headerSearchPath("Internals/DelegateForwarder"),
                .headerSearchPath("Internals/HttpClient"),
                .headerSearchPath("Internals/HttpClient/Util"),
                .headerSearchPath("Internals/Ingestion"),
                .headerSearchPath("Internals/Ingestion/Util"),
                .headerSearchPath("Internals/Context/UserId"),
                .headerSearchPath("Internals/Context/Device"),
                .headerSearchPath("Internals/Context/Session"),
                .headerSearchPath("Internals/Util"),
                .headerSearchPath("Internals/Storage"),
                .headerSearchPath("Internals/Channel"),
                .headerSearchPath("Internals/Model"),
                .headerSearchPath("Internals/Model/Util"),
                .headerSearchPath("Internals/Model/CommonSchema"),
                .headerSearchPath("Internals/Model/Properties"),
                .headerSearchPath("Internals/Vendor/Reachability"),
                .headerSearchPath("Model"),
            ],
            linkerSettings: [
                .linkedLibrary("z"),
                .linkedLibrary("sqlite3"),
                .linkedFramework("Foundation"),
                .linkedFramework("SystemConfiguration"),
                .linkedFramework("AppKit"),
                .linkedFramework("CoreTelephony"),
            ]
        ),
        .target(
            name: "AppCenterCrashes",
            dependencies: ["AppCenter", "PLCrashReporter"],
            path: "Sources/AppCenterCrashes",
            cSettings: [
                .headerSearchPath("include"),
                .headerSearchPath("WrapperSDKUtilities"),
                .headerSearchPath("Internals"),
                .headerSearchPath("Internals/Util"),
                .headerSearchPath("Internals/Model"),
                .headerSearchPath("Model"),
                .headerSearchPath("../AppCenter/include"),
                .headerSearchPath("../AppCenter/Internals"),
                .headerSearchPath("../AppCenter/Internals/DelegateForwarder"),
                .headerSearchPath("../AppCenter/Internals/HttpClient"),
                .headerSearchPath("../AppCenter/Internals/HttpClient/Util"),
                .headerSearchPath("../AppCenter/Internals/Ingestion"),
                .headerSearchPath("../AppCenter/Internals/Ingestion/Util"),
                .headerSearchPath("../AppCenter/Internals/Context/UserId"),
                .headerSearchPath("../AppCenter/Internals/Context/Device"),
                .headerSearchPath("../AppCenter/Internals/Context/Session"),
                .headerSearchPath("../AppCenter/Internals/Util"),
                .headerSearchPath("../AppCenter/Internals/Storage"),
                .headerSearchPath("../AppCenter/Internals/Channel"),
                .headerSearchPath("../AppCenter/Internals/Model"),
                .headerSearchPath("../AppCenter/Internals/Model/Util"),
                .headerSearchPath("../AppCenter/Internals/Model/CommonSchema"),
                .headerSearchPath("../AppCenter/Internals/Model/Properties"),
                .headerSearchPath("../AppCenter/Internals/Vendor/Reachability"),
                .headerSearchPath("../AppCenter/Model"),
                // PLCrashReporter public headers — AppCenterCrashes uses `#import "CrashReporter.h"` (quoted).
                .headerSearchPath("../../Frameworks/CrashReporter.xcframework/macos-arm64_x86_64/CrashReporter.framework/Headers"),
            ],
            linkerSettings: [
                .linkedFramework("Foundation"),
                .linkedFramework("AppKit"),
            ]
        ),
        .binaryTarget(
            name: "PLCrashReporter",
            path: "Frameworks/CrashReporter.xcframework"
        ),
    ]
)
