import Foundation
import InvoiceDomain

public struct PDFRect: Hashable, Codable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
}

public struct PDFTextBlock: Hashable, Codable, Sendable {
    public enum Style: String, Codable, Sendable { case title, heading, body, amount, caption }
    public let text: String
    public let frame: PDFRect
    public let style: Style
}

public struct PDFPagePlan: Hashable, Codable, Sendable {
    public let number: Int
    public let blocks: [PDFTextBlock]
}

public struct PDFLayoutPlan: Hashable, Codable, Sendable {
    public static let pageWidth = 595.28
    public static let pageHeight = 841.89
    public static let margin = 36.0
    public let invoiceID: UUID
    public let pages: [PDFPagePlan]
}

public enum PDFLayoutPlanner {
    private static let bodyLineHeight = 13.0
    private static let rowPadding = 7.0

    public static func plan(invoice: IssuedInvoice, language: String = "ja") throws -> PDFLayoutPlan {
        let labels = Labels(language: language)
        var pages: [[PDFTextBlock]] = [[]]
        var pageIndex = 0
        var y = PDFLayoutPlan.margin
        let contentWidth = PDFLayoutPlan.pageWidth - 2 * PDFLayoutPlan.margin

        func append(_ text: String, style: PDFTextBlock.Style, height: Double, x: Double = PDFLayoutPlan.margin, width: Double = contentWidth) {
            if y + height > PDFLayoutPlan.pageHeight - PDFLayoutPlan.margin - 24 {
                pageIndex += 1
                pages.append([])
                y = PDFLayoutPlan.margin + 22
                pages[pageIndex].append(PDFTextBlock(text: labels.invoice + " · " + invoice.number, frame: PDFRect(x: PDFLayoutPlan.margin, y: PDFLayoutPlan.margin, width: contentWidth, height: 16), style: .caption))
            }
            pages[pageIndex].append(PDFTextBlock(text: text, frame: PDFRect(x: x, y: y, width: width, height: height), style: style))
            y += height
        }

        func visualLines(for text: String, charactersPerLine: Int) -> [String] {
            text.split(separator: "\n", omittingEmptySubsequences: false).flatMap { paragraph in
                if paragraph.isEmpty { return [""] }
                var remaining = String(paragraph)
                var lines: [String] = []
                while !remaining.isEmpty {
                    let end = remaining.index(
                        remaining.startIndex,
                        offsetBy: min(charactersPerLine, remaining.count)
                    )
                    lines.append(String(remaining[..<end]))
                    remaining = String(remaining[end...])
                }
                return lines
            }
        }

        func appendWrapped(
            _ text: String,
            style: PDFTextBlock.Style,
            charactersPerLine: Int,
            padding: Double = 0,
            minimumHeight: Double = 0
        ) {
            let maximumBlockHeight = PDFLayoutPlan.pageHeight - (2 * PDFLayoutPlan.margin) - 46
            let maximumLines = max(1, Int(floor((maximumBlockHeight - 2 * padding) / bodyLineHeight)))
            let lines = visualLines(for: text, charactersPerLine: charactersPerLine)
            var start = 0
            while start < lines.count {
                let end = min(start + maximumLines, lines.count)
                let chunk = lines[start..<end].joined(separator: "\n")
                let height = max(minimumHeight, Double(end - start) * bodyLineHeight + 2 * padding)
                append(chunk, style: style, height: height)
                start = end
            }
        }

        append(labels.invoice, style: .title, height: 34)
        append("\(labels.number): \(invoice.number)", style: .body, height: 18)
        append("\(labels.issueDate): \(invoice.issueDate.description)", style: .body, height: 18)
        appendWrapped(invoice.customerName + labels.recipientSuffix, style: .heading, charactersPerLine: 32, minimumHeight: 28)
        if !invoice.customerAddress.isEmpty {
            appendWrapped(invoice.customerAddress, style: .body, charactersPerLine: 44, minimumHeight: 20)
        }
        y += 8
        appendWrapped(invoice.issuer.issuerName, style: .heading, charactersPerLine: 32, minimumHeight: 22)
        if !invoice.issuer.postalAddress.isEmpty {
            appendWrapped(invoice.issuer.postalAddress, style: .body, charactersPerLine: 44, minimumHeight: 18)
        }
        if let registration = invoice.issuer.registrationNumber {
            append("\(labels.registration): \(registration)", style: .body, height: 18)
        }
        y += 12
        append(labels.details, style: .heading, height: 24)

        var lastGroup = ""
        for line in invoice.lines {
            let group = "\(line.workDate.description) · \(line.siteName)"
            if group != lastGroup {
                appendWrapped(group, style: .heading, charactersPerLine: 36, minimumHeight: 22)
                lastGroup = group
            }
            let amount = "¥\(line.net.yen)"
            appendWrapped(
                "\(line.description)\n\(line.quantity.description) \(line.unit) × ¥\(line.unitPrice.yen) · \(line.taxRate.label)        \(amount)",
                style: .body,
                charactersPerLine: 38,
                padding: rowPadding,
                minimumHeight: bodyLineHeight + 2 * rowPadding
            )
        }

        y += 10
        append("\(labels.subtotal): ¥\(invoice.subtotal.yen)", style: .amount, height: 22)
        for total in invoice.taxTotals {
            append("\(labels.tax) \(total.taxRate.label): ¥\(total.tax.yen)", style: .amount, height: 20)
        }
        append("\(labels.total): ¥\(invoice.grandTotal.yen)", style: .amount, height: 28)
        append("\(labels.dueDate): \(invoice.dueDate.description)", style: .body, height: 20)
        if !invoice.issuer.bankDetails.isEmpty {
            appendWrapped(invoice.issuer.bankDetails, style: .body, charactersPerLine: 44, minimumHeight: 40)
        }

        let plannedPages = pages.enumerated().map { index, blocks in
            var withFooter = blocks
            withFooter.append(PDFTextBlock(
                text: "\(index + 1) / \(pages.count)",
                frame: PDFRect(
                    x: PDFLayoutPlan.margin,
                    y: PDFLayoutPlan.pageHeight - PDFLayoutPlan.margin - 12,
                    width: contentWidth,
                    height: 12
                ),
                style: .caption
            ))
            return PDFPagePlan(number: index + 1, blocks: withFooter)
        }
        guard !plannedPages.isEmpty else { throw InvoiceError.corruptData("zero_page_pdf") }
        return PDFLayoutPlan(invoiceID: invoice.id, pages: plannedPages)
    }
}

private struct Labels {
    let invoice: String
    let number: String
    let issueDate: String
    let dueDate: String
    let registration: String
    let details: String
    let subtotal: String
    let tax: String
    let total: String
    let recipientSuffix: String

    init(language: String) {
        if language == "en" {
            invoice = "Invoice"; number = "Number"; issueDate = "Issue date"; dueDate = "Due date"
            registration = "Registration"; details = "Service details"; subtotal = "Subtotal"
            tax = "Tax"; total = "Total"; recipientSuffix = ""
        } else {
            invoice = "請求書"; number = "請求書番号"; issueDate = "発行日"; dueDate = "支払期限"
            registration = "登録番号"; details = "作業明細"; subtotal = "小計"
            tax = "消費税"; total = "合計"; recipientSuffix = " 御中"
        }
    }
}
