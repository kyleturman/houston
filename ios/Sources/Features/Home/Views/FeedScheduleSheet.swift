import SwiftUI

struct FeedScheduleSheet: View {
    @Environment(SessionManager.self) var sessionManager
    @Environment(\.dismiss) var dismiss

    @State private var schedule: FeedSchedule?
    @State private var loading = false
    @State private var updating = false
    @State private var errorMessage: String?

    // Time picker state
    @State private var showingTimePicker = false
    @State private var selectedPeriod: String?
    @State private var selectedHour: Int = 6

    // Period metadata
    private let periods: [(id: String, name: String, icon: String)] = [
        ("morning", "Morning", "sun.horizon"),
        ("afternoon", "Afternoon", "sun.max"),
        ("evening", "Evening", "moon.stars")
    ]

    // Valid hour ranges per period
    private let hourRanges: [String: ClosedRange<Int>] = [
        "morning": 4...11,
        "afternoon": 12...16,
        "evening": 17...22
    ]

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if loading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = errorMessage {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 40))
                            .foregroundColor(Color.foreground["300"])
                        Text("Failed to load schedule")
                            .body()
                            .foregroundColor(Color.foreground["000"])
                        Text(error)
                            .caption()
                            .foregroundColor(Color.foreground["300"])
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let schedule = schedule {
                    scheduleContent(schedule)
                }
            }
            .navigationTitle("Feed Schedule")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            await loadSchedule()
        }
        .presentationBackground(.thinMaterial)
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showingTimePicker) {
            timePickerSheet
        }
    }

    @ViewBuilder
    private func scheduleContent(_ schedule: FeedSchedule) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("Customize when your feed updates with fresh insights, reflections, and discoveries from the around the web based on your goals.")
                        .body()
                        .foregroundColor(Color.foreground["300"])

                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                            .font(.system(size: 12))
                        Text(schedule.timezone)
                            .caption()
                    }
                    .foregroundColor(Color.foreground["400"])
                    .padding(.top, 4)
                }
                .padding(.horizontal, 20)

                // Period rows
                VStack(spacing: 12) {
                    ForEach(periods, id: \.id) { period in
                        if let config = schedule.periods[period.id] {
                            periodRow(period: period, config: config)
                        }
                    }
                }
                .padding(.horizontal, 20)

                Spacer(minLength: 20)
            }
        }
    }

    @ViewBuilder
    private func periodRow(period: (id: String, name: String, icon: String), config: FeedPeriodConfig) -> some View {
        HStack(spacing: 16) {
            // Icon
            ZStack {
                Circle()
                    .fill(Color.background["100"])
                    .frame(width: 48, height: 48)

                Image(systemName: period.icon)
                    .font(.system(size: 20))
                    .foregroundColor(config.enabled ? Color.foreground["000"] : Color.foreground["400"])
            }

            // Period name and time button
            VStack(alignment: .leading, spacing: 4) {
                Text(period.name)
                    .title()
                    .foregroundColor(config.enabled ? Color.foreground["000"] : Color.foreground["400"])

                // Time button
                Button {
                    selectedPeriod = period.id
                    selectedHour = parseHour(from: config.time)
                    showingTimePicker = true
                } label: {
                    HStack(spacing: 4) {
                        Text(formatTime(config.time))
                            .caption()
                            .foregroundColor(config.enabled ? Color.foreground["300"] : Color.foreground["500"])
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10))
                            .foregroundColor(Color.foreground["400"])
                    }
                }
                .disabled(!config.enabled || updating)
            }

            Spacer()

            // Toggle
            Toggle("", isOn: Binding(
                get: { config.enabled },
                set: { newValue in
                    Task {
                        await updatePeriod(period.id, enabled: newValue)
                    }
                }
            ))
            .labelsHidden()
            .disabled(updating)
        }
        .padding(16)
        .background(Color.background["100"])
        .cornerRadius(12)
        .opacity(updating ? 0.7 : 1)
    }

    @ViewBuilder
    private var timePickerSheet: some View {
        NavigationView {
            VStack(spacing: 24) {
                if let periodId = selectedPeriod,
                   let period = periods.first(where: { $0.id == periodId }),
                   let range = hourRanges[periodId] {

                    // Period header
                    VStack(spacing: 8) {
                        Image(systemName: period.icon)
                            .font(.system(size: 32))
                            .foregroundColor(Color.foreground["000"])
                        Text("\(period.name) Feed")
                            .titleLarge()
                            .foregroundColor(Color.foreground["000"])
                        Text("Select a time between \(formatHourShort(range.lowerBound)) and \(formatHourShort(range.upperBound))")
                            .caption()
                            .foregroundColor(Color.foreground["300"])
                    }
                    .padding(.top, 24)

                    // Hour picker
                    Picker("Hour", selection: $selectedHour) {
                        ForEach(Array(range), id: \.self) { hour in
                            Text(formatHourShort(hour))
                                .tag(hour)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 150)

                    Spacer()

                    // Save button
                    StandardButton(
                        title: "Save",
                        isLoading: updating,
                        isDisabled: false,
                        action: {
                            Task {
                                let time = String(format: "%02d:00", selectedHour)
                                await updatePeriod(periodId, time: time)
                                showingTimePicker = false
                            }
                        }
                    )
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
            }
            .background(Color.background["200"])
            .navigationTitle("Set Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showingTimePicker = false
                    } label: {
                        Text("Cancel")
                            .bodyLarge()
                            .foregroundColor(Color.foreground["000"])
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Helpers

    private func parseHour(from time: String) -> Int {
        let components = time.split(separator: ":")
        guard let hourStr = components.first else { return 6 }
        return Int(hourStr) ?? 6
    }

    private func formatTime(_ time: String) -> String {
        let hour = parseHour(from: time)
        return formatHourShort(hour)
    }

    private func formatHourShort(_ hour: Int) -> String {
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

    // MARK: - API

    private func loadSchedule() async {
        loading = true
        errorMessage = nil

        do {
            guard let apiClient = sessionManager.makeClient() else {
                errorMessage = "Not authenticated"
                loading = false
                return
            }

            let fetchedSchedule = try await apiClient.getFeedSchedule()
            schedule = fetchedSchedule

            // Schedule local notifications for feed times (fallback when APNs not configured)
            await FeedNotificationScheduler.shared.scheduleNotifications(for: fetchedSchedule)
        } catch {
            errorMessage = error.localizedDescription
        }

        loading = false
    }

    private func updatePeriod(_ period: String, time: String? = nil, enabled: Bool? = nil) async {
        updating = true

        do {
            guard let apiClient = sessionManager.makeClient() else {
                updating = false
                return
            }

            let updatedSchedule = try await apiClient.updateFeedSchedule(period: period, time: time, enabled: enabled)
            schedule = updatedSchedule

            // Reschedule local notifications with new times
            await FeedNotificationScheduler.shared.scheduleNotifications(for: updatedSchedule)
        } catch {
            // Reload to get current state
            await loadSchedule()
        }

        updating = false
    }
}

#Preview {
    FeedScheduleSheet()
        .environment(SessionManager())
}
