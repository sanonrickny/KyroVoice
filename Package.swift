// swift-tools-version:6.1
import PackageDescription

let package = Package(
    name: "KyroVoice",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "KyroVoice", targets: ["KyroVoice"])
    ],
    dependencies: [
        // No NeMo text normalizer: it only serves TTS, and Parakeet does its own ITN.
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.15.7", traits: [])
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
    ],
    swiftLanguageModes: [.v5]
)
