import Foundation

enum TagType: String, Codable, CaseIterable {
    case action
    case event
    case reminder
    case question
    case idea
    case decision
    case person
    case reference
    case purchase
    case money
    case note

    var label: String {
        switch self {
        case .action:    return "Action"
        case .event:     return "Event"
        case .reminder:  return "Reminder"
        case .question:  return "Question"
        case .idea:      return "Idea"
        case .decision:  return "Decision"
        case .person:    return "Person"
        case .reference: return "Reference"
        case .purchase:  return "Purchase"
        case .money:     return "Money"
        case .note:      return "Note"
        }
    }

    var icon: String {
        switch self {
        case .action:    return "bolt.fill"
        case .event:     return "calendar"
        case .reminder:  return "bell.fill"
        case .question:  return "questionmark.circle.fill"
        case .idea:      return "lightbulb.fill"
        case .decision:  return "checkmark.seal.fill"
        case .person:    return "person.fill"
        case .reference: return "doc.text.fill"
        case .purchase:  return "cart.fill"
        case .money:     return "dollarsign.circle.fill"
        case .note:      return "note.text"
        }
    }

    /// Lower = shown first in the feed chips
    var feedPriority: Int {
        switch self {
        case .event:     return 0
        case .reminder:  return 1
        case .action:    return 2
        case .question:  return 3
        case .idea:      return 4
        case .decision:  return 5
        case .person:    return 6
        case .reference: return 7
        case .purchase:  return 8
        case .money:     return 9
        case .note:      return 10
        }
    }
}

enum TagStatus: String, Codable {
    case auto       // applied quietly, high confidence
    case suggested  // visible chip, not yet committed
}

struct EntryTag: Identifiable, Codable, Equatable {
    let id: UUID
    let type: TagType
    var status: TagStatus
    var confidence: Double
    var triggerText: String?  // phrase that triggered this tag, for "why" display

    init(
        id: UUID = UUID(),
        type: TagType,
        status: TagStatus,
        confidence: Double,
        triggerText: String? = nil
    ) {
        self.id = id
        self.type = type
        self.status = status
        self.confidence = confidence
        self.triggerText = triggerText
    }
}
