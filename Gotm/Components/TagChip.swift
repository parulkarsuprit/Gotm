import SwiftUI

// MARK: - Custom Button Style for TagChip
struct TagChipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

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
    var actionState: TagActionState = .idle
    var onConfirm: (() -> Void)? = nil
    var onAction: (() -> Void)? = nil
    var showActionIndicator: Bool = false

    var body: some View {
        // Use Button for proper tap handling that takes priority over parent gestures
        Button(action: {
            handleTap()
        }) {
            HStack(spacing: 4) {
                Image(systemName: iconName)
                    .imageScale(.small)
                Text(tag.type.label)
                
                // State indicators
                switch actionState {
                case .processing:
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 10, height: 10)
                case .completed:
                    Image(systemName: "checkmark")
                        .imageScale(.small)
                        .fontWeight(.bold)
                case .failed:
                    Image(systemName: "exclamationmark")
                        .imageScale(.small)
                        .fontWeight(.bold)
                case .idle:
                    // Priority 1: Show action icon for actionable tags (Calendar, Reminder, To-do, Purchase)
                    if showActionIndicator && isActionableTag(tag.type) {
                        Image(systemName: actionIcon)
                            .imageScale(.small)
                            .fontWeight(.semibold)
                    } else if tag.status == .suggested {
                        // Show + only for non-actionable tags when suggested
                        Image(systemName: "plus")
                            .imageScale(.small)
                            .fontWeight(.bold)
                    } else if showActionIndicator {
                        // Fallback for non-actionable tags with share action
                        Image(systemName: actionIcon)
                            .imageScale(.small)
                            .fontWeight(.semibold)
                    }
                }
            }
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(chipColor.opacity(backgroundOpacity))
            .clipShape(Capsule())
            .overlay(chipOverlay)
        }
        .buttonStyle(TagChipButtonStyle())
        .disabled(actionState == .processing)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        .animation(.easeInOut(duration: 0.15), value: tag.status)
        .animation(.easeInOut(duration: 0.15), value: actionState)
    }
    
    private func handleTap() {
        switch actionState {
        case .processing:
            return // Ignore while processing
        case .completed:
            // Already added - provide haptic feedback that it's already done
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred()
        case .failed, .idle:
            if tag.status == .suggested {
                // If onConfirm is provided, use it (for detail view with confirmation)
                // Otherwise fall back to onAction (for card view)
                if onConfirm != nil {
                    onConfirm?()
                } else {
                    onAction?()
                }
            } else if showActionIndicator {
                onAction?()
            }
        }
    }
    
    private var iconName: String {
        tag.type.icon
    }
    
    private var actionIcon: String {
        switch tag.type {
        case .event:
            return "arrow.up.forward"
        case .reminder, .action:
            return "checklist"
        case .purchase:
            return "cart.badge.plus"
        case .reference, .note, .idea, .decision, .question, .person, .money:
            return "square.and.arrow.up"
        }
    }
    
    /// Returns true for tags that create items in Apple apps (Calendar, Reminders, To-do, Shopping)
    private func isActionableTag(_ type: TagType) -> Bool {
        switch type {
        case .event, .reminder, .action, .purchase:
            return true
        case .reference, .note, .idea, .decision, .question, .person, .money:
            return false
        }
    }
    
    private var foregroundColor: Color {
        let base = chipColor
        switch actionState {
        case .processing:
            return base.opacity(0.5)
        case .completed:
            return base
        case .failed:
            return .red
        case .idle:
            if isSelected { return base }
            if tag.status == .suggested { return base.opacity(0.60) }
            return base.opacity(0.80)
        }
    }
    
    private var backgroundOpacity: Double {
        switch actionState {
        case .processing:
            return 0.06
        case .completed:
            return 0.20
        case .failed:
            return 0.12
        case .idle:
            if isSelected { return 0.20 }
            if tag.status == .suggested { return 0.06 }
            return 0.12
        }
    }
    
    @ViewBuilder
    private var chipOverlay: some View {
        switch actionState {
        case .completed:
            Capsule().strokeBorder(chipColor.opacity(0.60), lineWidth: 1.5)
        case .processing:
            EmptyView()
        case .failed:
            Capsule().strokeBorder(Color.red.opacity(0.50), lineWidth: 1)
        case .idle:
            if isSelected {
                Capsule().strokeBorder(chipColor.opacity(0.45), lineWidth: 1)
            } else if tag.status == .suggested {
                Capsule()
                    .strokeBorder(chipColor.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
        }
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
        case .note:      return Color(red: 0.55, green: 0.55, blue: 0.55) // neutral grey
        }
    }
}
