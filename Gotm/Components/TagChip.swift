import SwiftUI

// MARK: - Flow layout for wrapping chips

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let maxWidth = bounds.maxX
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Tag chip

struct TagChip: View {
    let tag: EntryTag
    var isSelected: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: tag.type.icon)
                .imageScale(.small)
            Text(tag.type.label)
        }
        .font(.caption)
        .fontWeight(.medium)
        .foregroundStyle(chipColor.opacity(isSelected ? 1.0 : 0.80))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(chipColor.opacity(isSelected ? 0.20 : 0.12))
        .clipShape(Capsule())
        .overlay {
            if isSelected {
                Capsule().strokeBorder(chipColor.opacity(0.45), lineWidth: 1)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }

    var chipColor: Color {
        switch tag.type {
        case .event:     return Color(red: 0.27, green: 0.52, blue: 0.93) // blue
        case .reminder:  return Color(red: 0.95, green: 0.60, blue: 0.15) // amber
        case .action:    return Color(red: 0.88, green: 0.28, blue: 0.22) // coral red
        case .idea:      return Color(red: 0.22, green: 0.70, blue: 0.42) // green
        case .question:  return Color(red: 0.42, green: 0.35, blue: 0.85) // indigo
        case .decision:  return Color(red: 0.12, green: 0.65, blue: 0.65) // teal
        case .person:    return Color(red: 0.55, green: 0.52, blue: 0.58) // warm grey
        case .reference: return Color(red: 0.35, green: 0.52, blue: 0.72) // slate blue
        case .purchase:  return Color(red: 0.58, green: 0.28, blue: 0.82) // violet
        case .money:     return Color(red: 0.80, green: 0.60, blue: 0.08) // golden yellow
        }
    }
}
