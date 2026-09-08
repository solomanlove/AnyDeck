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
        .macOS("10.15")
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
                    "-std=c++17",
                    "-I/opt/homebrew/opt/ffmpeg/include",
                    "-I/usr/local/opt/ffmpeg/include"
                ])
            ],
            linkerSettings: [
                .linkedFramework("AudioToolbox"),
                .linkedFramework("CoreVideo"),
                .unsafeFlags([
                    "-L\(libsDir)",
                    "-L/opt/homebrew/lib",
                    "-L/usr/local/lib",
                    "-lrust_scrcpy",
                    "-lavcodec",
                    "-lavformat",
                    "-lavutil",
                    "-lswscale",
                    "-lswresample",
                    "-lSvtAv1Enc",
                    "-lcrypto",
                    "-ldav1d",
                    "-lmp3lame",
                    "-lopus",
                    "-lssl",
                    "-lvpx",
                    "-lx264",
                    "-lx265"
                ])
            ]
        )
    ]
)
