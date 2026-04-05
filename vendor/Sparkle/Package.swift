// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Sparkle",
    defaultLocalization: "en",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(name: "Sparkle", type: .dynamic, targets: ["Sparkle"]),
    ],
    targets: [
        .target(
            name: "Sparkle",
            path: "Sources/Sparkle",
            resources: [
                .process("SUStatus.xib"),
                .process("SUUpdateAlert.xib"),
                .process("SUUpdatePermissionPrompt.xib"),
                .process("ReleaseNotesColorStyle.css"),
            ],
            publicHeadersPath: "include",
            cSettings: [
                // internal/ holds the ~100 private headers (public ones are in include/Sparkle/
                // via publicHeadersPath). Lets .m files use `#import "Foo.h"` for private headers.
                .headerSearchPath("internal"),
                // include/Sparkle/ for `#import "Foo.h"` style references to public headers.
                .headerSearchPath("include/Sparkle"),
                // include/ (parent of Sparkle/) for `#import <Sparkle/Foo.h>` style references —
                // used by private headers that depend on the public API.
                .headerSearchPath("include"),
                // Lets SUSignatureVerifier.m use `#import "ed25519.h"`.
                .headerSearchPath("ed25519"),

                // Defines from upstream's ConfigCommon.xcconfig + ConfigFramework.xcconfig.
                // Macros mapping objc_direct attributes — required for headers using SPU_OBJC_DIRECT.
                .define("SPU_OBJC_DIRECT", to: "__attribute__((objc_direct))"),
                .define("SPU_OBJC_DIRECT_MEMBERS", to: "__attribute__((objc_direct_members))"),
                // Identifies us as the Sparkle library build (not a Sparkle helper or consumer).
                .define("BUILDING_SPARKLE", to: "1"),
                // Feature toggles. Setting legacy code paths to 0 lets the linker strip them.
                .define("SPARKLE_BUILD_UI_BITS", to: "1"),
                .define("SPARKLE_COPY_LOCALIZATIONS", to: "1"),
                .define("SPARKLE_NORMALIZE_INSTALLED_APPLICATION_NAME", to: "0"),
                .define("SPARKLE_BUILD_LEGACY_SUUPDATER", to: "0"),
                .define("SPARKLE_BUILD_LEGACY_DSA_SUPPORT", to: "0"),
                .define("SPARKLE_BUILD_PACKAGE_SUPPORT", to: "0"),
                .define("SPARKLE_BUILD_LEGACY_DELTA_SUPPORT", to: "0"),
                .define("SPARKLE_BUILD_BZIP2_DELTA_SUPPORT", to: "0"),
                .define("GENERATE_APPCAST_BUILD_LEGACY_DSA_SUPPORT", to: "0"),
                // String constants the library references at runtime. We don't embed XPC services.
                .define("SPARKLE_BUNDLE_IDENTIFIER", to: "\"org.sparkle-project.Sparkle\""),
                .define("CURRENT_PROJECT_VERSION", to: "\"2054\""),
                .define("MARKETING_VERSION", to: "\"2.9.1\""),
                .define("SPARKLE_RELAUNCH_TOOL_NAME", to: "\"Autoupdate\""),
                .define("SPARKLE_INSTALLER_PROGRESS_TOOL_NAME", to: "\"Updater\""),
                .define("SPARKLE_INSTALLER_PROGRESS_TOOL_BUNDLE_ID", to: "\"org.sparkle-project.Sparkle.Updater\""),
                .define("SPARKLE_ICON_NAME", to: "\"AppIcon\""),
                .define("INSTALLER_LAUNCHER_NAME", to: "\"Installer\""),
                .define("INSTALLER_LAUNCHER_BUNDLE_ID", to: "\"org.sparkle-project.InstallerLauncher\""),
                .define("INSTALLER_LAUNCHER_XPC_SERVICE_EMBEDDED", to: "0"),
                .define("INSTALLER_CONNECTION_NAME", to: "\"InstallerConnection\""),
                .define("INSTALLER_CONNECTION_BUNDLE_ID", to: "\"org.sparkle-project.InstallerConnection\""),
                .define("INSTALLER_CONNECTION_XPC_SERVICE_EMBEDDED", to: "0"),
                .define("INSTALLER_STATUS_NAME", to: "\"InstallerStatus\""),
                .define("INSTALLER_STATUS_BUNDLE_ID", to: "\"org.sparkle-project.InstallerStatus\""),
                .define("INSTALLER_STATUS_XPC_SERVICE_EMBEDDED", to: "0"),
                .define("DOWNLOADER_NAME", to: "\"Downloader\""),
                .define("DOWNLOADER_BUNDLE_ID", to: "\"org.sparkle-project.DownloaderService\""),
                .define("DOWNLOADER_XPC_SERVICE_EMBEDDED", to: "0"),
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("WebKit"),
                .linkedFramework("Security"),
                .linkedFramework("SystemConfiguration"),
            ]
        ),
    ]
)
