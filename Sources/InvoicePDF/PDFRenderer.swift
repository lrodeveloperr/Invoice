import Foundation
import InvoiceDomain

#if canImport(UIKit)
import UIKit

public enum CanonicalPDFRenderer {
    public static func render(invoice: IssuedInvoice, language: String = "ja") throws -> Data {
        let plan = try PDFLayoutPlanner.plan(invoice: invoice, language: language)
        let bounds = CGRect(x: 0, y: 0, width: PDFLayoutPlan.pageWidth, height: PDFLayoutPlan.pageHeight)
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: "Invoice \(invoice.number)",
            kCGPDFContextCreator as String: "Dated Service Invoice"
        ]
        return UIGraphicsPDFRenderer(bounds: bounds, format: format).pdfData { context in
            for (pageIndex, page) in plan.pages.enumerated() {
                context.beginPage()
                UIColor.white.setFill()
                context.cgContext.fill(bounds)
                for block in page.blocks { draw(block, pdfStyle: invoice.issuer.effectivePDFStyle) }
                if pageIndex == 0,
                   let logoData = invoice.issuer.logoPNGData,
                   let logo = UIImage(data: logoData) {
                    let size = CGSize(width: 54, height: 54)
                    let rect = CGRect(
                        x: bounds.maxX - PDFLayoutPlan.margin - size.width,
                        y: PDFLayoutPlan.margin,
                        width: size.width,
                        height: size.height
                    )
                    logo.draw(in: rect)
                }
            }
        }
    }

    private static func draw(_ block: PDFTextBlock, pdfStyle: PDFStyle) {
        let font: UIFont
        let color: UIColor
        let alignment: NSTextAlignment
        let accent = UIColor(red: 0.08, green: 0.25, blue: 0.42, alpha: 1)
        switch block.style {
        case .title:
            font = .systemFont(ofSize: pdfStyle == .compact ? 20 : 24, weight: .bold)
            color = pdfStyle == .modern ? accent : .label
            alignment = .left
        case .heading:
            font = .systemFont(ofSize: pdfStyle == .compact ? 10 : 11, weight: .semibold)
            color = pdfStyle == .modern ? accent : .label
            alignment = .left
        case .body:
            font = .systemFont(ofSize: pdfStyle == .compact ? 8 : 9, weight: .regular)
            color = .label
            alignment = .left
        case .amount:
            font = .monospacedDigitSystemFont(ofSize: pdfStyle == .compact ? 9 : 10, weight: .semibold)
            color = pdfStyle == .modern ? accent : .label
            alignment = .right
        case .caption: font = .systemFont(ofSize: 9, weight: .regular); color = .secondaryLabel; alignment = .right
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]
        let rect = CGRect(x: block.frame.x, y: block.frame.y, width: block.frame.width, height: block.frame.height)
        (block.text as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes, context: nil)
    }
}
#else
public enum CanonicalPDFRenderer {
    public static func render(invoice: IssuedInvoice, language: String = "ja") throws -> Data {
        _ = try PDFLayoutPlanner.plan(invoice: invoice, language: language)
        throw InvoiceError.corruptData("uikit_pdf_renderer_unavailable")
    }
}
#endif
