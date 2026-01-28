import SwiftUI

/// Timeline widget showing 24-hour day with goal activity and feed schedules
///
/// Displays:
/// - 22 interior vertical lines representing hours 1-22
/// - Goal rows with squares (notes) and diamonds (check-ins)
/// - Arc line with current time indicator
/// - Feed schedule dots (stroke for upcoming, filled+check for completed)
/// - Time labels only below feed schedule positions
struct DayTimelineWidget: View {
    let goals: [Goal]
    let feedItems: [FeedItem]?
    let feedSchedule: FeedSchedule?

    // Layout constants
    private let goalRowHeight: CGFloat = 8
    private let goalRowOverlap: CGFloat = -2
    private let arcHeight: CGFloat = 56
    private let topPadding: CGFloat = 48
    private let minHeight: CGFloat = 100
    var bottomPadding: CGFloat = 16

    // Animation constants
    private let baseAnimationDuration: Double = 1.2 // Duration if animating full width

    /// Current time as a percentage of the day (0.0 to 1.0)
    private var currentTimePercent: CGFloat {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: Date())
        let minute = calendar.component(.minute, from: Date())
        let fractionalHour = CGFloat(hour) + CGFloat(minute) / 60.0
        return fractionalHour / 24.0
    }

    /// Actual animation duration based on how far the arc needs to travel
    private var animationDuration: Double {
        Double(currentTimePercent) * baseAnimationDuration
    }

    // Animation state
    @State private var arcProgress: CGFloat = 0
    @State private var hasAnimated = false

    // Track if app was freshly launched (shared across instances)
    private static var hasAnimatedThisSession = false

    // Default feed schedule periods (hours in 24h format) - used when feedSchedule is nil
    private let defaultSchedulePeriods: [(period: String, hour: Int)] = [
        ("morning", 6),
        ("afternoon", 12),
        ("evening", 17)
    ]

    /// Schedule periods from feedSchedule (only enabled periods with their configured hours)
    private var schedulePeriods: [(period: String, hour: Int)] {
        guard let feedSchedule = feedSchedule else {
            return defaultSchedulePeriods
        }

        // Get only enabled periods with their configured hours
        return feedSchedule.enabledPeriods.compactMap { (period, config) in
            guard let hour = feedSchedule.hour(for: period) else { return nil }
            return (period: period, hour: hour)
        }
    }

    private var dateText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE. MMM d"
        return formatter.string(from: Date()).uppercased()
    }

    /// Dynamic height based on total number of goals (not just active ones)
    private var calculatedHeight: CGFloat {
        let goalCount = max(1, goals.count)
        let goalsHeight = goalRowHeight + CGFloat(goalCount - 1) * (goalRowHeight - goalRowOverlap)
        let totalHeight = topPadding + goalsHeight + 8 + arcHeight + 8
        return max(minHeight, totalHeight)
    }

    /// Spacing between goal rows (used for horizontal grid lines)
    private var goalRowSpacing: CGFloat {
        goalRowHeight - goalRowOverlap
    }

    private var goalsWithActivity: [Goal] {
        goals.filter { hasActivity(for: $0) }
    }

    /// Accent colors from all goals for rainbow border
    private var goalAccentColors: [Color] {
        let colors = goals.map { Color.accent($0) }
        // Need at least 2 colors for a gradient, duplicate if only 1
        if colors.count == 1 {
            return colors + colors
        }
        return colors.isEmpty ? [Color.foreground["300"], Color.foreground["500"]] : colors
    }

    /// Whether entrance animation should play
    private var shouldAnimate: Bool {
        !DayTimelineWidget.hasAnimatedThisSession
    }

    /// Calculate delay for an element based on its x-position percentage
    private func elementDelay(for xPercent: CGFloat) -> Double {
        // Elements past current time pop in sequentially after the arc animation finishes
        // Stagger them based on how far past current time they are
        if xPercent > currentTimePercent {
            let baseDelay = animationDuration + 0.1
            // How far past current time (0 = at current time, 1 = at end of day)
            let remainingDay = 1.0 - currentTimePercent
            let positionPastCurrent = (xPercent - currentTimePercent) / remainingDay
            // Stagger over 0.3s for elements past current time
            return baseDelay + Double(positionPastCurrent) * 0.3
        }

        // Element appears slightly before arc reaches its position
        // The delay is based on where the element is relative to the animation
        // xPercent/currentTimePercent gives us how far through the animation this element is
        let relativePosition = xPercent / currentTimePercent
        let anticipation: Double = animationDuration * 0.1
        let delay = Double(relativePosition) * animationDuration - anticipation
        return max(0, delay)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Main widget content
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    // Background grid lines
                    hourLines(in: geometry.size)
                    goalRowLines(in: geometry.size)

                    // Goal activity rows
                    goalRows(in: geometry.size)

                    // Arc section at bottom
                    arcSection(in: geometry.size)

                    // Date badge (top-left inside widget)
                    Text(dateText)
                        .caption()
                        .foregroundColor(Color.foreground["000"])
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.background["100"])
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.foreground["000"].opacity(0.5), lineWidth: 1)
                        )
                        .cornerRadius(4)
                        .padding(8)
                }
            }
            .frame(height: calculatedHeight)
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.background["100"],
                        Color.background["100"].opacity(0.25)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .cornerRadius(8)
            .rainbowBorder(
                colors: goalAccentColors.map { $0.opacity(0.5) },
                baseColor: Color.border["000"],
                lineWidth: 3,
                cornerRadius: 8,
                duration: 10
            )

            // Time labels below the container
            scheduleLabels
        }
        .onAppear {
            guard shouldAnimate else {
                arcProgress = 1
                return
            }

            // Start animation after a brief delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.linear(duration: animationDuration)) {
                    arcProgress = 1
                }
                DayTimelineWidget.hasAnimatedThisSession = true
            }
        }
    }

    // MARK: - Schedule Labels

    private var scheduleLabels: some View {
        GeometryReader { geometry in
            ForEach(schedulePeriods, id: \.period) { period, hour in
                Text(formatHour(hour))
                    .captionSmall()
                    .foregroundColor(Color.foreground["300"])
                    .position(
                        x: xPosition(for: hour, in: geometry.size.width),
                        y: 0
                    )
            }
        }
        .padding(.top, 12)
    }

    // MARK: - Hour Lines (Vertical)

    @ViewBuilder
    private func hourLines(in size: CGSize) -> some View {
        // 23 interior lines (hours 1-23), representing divisions between hours
        // Left edge = midnight (hour 0), Right edge = midnight (hour 24)
        ForEach(1..<24, id: \.self) { hour in
            Rectangle()
                .fill(Color.foreground["000"].opacity(0.2))
                .frame(width: 0.5)
                .position(
                    x: xPosition(for: hour, in: size.width),
                    y: size.height / 2
                )
        }
    }

    // MARK: - Goal Row Lines (Horizontal)

    @ViewBuilder
    private func goalRowLines(in size: CGSize) -> some View {
        // First goal row center is at: topPadding + goalRowHeight/2
        // We want grid lines starting from y=0 that align with goal rows
        // So we need to find the offset from 0 to the first goal row, then work backwards
        let firstGoalRowY = topPadding + goalRowHeight / 2

        // Calculate how many lines fit above the first goal row
        let linesAboveFirstGoal = Int(firstGoalRowY / goalRowSpacing)

        // Start position: work backwards from first goal row to get line at or near y=0
        let startY = firstGoalRowY - CGFloat(linesAboveFirstGoal) * goalRowSpacing

        // Calculate total number of lines needed to cover the full height
        let numberOfLines = Int((size.height - startY) / goalRowSpacing) + 1

        ZStack {
            ForEach(0..<numberOfLines, id: \.self) { index in
                let y = startY + CGFloat(index) * goalRowSpacing

                if y >= 0 && y <= size.height {
                    Rectangle()
                        .fill(Color.foreground["000"].opacity(0.2))
                        .frame(height: 0.5)
                        .position(x: size.width / 2, y: y)
                }
            }
        }
        .opacity(0.25)
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: 0.5),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    // MARK: - Goal Rows

    @ViewBuilder
    private func goalRows(in size: CGSize) -> some View {
        let activeGoals = goalsWithActivity
        let startY = topPadding + goalRowHeight / 2

        ForEach(Array(activeGoals.enumerated()), id: \.element.id) { index, goal in
            let y = startY + CGFloat(index) * goalRowSpacing

            // Notes for this goal (squares)
            ForEach(notesForGoal(goal), id: \.id) { noteData in
                if let createdAt = noteData.createdAt {
                    let xPos = xPosition(for: createdAt, in: size.width)
                    let xPercent = xPos / size.width

                    DelayedPopIn(delay: elementDelay(for: xPercent), shouldAnimate: shouldAnimate) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.accent(goal))
                            .frame(width: 8, height: 8)
                    }
                    .position(x: xPos, y: y)
                }
            }

            // Check-in for this goal (diamond outline)
            // Show if goal has a check-in scheduled for today based on its schedule
            if let checkInTime = todaysCheckInTime(for: goal) {
                let xPos = xPosition(for: checkInTime, in: size.width)
                let xPercent = xPos / size.width
                let isPast = checkInTime < Date()

                DelayedPopIn(delay: elementDelay(for: xPercent), shouldAnimate: shouldAnimate) {
                    RoundedRectangle(cornerRadius: 1)
                        .stroke(Color.accent(goal), lineWidth: 1.5)
                        .frame(width: 6, height: 6)
                        .rotationEffect(.degrees(45))
                        .opacity(isPast ? 0.5 : 1.0) // Dim past check-ins
                }
                .position(x: xPos, y: y)
            }
        }
    }

    // MARK: - Arc Section

    @ViewBuilder
    private func arcSection(in size: CGSize) -> some View {
        // Arc baseline near the bottom of the container (labels are outside now)
        let arcBaseY = size.height - bottomPadding
        let currentTimeX = xPosition(for: Date(), in: size.width)

        // Arc path - quadratic bezier curve
        // P0 = (0, arcBaseY), P1 = (width/2, arcBaseY - arcHeight), P2 = (width, arcBaseY)
        let arcPath = Path { path in
            path.move(to: CGPoint(x: 0, y: arcBaseY))
            path.addQuadCurve(
                to: CGPoint(x: size.width, y: arcBaseY),
                control: CGPoint(x: size.width / 2, y: arcBaseY - arcHeight)
            )
        }

        // Full dashed arc (visible from the start as background)
        AnimatedDashStroke(
            dash: [4, 4],
            color: Color.foreground["500"],
            lineWidth: 1,
            reverse: true
        ) {
            arcPath
        }

        // Solid arc animates in on top, up to current time
        arcPath
            .trim(from: 0, to: min(arcProgress, currentTimeX / size.width))
            .stroke(Color.foreground["500"], lineWidth: 1)

        // Current time indicator dot - positioned exactly on the arc
        let currentTimePercentValue = currentTimeX / size.width
        DelayedPopIn(delay: elementDelay(for: currentTimePercentValue), shouldAnimate: shouldAnimate) {
            PulsingDot()
                .frame(width: 6, height: 6)
        }
        .position(x: currentTimeX, y: yOnArc(t: currentTimePercentValue, arcBaseY: arcBaseY))

        // Feed schedule indicators
        ForEach(schedulePeriods, id: \.period) { period, hour in
            let x = xPosition(for: hour, in: size.width)
            let t = x / size.width
            let y = yOnArc(t: t, arcBaseY: arcBaseY)
            let isCompleted = isHourPassed(hour)

            DelayedPopIn(delay: elementDelay(for: t), shouldAnimate: shouldAnimate) {
                if isCompleted {
                    // Circle with checkmark
                    ZStack {
                        Circle()
                            .fill(Color.background["000"])
                            .stroke(Color.foreground["000"], lineWidth: 1)
                            .frame(width: 18, height: 18)
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(Color.foreground["000"])
                    }
                } else {
                    // Animated dashed circle for upcoming feed
                    AnimatedDashStroke(dash: [3, 3], color: Color.foreground["000"], lineWidth: 1) {
                        Circle()
                    }
                    .background(Circle().fill(Color.background["000"]))
                    .frame(width: 18, height: 18)
                }
            }
            .position(x: x, y: y)
        }
    }

    /// Calculate y-position on the quadratic bezier arc
    /// For a quadratic bezier: y(t) = (1-t)²·P0y + 2(1-t)t·P1y + t²·P2y
    /// With P0y = P2y = arcBaseY and P1y = arcBaseY - arcHeight:
    /// y(t) = arcBaseY - 2t(1-t)·arcHeight
    private func yOnArc(t: CGFloat, arcBaseY: CGFloat) -> CGFloat {
        return arcBaseY - 2 * t * (1 - t) * arcHeight
    }

    // MARK: - Position Calculations

    private func xPosition(for hour: Int, in width: CGFloat) -> CGFloat {
        // Hour 0 = left edge (0%), Hour 24 = right edge (100%)
        // This gives us 24 equal segments for each hour of the day
        return (CGFloat(hour) / 24.0) * width
    }

    private func xPosition(for date: Date, in width: CGFloat) -> CGFloat {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let fractionalHour = CGFloat(hour) + CGFloat(minute) / 60.0
        return (fractionalHour / 24.0) * width
    }

    // MARK: - Helpers

    private func hasActivity(for goal: Goal) -> Bool {
        let hasNotes = notesForGoal(goal).count > 0
        let hasCheckIn = todaysCheckInTime(for: goal) != nil
        return hasNotes || hasCheckIn
    }

    /// Get today's check-in time for a goal based on its schedule configuration
    /// Returns the scheduled time if the goal has a check-in today, nil otherwise
    private func todaysCheckInTime(for goal: Goal) -> Date? {
        guard let schedule = goal.checkInSchedule,
              let frequency = schedule.frequency,
              frequency != "none",
              let timeStr = schedule.time else { return nil }

        let calendar = Calendar.current
        let today = Date()
        let weekday = calendar.component(.weekday, from: today)
        // weekday: 1 = Sunday, 2 = Monday, ..., 7 = Saturday
        let isWeekday = weekday >= 2 && weekday <= 6

        let weekdayNames = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
        let todayName = weekdayNames[weekday - 1]

        // Check if check-in is scheduled for today
        let hasCheckInToday: Bool
        switch frequency {
        case "daily":
            hasCheckInToday = true
        case "weekdays":
            hasCheckInToday = isWeekday
        case "weekly":
            hasCheckInToday = schedule.dayOfWeek?.lowercased() == todayName
        default:
            hasCheckInToday = false
        }

        guard hasCheckInToday else { return nil }

        // Parse time string (e.g., "09:00") and create today's date with that time
        let parts = timeStr.split(separator: ":")
        guard parts.count >= 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]) else { return nil }

        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: today)
    }

    private func notesForGoal(_ goal: Goal) -> [NoteData] {
        guard let items = feedItems else { return [] }
        return items.compactMap { item in
            if case .note(let noteData) = item.data,
               noteData.goalId == goal.id {
                return noteData
            }
            return nil
        }
    }

    private func isToday(_ date: Date) -> Bool {
        Calendar.current.isDateInToday(date)
    }

    private func isHourPassed(_ hour: Int) -> Bool {
        let currentHour = Calendar.current.component(.hour, from: Date())
        return currentHour >= hour
    }

    private func formatHour(_ hour: Int) -> String {
        if hour == 0 {
            return "12am"
        } else if hour < 12 {
            return "\(hour)am"
        } else if hour == 12 {
            return "12pm"
        } else {
            return "\(hour - 12)pm"
        }
    }
}

// MARK: - Animated Dash Stroke

/// A reusable view that applies an animated "marching ants" dashed stroke to any shape
private struct AnimatedDashStroke<S: Shape>: View {
    let dash: [CGFloat]
    let color: Color
    let lineWidth: CGFloat
    let reverse: Bool
    let shape: S
    
    @State private var dashPhase: CGFloat = 0
    
    init(dash: [CGFloat], color: Color, lineWidth: CGFloat = 1, reverse: Bool = false, @ViewBuilder shape: () -> S) {
        self.dash = dash
        self.color = color
        self.lineWidth = lineWidth
        self.reverse = reverse
        self.shape = shape()
    }
    
    var body: some View {
        shape
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, dash: dash, dashPhase: dashPhase))
            .onAppear {
                let total = dash.reduce(0, +)
                withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                    dashPhase = reverse ? -total : total
                }
            }
    }
}

// MARK: - Pulsing Dot

/// A circle that pulses between two colors
private struct PulsingDot: View {
    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(isPulsing ? Color.foreground["500"] : Color.foreground["000"])
            .animation(.easeInOut(duration: 0.95).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear {
                isPulsing = true
            }
    }
}

// MARK: - Delayed Pop-In Animation

/// Wrapper that animates content with a delayed pop-in effect
private struct DelayedPopIn<Content: View>: View {
    let delay: Double
    let shouldAnimate: Bool
    let content: Content

    @State private var isVisible = false

    init(delay: Double, shouldAnimate: Bool, @ViewBuilder content: () -> Content) {
        self.delay = delay
        self.shouldAnimate = shouldAnimate
        self.content = content()
    }

    var body: some View {
        content
            .scaleEffect(isVisible ? 1 : 0)
            .opacity(isVisible ? 1 : 0)
            .onAppear {
                if shouldAnimate {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay + 0.1) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.45, blendDuration: 0.1)) {
                            isVisible = true
                        }
                    }
                } else {
                    isVisible = true
                }
            }
    }
}

#Preview {
    VStack(spacing: 20) {
        DayTimelineWidget(
            goals: [
                Goal(id: "1", title: "Learn Swift", status: .working, accentColor: "#FF6B6B"),
                Goal(id: "2", title: "Exercise", status: .working, accentColor: "#4ECDC4")
            ],
            feedItems: nil,
            feedSchedule: nil
        )
        .padding(.horizontal, 20)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.background["000"])
}
