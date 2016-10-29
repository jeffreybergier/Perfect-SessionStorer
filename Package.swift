import PackageDescription

let package = Package(
     name: "Perfect-SessionStorer",
	dependencies: [
		.Package(url: "https://github.com/PerfectlySoft/Perfect-HTTP.git", majorVersion: 2, minor: 0),
		.Package(url: "https://github.com/krzyzanowskim/CryptoSwift.git", majorVersion: 0, minor: 6)
    ]
)
