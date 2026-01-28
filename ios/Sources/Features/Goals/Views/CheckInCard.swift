import SwiftUI

/// A card displaying check-in information for a goal
struct CheckInCard: View {
    let style: Style
    let timeText: String
    let intent: String
    let accentColor: Color
    var scheduleText: String? = nil

    enum Style {
        /// Recurring scheduled check-in (shows repeat icon + schedule)
        case scheduled
        /// One-time follow-up check-in
        case followUp
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: style.iconName)
                    .foregroundColor(accentColor)
                    .font(.symbol(size: 14))
                
                // Title row
                switch style {
                case .scheduled:
                    HStack(spacing: 6) {
                        if let scheduleText = scheduleText {
                            Text(scheduleText)
                                .bodySmall()
                                .foregroundColor(Color.foreground["000"])
                        }
                        
                        Text(timeText)
                            .bodySmall()
                            .foregroundColor(Color.foreground["500"])
                    }
                    
                case .followUp:
                    Text(timeText)
                        .bodySmall()
                        .foregroundColor(Color.foreground["000"])
                }
                
                Spacer()
            }
            
            // Intent row
            Text(intent)
                .bodySmall()
                .foregroundColor(Color.foreground["500"])
                .lineLimit(2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.background["100"])
        .cornerRadius(14)
    }
}

// MARK: - Style Helpers

extension CheckInCard.Style {
    var iconName: String {
        switch self {
        case .scheduled: return "repeat"
        case .followUp: return "arrow.turn.down.right"
        }
    }
}

// MARK: - Convenience Initializers

extension CheckInCard {
    /// Creates a scheduled check-in card with time calculation
    static func scheduled(
        scheduledFor: Date,
        scheduleText: String?,
        intent: String,
        accentColor: Color
    ) -> CheckInCard {
        CheckInCard(
            style: .scheduled,
            timeText: Self.timeUntilText(for: scheduledFor),
            intent: intent,
            accentColor: accentColor,
            scheduleText: scheduleText
        )
    }

    /// Creates a follow-up check-in card with time calculation
    static func followUp(
        scheduledFor: Date,
        intent: String,
        accentColor: Color
    ) -> CheckInCard {
        CheckInCard(
            style: .followUp,
            timeText: Self.timeUntilText(for: scheduledFor, prefix: "Following up"),
            intent: intent,
            accentColor: accentColor
        )
    }

    private static func timeUntilText(for date: Date, prefix: String = "") -> String {
        let now = Date()
        let interval = date.timeIntervalSince(now)

        if interval < 0 {
            return "\(prefix)happening soon"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(prefix)in \(minutes)m"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(prefix)in \(hours)h"
        } else {
            let days = Int(interval / 86400)
            return "\(prefix)in \(days)d"
        }
    }
}

// MARK: - Previews

#Preview("Scheduled Check-In") {
    VStack(spacing: 16) {
        CheckInCard(
            style: .scheduled,
            timeText: "Checking in 2h",
            intent: "Review morning priorities and energy levels or something that goes to two lines",
            accentColor: .blue,
            scheduleText: "Daily at 9am"
        )

        CheckInCard(
            style: .scheduled,
            timeText: "Checking in 30m",
            intent: "Quick sync on project status",
            accentColor: .purple,
            scheduleText: "Weekdays at 2pm"
        )
    }
    .padding()
}

#Preview("Follow-Up Check-In") {
    VStack(spacing: 16) {
        CheckInCard(
            style: .followUp,
            timeText: "Following up in 1h",
            intent: "Check if the API integration is complete",
            accentColor: .green
        )

        CheckInCard(
            style: .followUp,
            timeText: "Following up soon",
            intent: "See how the meeting went",
            accentColor: .orange
        )
    }
    .padding()
}

#Preview("With Date Calculation") {
    VStack(spacing: 16) {
        CheckInCard.scheduled(
            scheduledFor: Date().addingTimeInterval(3600 * 2),
            scheduleText: "Daily at 5am",
            intent: "Morning reflection and planning",
            accentColor: .blue
        )

        CheckInCard.followUp(
            scheduledFor: Date().addingTimeInterval(1800),
            intent: "Check on task progress",
            accentColor: .green
        )
    }
    .padding()
}
