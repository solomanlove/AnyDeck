// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import Foundation
import PackageDescription

let packageFile = URL(fileURLWithPath: #file).resolvingSymlinksInPath()
let packageDir = packageFile.deletingLastPathComponent()
let macosDir = packageDir.deletingLastPathComponent()
let libsDir = macosDir.appendingPathComponent("Libs").path

let package = Package(
    name: "scrcpy_flutter",
    platforms: [
        .macOS("11.0")
    ],
    products: [
        .library(name: "scrcpy-flutter", targets: ["scrcpy_flutter"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "scrcpy_flutter",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ],
            path: "Sources/scrcpy_flutter",
            resources: [],
            cxxSettings: [
                .headerSearchPath("include"),
                .headerSearchPath("include/scrcpy_flutter"),
                .unsafeFlags([
                    "-std=c++17"
                ])
            ],
            linkerSettings: [
                .linkedFramework("AudioToolbox"),
                .linkedFramework("VideoToolbox"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("CoreVideo"),
                .unsafeFlags([
                    "-L\(libsDir)",
                    "-lrust_scrcpy"
                ])
            ]
        )
    ]
)
