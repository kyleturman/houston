import SwiftUI

struct SettingsView: View {
    @Environment(SessionManager.self) var session
    @Environment(ThemeManager.self) var themeManager
    @Environment(NavigationViewModel.self) var navigationVM
    @Environment(\.colorScheme) var colorScheme
    
    let onCreateGoal: () -> Void
    
    @State private var showingIntegrations = false
    @State private var showingAccountMenu = false

    var body: some View {
        VStack {
            HStack {
                Image("logo-horizontal")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 160)

                Spacer()
            }

            StandardButton(
                title: "Start New Goal",
                icon: "plus.circle",
                variant: .glass,
                action: {
                    navigationVM.closeSideMenu()
                    onCreateGoal()
                }
            )
            .padding(.horizontal, -4)
            .padding(.top, 16)

            // Settings Menu Items
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SettingsMenuItem(
                        icon: "target",
                        title: "Goals",
                        action: { navigationVM.navigateToGoals() }
                    )

                    SettingsMenuItem(
                        icon: "note.text",
                        title: "Notes",
                        action: { navigationVM.navigateToNotes() }
                    )

                    SettingsMenuItem(
                        icon: "clock.arrow.circlepath",
                        title: "Activity",
                        action: { navigationVM.navigateToHistory() }
                    )

                    SettingsMenuItem(
                        icon: "wrench",
                        title: "Tools & integrations",
                        action: { showingIntegrations = true }
                    )
                }
                .padding(.vertical, 12)
            }

            Spacer()

            HStack(spacing: 4) {
                // User - Tappable to open account menu
                StandardButton(variant: .outline, action: {
                    showingAccountMenu = true
                }) {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(session.currentUserEmail ?? "Unknown user")
                                .body()
                                .foregroundColor(Color.foreground["300"])
                            if let serverName = session.currentServerName {
                                Text(serverName)
                                    .body()
                                    .foregroundColor(Color.foreground["500"])
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color.foreground["300"])
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, -4)
                }
                .padding(.leading, -4)

                Spacer()

                Menu {
                    Button(action: {
                        themeManager.followSystemAppearance = false
                        themeManager.currentTheme = "dark"
                    }) {
                        let isSelected = !themeManager.followSystemAppearance && themeManager.currentTheme == "dark"
                        Label {
                            Text("Dark")
                        } icon: {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "moon")
                        }
                    }
                    
                    Button(action: {
                        themeManager.followSystemAppearance = false
                        themeManager.currentTheme = "light"
                    }) {
                        let isSelected = !themeManager.followSystemAppearance && themeManager.currentTheme == "light"
                        Label {
                            Text("Light")
                        } icon: {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "sun.max")
                        }
                    }
                    
                    Button(action: {
                        themeManager.followSystemAppearance = true
                        themeManager.updateFromEnvironment(colorScheme)
                    }) {
                        let isSelected = themeManager.followSystemAppearance
                        Label {
                            Text("Match System")
                        } icon: {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "iphone.circle")
                        }
                    }
                } label: {
                    IconButton(iconName:themeManager.currentTheme == "light" ? "sun.max" : "moon", rounded: true)
                }    
            }
        }
        .sheet(isPresented: $showingIntegrations) {
            MCPIntegrationsView()
                .navigationTitle("Integrations")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            showingIntegrations = false
                        }
                    }
                }
        }
        .sheet(isPresented: $showingAccountMenu) {
            AccountMenuSheet()
                .environment(session)
                .environment(navigationVM)
        }
        .safeAreaPadding(.top, WindowHelper.safeAreaTop + 20)
        .safeAreaPadding(.bottom, nil)
        .padding(.leading, 20)
        .padding(.trailing, 24)
        .padding(.bottom, 24)
    }
}

// MARK: - Settings Menu Item Component
struct SettingsMenuItem: View {
    let icon: String
    let title: String
    let action: () -> Void
    let color: Color
    
    init(icon: String, title: String, action: @escaping () -> Void, color: Color = Color.foreground["000"]) {
        self.icon = icon
        self.title = title
        self.action = action
        self.color = color
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .light))
                    .foregroundColor(color)
                    .frame(width: 24, height: 24)
                
                Text(title)
                    .bodyLarge()
                    .foregroundColor(color)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
}
