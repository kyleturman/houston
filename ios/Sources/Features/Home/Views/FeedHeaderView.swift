import SwiftUI
import SwiftUINavigationTransitions

struct FeedHeaderView: View {
    @Environment(SessionManager.self) var sessionManager
    @Environment(NavigationViewModel.self) var navigationVM

    let userName: String?
    let goalCount: Int
    let hasActiveAgents: Bool
    let goals: [Goal]
    let feedItems: [FeedItem]?
    @Binding var feedSchedule: FeedSchedule?
    let noteTransition: Namespace.ID

    @State private var showingSchedule = false
    @AppStorage("feedOnboardingNoticeDismissed") private var noticeDismissed = false

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<12:
            return "Good morning"
        case 12..<17:
            return "Good afternoon"
        default:
            return "Good evening"
        }
    }

    private var greetingIcon: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<12:
            return "sun.horizon"
        case 12..<17:
            return "sun.max"
        default:
            return "moon.stars"
        }
    }

    private var todaysNoteCount: Int {
        feedItems?.filter { item in
            if case .note = item.data { return true }
            return false
        }.count ?? 0
    }

    /// Count of check-ins scheduled for today (both past and future)
    /// Uses the check-in schedule configuration to determine if a goal
    /// has a check-in for today, regardless of whether it has passed.
    private var todaysCheckInCount: Int {
        let calendar = Calendar.current
        let today = Date()
        let weekday = calendar.component(.weekday, from: today)
        // weekday: 1 = Sunday, 2 = Monday, ..., 7 = Saturday
        let isWeekday = weekday >= 2 && weekday <= 6

        let weekdayNames = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
        let todayName = weekdayNames[weekday - 1]

        return goals.filter { goal in
            guard let schedule = goal.checkInSchedule,
                  let frequency = schedule.frequency,
                  frequency != "none" else { return false }

            switch frequency {
            case "daily":
                return true
            case "weekdays":
                return isWeekday
            case "weekly":
                return schedule.dayOfWeek?.lowercased() == todayName
            default:
                return false
            }
        }.count
    }

    /// Whether to show the feed onboarding notice
    /// Shows when there are goals but no feed generations yet (reflections/discoveries)
    /// Waits for schedule AND feed items to load to avoid flash during loading
    private var shouldShowFeedNotice: Bool {
        // Don't show until we have both schedule and feed items loaded
        // feedItems being nil means still loading - wait for it
        guard !noticeDismissed && goalCount > 0 && feedSchedule != nil && feedItems != nil else { return false }

        // Check if there are any generated feed items (reflections or discoveries)
        // Notes don't count since those are created by agents throughout the day
        let hasGeneratedContent = feedItems?.contains { item in
            switch item.data {
            case .reflection, .discovery:
                return true
            case .note:
                return false
            }
        } ?? false

        return !hasGeneratedContent
    }

    /// Formatted schedule times string (e.g., "6am, 12pm, 6pm")
    private var scheduleTimesText: String {
        guard let schedule = feedSchedule else { return "loading..." }
        let times = schedule.enabledPeriods.compactMap { period, config -> String? in
            guard let hour = schedule.hour(for: period) else { return nil }
            let suffix = hour >= 12 ? "pm" : "am"
            let displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
            return "\(displayHour)\(suffix)"
        }
        return times.isEmpty ? "not configured" : times.joined(separator: ", ")
    }

    var body: some View {
        VStack(spacing: 16) {
            // Greeting row
            HStack(spacing: 12) {
                Image(systemName: greetingIcon)
                    .font(.system(size: 20))
                    .foregroundColor(Color.foreground["000"])

                if let name = userName, !name.isEmpty {
                    Text("\(greeting), \(name)")
                        .headline()
                        .foregroundColor(Color.foreground["000"])
                } else {
                    Text(greeting)
                        .headline()
                        .foregroundColor(Color.foreground["000"])
                }

                Spacer()
            }

            // Day timeline widget
            Button {
                showingSchedule = true
            } label: {
                DayTimelineWidget(
                    goals: goals,
                    feedItems: feedItems,
                    feedSchedule: feedSchedule
                )
            }
            .buttonStyle(.plain)

            // Feed onboarding notice (dismissable)
            if shouldShowFeedNotice {
                Button {
                    showingSchedule = true
                    withAnimation(.easeOut(duration: 0.25)) {
                        noticeDismissed = true
                    }
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        (Text("Houston will populate your feed based on your goals and notes, currently set to generate at \(scheduleTimesText). ")
                            .foregroundColor(Color.foreground["200"])
                        +
                        Text("Tap to edit schedule.")
                            .foregroundColor(Color.semantic["primary"]))
                        .font(.bodySmall)

                        Spacer(minLength: 8)

                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color.foreground["300"])
                            .onTapGesture {
                                withAnimation(.easeOut(duration: 0.25)) {
                                    noticeDismissed = true
                                }
                            }
                    }
                    .padding(12)
                    .background(Color.background["100"])
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
                .transition(.asymmetric(
                    insertion: .opacity,
                    removal: .opacity.combined(with: .scale(scale: 0.95, anchor: .top))
                        .combined(with: .move(edge: .top))
                ))
            }

            // Goal and note counts
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(goalCount)")
                        .stat()
                        .foregroundColor(Color.foreground["200"])
                    Text(goalCount == 1 ? "Goal" : "Goals")
                        .captionSmall()
                        .foregroundColor(Color.foreground["500"])
                }
                .fixedSize(horizontal: true, vertical: false)

                VStack(alignment: .leading, spacing: 0) {
                    Text("\(todaysNoteCount)")
                        .stat()
                        .foregroundColor(Color.foreground["200"])
                    Text(todaysNoteCount == 1 ? "Note" : "Notes")
                        .captionSmall()
                        .foregroundColor(Color.foreground["500"])
                }
                .fixedSize(horizontal: true, vertical: false)

                VStack(alignment: .leading, spacing: 0) {
                    Text("\(todaysCheckInCount)")
                        .stat()
                        .foregroundColor(Color.foreground["200"])
                    Text(todaysCheckInCount == 1 ? "Check-in" : "Check-ins")
                        .captionSmall()
                        .foregroundColor(Color.foreground["500"])
                }
                .fixedSize(horizontal: true, vertical: false)


                StandardButton(variant: .outline, action: {
                    navigationVM.openNoteCompose(goal: nil, sourceID: "noteComposeHeader")
                }) {
                    HStack {
                        Image(systemName: "plus")
                            .font(.system(size: 12))
                        Text("Add Note")
                            .caption()
                    }
                    .padding(.leading, 2)
                }
                .padding(.leading, 20)
                .padding(.top, 2)
                .padding(.bottom, 0.5)
                .padding(.trailing, 0.5)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(Color.background["000"])
        .sheet(isPresented: $showingSchedule, onDismiss: {
            // Schedule will be reloaded by parent on dismiss
            Task {
                await reloadSchedule()
            }
        }) {
            FeedScheduleSheet()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    private func reloadSchedule() async {
        guard let client = sessionManager.makeClient() else { return }
        do {
            feedSchedule = try await client.getFeedSchedule()
        } catch {
            print("Failed to reload feed schedule: \(error)")
        }
    }
}

#Preview {
    @Previewable @Namespace var noteTransition
    @Previewable @State var previewSchedule: FeedSchedule? = nil

    VStack(spacing: 0) {
        FeedHeaderView(
            userName: "Kyle",
            goalCount: 2,
            hasActiveAgents: true,
            goals: [
                Goal(id: "1", title: "Learn Swift", status: .working, accentColor: "#FF6B6B"),
                Goal(id: "2", title: "Exercise", status: .working, accentColor: "#4ECDC4")
            ],
            feedItems: nil,
            feedSchedule: $previewSchedule,
            noteTransition: noteTransition
        )
    }
    .background(Color.background["000"])
    .environment(SessionManager())
    .environment(NavigationViewModel(goalsViewModel: GoalsViewModel(session: SessionManager())))
}
