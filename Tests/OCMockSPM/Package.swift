// swift-tools-version: 5.6
// Local wrapper that exposes OCMock to the Texture SPM package.
//
// SPM refuses to let a root package declare a remote dependency whose targets
// use unsafeFlags (OCMock needs -fno-objc-arc). The workaround described in
// https://github.com/erikdoe/ocmock/issues/500#issuecomment-1002700625 is to
// reference OCMock from a *local* package — local packages are trusted by SPM
// and their transitive remote dependencies are not subject to the unsafeFlags
// restriction.

import PackageDescription

let package = Package(
    name: "OCMockSPM",
    products: [
        .library(name: "OCMockSPM", targets: ["OCMockSPM"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/erikdoe/ocmock.git",
            .revision("229b8fa15917173a138beb07765a408ac617bc03") // v3.9.4
        ),
    ],
    targets: [
        .target(
            name: "OCMockSPM",
            dependencies: [
                .product(name: "OCMock", package: "ocmock"),
            ],
            path: "Sources/OCMockSPM",
            publicHeadersPath: "include"
        ),
    ]
)
