import InvoiceDomain
import SwiftUI

func yenText(_ money: Money) -> String {
    "¥" + money.yen.formatted(.number.grouping(.automatic))
}

func localDateText(_ date: LocalDate) -> String {
    String(format: "%04d/%02d/%02d", date.year, date.month, date.day)
}

func dateValue(_ date: LocalDate) -> Date {
    Calendar(identifier: .gregorian).date(
        from: DateComponents(year: date.year, month: date.month, day: date.day)
    ) ?? .distantPast
}

struct EmptyDetailView: View {
    let title: String
    let systemImage: String
    let description: String

    var body: some View {
        ContentUnavailableView(title, systemImage: systemImage, description: Text(description))
    }
}

struct StateBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule())
    }
}
