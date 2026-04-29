// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "KyroVoice",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "KyroVoice", targets: ["KyroVoice"])
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit", from: "0.9.0")
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
                .product(name: "WhisperKit", package: "WhisperKit"),
                "KyroVoiceObjC"
            ],
            path: "Sources/KyroVoice"
        )
    ]
)
