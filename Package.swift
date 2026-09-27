// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DatedServiceInvoice",
    defaultLocalization: "ja",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        .library(name: "InvoiceDomain", targets: ["InvoiceDomain"]),
        .library(name: "InvoicePersistence", targets: ["InvoicePersistence"]),
        .library(name: "InvoicePDF", targets: ["InvoicePDF"]),
        .library(name: "InvoiceBackup", targets: ["InvoiceBackup"]),
        .library(name: "InvoiceEntitlements", targets: ["InvoiceEntitlements"]),
        .executable(name: "invoice-harness", targets: ["InvoiceHarness"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.11.1")
    ],
    targets: [
        .target(name: "InvoiceDomain"),
        .target(
            name: "InvoicePersistence",
            dependencies: ["InvoiceDomain", .product(name: "GRDB", package: "GRDB.swift")]
        ),
        .target(name: "InvoicePDF", dependencies: ["InvoiceDomain"]),
        .target(name: "InvoiceBackup", dependencies: ["InvoiceDomain", "InvoicePersistence"]),
        .target(name: "InvoiceEntitlements", dependencies: ["InvoiceDomain"]),
        .executableTarget(
            name: "InvoiceHarness",
            dependencies: ["InvoiceDomain", "InvoicePersistence", "InvoicePDF", "InvoiceBackup"]
        ),
        .testTarget(name: "InvoiceDomainTests", dependencies: ["InvoiceDomain"]),
        .testTarget(
            name: "InvoicePersistenceTests",
            dependencies: [
                "InvoiceDomain", "InvoicePersistence", "InvoicePDF", "InvoiceBackup",
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
