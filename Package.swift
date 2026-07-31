// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "KyroVoice",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "KyroVoice", targets: ["KyroVoice"])
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.15.5")
    ],
    targets: [
        .target(
            name: "KyroVoiceObjC",
            path: "Sources/KyroVoiceObjC",
            publicHeadersPath: "include"
        ),
        .executableTarget(
            name: "KyroVoice",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio"),
                "KyroVoiceObjC"
            ],
            path: "Sources/KyroVoice"
        )
    ]
)
