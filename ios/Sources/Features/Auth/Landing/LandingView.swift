import SwiftUI
import CoreMotion

struct LandingView: View {
    @Environment(SessionManager.self) var session
    @Environment(NotificationManager.self) var notificationManager

    @State private var showInviteCodeSheet = false
    @StateObject private var motion = ParallaxMotionManager()

    // Onboarding state
    @State private var currentOnboardingPage = 0
    @State private var isCompletingOnboarding = false
    @State private var animationProgress: CGFloat = 0
    @Namespace private var buttonAnimation

    private let totalOnboardingPages = 5

    // Value prop descriptions for pages 1-4
    private let valueProps = [
        "Create goals around things you want to learn more about, get done, and work toward accomplishing",
        "Add notes to keep track of your progress and your goal will get smarter and add notes back",
        "Goals agents check-in regularly, research on the web, and use MCP integrations to help make progress",
        "The system learns, adapts, and updates a feed of helpful web content multiple times a day"
    ]

    /// Whether we're currently showing onboarding content
    private var isInOnboarding: Bool {
        session.phase == .onboarding
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background with zoom animation (no fade, always smooth)
                Image("space-background")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .scaleEffect(1.0 + (0.05 * animationProgress))
                    .animation(.easeInOut(duration: 0.35), value: animationProgress)

                // Planet - upper left (moves more for foreground feel)
                // Animation controlled by onChange - smooth exit, snappy return
                Image("space-planet")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 120)
                    .position(x: 80, y: 230)
                    .offset(
                        x: motion.x * 15 + (-200 * animationProgress),
                        y: motion.y * 15 + (-300 * animationProgress)
                    )
                    .opacity(1.0 - animationProgress)

                // Satellite - right side (moves less for depth)
                // Animation controlled by onChange - smooth exit, snappy return
                Image("space-satelite")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 400)
                    .position(x: geometry.size.width - 24, y: geometry.size.height * 0.45)
                    .offset(
                        x: motion.x * 40 + (200 * animationProgress),
                        y: motion.y * 40
                    )
                    .opacity(1.0 - animationProgress)

                // Main content
                if isInOnboarding {
                    onboardingContent(geometry: geometry)
                } else {
                    signInContent(geometry: geometry)
                }
            }
        }
        .ignoresSafeArea()
        .sheet(isPresented: $showInviteCodeSheet) {
            InviteCodeSheet()
        }
        .onChange(of: currentOnboardingPage) { oldPage, newPage in
            // Animate planet/satellite with direction-aware easing:
            // - Exiting (going to page 1+): Smooth ease-out, elements drift off naturally
            // - Returning (back to page 0): Snappy with bounce, elements pop back in
            if isInOnboarding {
                if newPage > 0 && animationProgress < 1.0 {
                    // Elements exiting - smooth accelerate out
                    withAnimation(.easeOut(duration: 0.4)) {
                        animationProgress = 1.0
                    }
                } else if newPage == 0 && animationProgress > 0.0 {
                    // Elements returning - snappy with bounce
                    withAnimation(.snappy(duration: 0.45, extraBounce: 0.15)) {
                        animationProgress = 0.0
                    }
                }
            }
        }
    }

    // MARK: - Sign In Content

    private func signInContent(geometry: GeometryProxy) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer()
                .frame(height: geometry.size.height * 0.4)

            // Logo
            Image("logo-globe")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 92)
                .padding(.leading, 28)

            // Tagline
            VStack(alignment: .leading, spacing: 4) {
                Text("Your pal on the ground,")
                    .body()
                    .foregroundStyle(.white.opacity(0.8))
                Text("waiting and ready to help")
                    .body()
                    .padding(.leading, 12)
                    .foregroundStyle(.white.opacity(0.8))
                Text("you reach your goals")
                    .body()
                    .padding(.leading, 4)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(.leading, 40)

            Spacer()

            // Sign-in card
            LandingSignInCard(showInviteCodeSheet: {
                showInviteCodeSheet = true
            })
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Onboarding Content

    private func onboardingContent(geometry: GeometryProxy) -> some View {
        ZStack {
            // Swipeable pages
            TabView(selection: $currentOnboardingPage) {
                // Page 0: Welcome page with logo, tagline, and server info
                welcomePageContent(geometry: geometry)
                    .tag(0)

                // Pages 1-4: Value prop pages (full screen)
                ForEach(1..<totalOnboardingPages, id: \.self) { index in
                    valuePropPageContent(index: index, geometry: geometry)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            // Fixed navigation overlay at bottom - stays in place during swipes
            VStack {
                Spacer()
                navigationControls
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
            }
        }
    }

    // MARK: - Welcome Page Content (Page 0)

    private func welcomePageContent(geometry: GeometryProxy) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer()
                .frame(height: geometry.size.height * 0.4)

            // Logo
            Image("logo-globe")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 92)
                .padding(.leading, 28)

            // Welcome tagline
            VStack(alignment: .leading, spacing: 4) {
                Text("Welcome, traveler!")
                    .body()
                    .padding(.leading, 4)
                    .foregroundStyle(.white.opacity(0.8))
                Text("Let's get you set up")
                    .body()
                    .foregroundStyle(.white.opacity(0.8))
                Text("and your goals on track")
                    .body()
                    .padding(.leading, 12)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(.leading, 40)

            Spacer()

            // Glass card with server info only
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.currentServerName ?? "Server")
                        .title()
                        .foregroundStyle(.white)

                    if let url = session.serverURL {
                        Text(url.absoluteString)
                            .body()
                            .foregroundStyle(.white.opacity(0.6))
                    }

                    if let email = session.currentUserEmail {
                        Text(email)
                            .body()
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }

                Spacer()

                // Sign out button
                Button {
                    session.signOutUser()
                } label: {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 18))
                        .foregroundStyle(ThemeManager.shared.accentColor(named: "coral") ?? .red)
                }
            }
            .padding(16)
            .glassBackground(cornerRadius: 16)
            .padding(.horizontal, 24)

            // Spacer for navigation controls area
            Spacer()
                .frame(height: 100)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Value Prop Page Content (Pages 1-4)

    private func valuePropPageContent(index: Int, geometry: GeometryProxy) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
                .frame(height: geometry.size.height * 0.12)

            // Show different illustrations based on page
            Group {
                switch index {
                case 2:
                    // Notes illustration for "Add notes..." page
                    OnboardingNotesIllustration(isVisible: currentOnboardingPage == index)
                case 3:
                    // Check-in illustration for "Goals agents check-in..." page
                    OnboardingCheckInIllustration(isVisible: currentOnboardingPage == index)
                case 4:
                    // Feed illustration for "The system learns..." page
                    OnboardingFeedIllustration(isVisible: currentOnboardingPage == index)
                default:
                    // Goal cards illustration for other pages
                    OnboardingGoalCardsIllustration(isVisible: currentOnboardingPage == index)
                }
            }
            .frame(height: geometry.size.height * 0.45)

            Spacer()

            // Value prop description
            Text(valueProps[index - 1])
                .titleLarge()
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)
                .lineSpacing(6)
                .padding(.horizontal, 36)
                .padding(.bottom, 20)

            // Spacer for navigation controls area
            Spacer()
                .frame(height: 100)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Navigation Controls (Fixed at bottom)

    private var isOnLastPage: Bool {
        currentOnboardingPage >= totalOnboardingPages - 1
    }

    private var navigationControls: some View {
        HStack {
            // Page indicators
            HStack(spacing: 8) {
                ForEach(0..<totalOnboardingPages, id: \.self) { index in
                    Circle()
                        .fill(index == currentOnboardingPage ? Color.white : Color.white.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }

            Spacer()

            // Navigation button - animates between arrow and Start
            Button {
                if isOnLastPage {
                    completeOnboarding()
                } else {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        currentOnboardingPage += 1
                    }
                }
            } label: {
                ZStack {
                    // Arrow icon - fades out on last page
                    Image(systemName: "arrow.right")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.black)
                        .opacity(isOnLastPage ? 0 : 1)

                    // Start text or loading - fades in on last page
                    Group {
                        if isCompletingOnboarding {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.black)
                        } else {
                            Text("Start")
                                .title()
                                .foregroundColor(.black)
                        }
                    }
                    .opacity(isOnLastPage ? 1 : 0)
                }
                .frame(width: isOnLastPage ? 100 : 56, height: 56)
                .background(
                    Capsule()
                        .fill(Color.white)
                        .matchedGeometryEffect(id: "navButton", in: buttonAnimation)
                )
                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
            }
            .disabled(isCompletingOnboarding)
            .animation(.snappy(duration: 0.3), value: isOnLastPage)
        }
        .padding(.leading, 12)
    }

    // MARK: - Actions

    private func completeOnboarding() {
        guard !isCompletingOnboarding else { return }
        isCompletingOnboarding = true

        Task { @MainActor in
            // Request notification permissions before completing onboarding
            do {
                let granted = try await notificationManager.requestAuthorization()
                print("[LandingView] Notification permission: \(granted ? "granted" : "denied")")
            } catch {
                print("[LandingView] Failed to request notifications: \(error)")
            }

            do {
                try await session.completeOnboarding()

                // Transition to main
                withAnimation(.easeInOut(duration: 0.5)) {
                    session.onboardingCompleted = true
                    session.phase = .main
                }
            } catch {
                print("[LandingView] Failed to complete onboarding: \(error)")
                // Still mark as completed locally even if API fails
                withAnimation(.easeInOut(duration: 0.5)) {
                    session.onboardingCompleted = true
                    session.phase = .main
                }
            }
            isCompletingOnboarding = false
        }
    }
}

// MARK: - Onboarding Feed Illustration

private struct OnboardingFeedIllustration: View {
    let isVisible: Bool
    @State private var elementStates: [Bool] = [false, false, false, false, false, false]

    private let pinkColor = Color(red: 1.0, green: 0.42, blue: 0.62)
    private let orangeColor = Color(red: 1.0, green: 0.55, blue: 0.42)
    private let mintColor = Color(red: 0.42, green: 1.0, blue: 0.77)

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Morning section
            timeSection(
                icon: "sun.horizon",
                label: "Morning",
                content: "4 Workout Routines for New Parents",
                color: pinkColor,
                labelIndex: 0,
                cardIndex: 1
            )

            // Afternoon section
            timeSection(
                icon: "sun.max",
                label: "Afternoon",
                content: "Tips for Budgeting for Home Renovations",
                color: orangeColor,
                labelIndex: 2,
                cardIndex: 3
            )

            // Evening section
            timeSection(
                icon: "moon",
                label: "Evening",
                content: "Discussion of budgeting strategies on Reddit",
                color: mintColor,
                labelIndex: 4,
                cardIndex: 5
            )
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: isVisible) { _, visible in
            if visible {
                animateElementsIn()
            } else {
                resetElements()
            }
        }
        .onAppear {
            if isVisible {
                animateElementsIn()
            }
        }
    }

    private func timeSection(icon: String, label: String, content: String, color: Color, labelIndex: Int, cardIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Time label with icon
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.8))
                Text(label)
                    .font(Font.custom(AppTitleFontFamily, size: 17).weight(.medium))
                    .foregroundColor(.white.opacity(0.9))
            }
            .opacity(elementStates[labelIndex] ? 1 : 0)
            .offset(y: elementStates[labelIndex] ? 0 : 15)

            // Content card
            Text(content)
                .font(Font.custom(AppFontFamily, size: 17))
                .foregroundColor(color)
                .lineSpacing(4)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(color, lineWidth: 1.5)
                )
                .opacity(elementStates[cardIndex] ? 1 : 0)
                .offset(y: elementStates[cardIndex] ? 0 : 15)
        }
    }

    private func animateElementsIn() {
        for index in elementStates.indices {
            withAnimation(
                .spring(response: 0.5, dampingFraction: 0.75)
                .delay(Double(index) * 0.1)
            ) {
                elementStates[index] = true
            }
        }
    }

    private func resetElements() {
        elementStates = [false, false, false, false, false, false]
    }
}

// MARK: - Onboarding Check-In Illustration

private struct OnboardingCheckInIllustration: View {
    let isVisible: Bool
    @State private var elementStates: [Bool] = [false, false, false, false]

    private let accentColor = Color(red: 0.42, green: 1.0, blue: 0.77) // Mint green

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Finance badge at top
            Text("Finance")
                .font(Font.custom(AppTitleFontFamily, size: 17).weight(.semibold))
                .foregroundColor(accentColor)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(accentColor, lineWidth: 2)
                )
                .opacity(elementStates[0] ? 1 : 0)
                .offset(y: elementStates[0] ? 0 : 20)

            // Schedule row
            HStack(spacing: 12) {
                Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                    .font(.system(size: 20))
                    .foregroundColor(.white.opacity(0.9))
                Text("Every day at 8am")
                    .font(Font.custom(AppFontFamily, size: 19))
                    .foregroundColor(.white.opacity(0.9))
            }
            .opacity(elementStates[1] ? 1 : 0)
            .offset(y: elementStates[1] ? 0 : 20)

            // MCP integration row
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 20))
                    .foregroundColor(.white.opacity(0.9))
                Text("Getting bank transactions")
                    .font(Font.custom(AppFontFamily, size: 19))
                    .foregroundColor(.white.opacity(0.9))
            }
            .opacity(elementStates[2] ? 1 : 0)
            .offset(y: elementStates[2] ? 0 : 20)

            // Agent report note
            HStack(alignment: .top, spacing: 16) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(accentColor)
                    .frame(width: 4)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Daily spending report")
                        .font(Font.custom(AppFontFamily, size: 19))
                        .foregroundColor(.white.opacity(0.9))
                    Text("Yesterday you spent $67 at the grocery store.")
                        .font(Font.custom(AppFontFamily, size: 19))
                        .foregroundColor(.white.opacity(0.9))
                    Text("You've spent $320 on groceries this month.")
                        .font(Font.custom(AppFontFamily, size: 19))
                        .foregroundColor(.white.opacity(0.9))

                    // Agent badge
                    Text("Agent")
                        .font(Font.custom(AppTitleFontFamily, size: 15).weight(.medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(.white, lineWidth: 1.5)
                        )
                        .padding(.top, 6)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .opacity(elementStates[3] ? 1 : 0)
            .offset(y: elementStates[3] ? 0 : 20)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: isVisible) { _, visible in
            if visible {
                animateElementsIn()
            } else {
                resetElements()
            }
        }
        .onAppear {
            if isVisible {
                animateElementsIn()
            }
        }
    }

    private func animateElementsIn() {
        for index in elementStates.indices {
            withAnimation(
                .spring(response: 0.5, dampingFraction: 0.75)
                .delay(Double(index) * 0.15)
            ) {
                elementStates[index] = true
            }
        }
    }

    private func resetElements() {
        elementStates = [false, false, false, false]
    }
}

// MARK: - Onboarding Notes Illustration

private struct OnboardingNotesIllustration: View {
    let isVisible: Bool
    @State private var elementStates: [Bool] = [false, false, false, false]

    private let accentColor = Color(red: 1.0, green: 0.55, blue: 0.42) // Coral/salmon

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            // Goal badge at top
            Text("Home Reno '26")
                .font(Font.custom(AppTitleFontFamily, size: 17).weight(.semibold))
                .foregroundColor(accentColor)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(accentColor, lineWidth: 2)
                )
                .opacity(elementStates[0] ? 1 : 0)
                .offset(y: elementStates[0] ? 0 : 20)

            // User note
            noteView(
                text: "We're thinking of doing tile in the bathroom for both the walls and floors",
                author: "You",
                authorColor: accentColor,
                lineColor: accentColor
            )
            .opacity(elementStates[1] ? 1 : 0)
            .offset(y: elementStates[1] ? 0 : 20)

            // Agent note
            noteView(
                text: "Based on your aesthetic and budget, here's some tile options I found",
                author: "Agent",
                authorColor: .white,
                lineColor: .white.opacity(0.6)
            )
            .opacity(elementStates[2] ? 1 : 0)
            .offset(y: elementStates[2] ? 0 : 20)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: isVisible) { _, visible in
            if visible {
                animateElementsIn()
            } else {
                resetElements()
            }
        }
        .onAppear {
            if isVisible {
                animateElementsIn()
            }
        }
    }

    private func noteView(text: String, author: String, authorColor: Color, lineColor: Color) -> some View {
        HStack(alignment: .top, spacing: 16) {
            // Vertical line
            RoundedRectangle(cornerRadius: 2)
                .fill(lineColor)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 14) {
                // Note text
                Text(text)
                    .font(Font.custom(AppFontFamily, size: 19))
                    .foregroundColor(.white.opacity(0.9))
                    .lineSpacing(6)
                    .fixedSize(horizontal: false, vertical: true)

                // Author badge
                Text(author)
                    .font(Font.custom(AppTitleFontFamily, size: 15).weight(.medium))
                    .foregroundColor(authorColor)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(authorColor, lineWidth: 1.5)
                    )
            }
        }
    }

    private func animateElementsIn() {
        for index in elementStates.indices {
            withAnimation(
                .spring(response: 0.5, dampingFraction: 0.75)
                .delay(Double(index) * 0.15)
            ) {
                elementStates[index] = true
            }
        }
    }

    private func resetElements() {
        elementStates = [false, false, false, false]
    }
}

// MARK: - Onboarding Goal Cards Illustration

private struct OnboardingGoalCardsIllustration: View {
    let isVisible: Bool
    @State private var cardStates: [Bool] = [false, false, false]

    private struct GoalCardData {
        let title: String
        let description: String
        let color: Color
        let rotation: Double
        let offset: CGPoint
    }

    private let cards: [GoalCardData] = [
        GoalCardData(
            title: "Exercise",
            description: "Get back into the gym regularly with a good workout routine",
            color: Color(red: 1.0, green: 0.42, blue: 0.62), // Pink
            rotation: -8,
            offset: CGPoint(x: -50, y: -110)
        ),
        GoalCardData(
            title: "Home Reno '26",
            description: "Plan, research, and keep track of upcoming renovation",
            color: Color(red: 1.0, green: 0.55, blue: 0.42), // Orange/salmon
            rotation: 6,
            offset: CGPoint(x: 50, y: 0)
        ),
        GoalCardData(
            title: "Finance",
            description: "Watch budget daily and help me manage my money well",
            color: Color(red: 0.42, green: 1.0, blue: 0.77), // Mint green
            rotation: -4,
            offset: CGPoint(x: -40, y: 120)
        )
    ]

    var body: some View {
        ZStack {
            ForEach(Array(cards.enumerated()), id: \.offset) { index, card in
                goalCardView(card: card, index: index)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: isVisible) { _, visible in
            if visible {
                animateCardsIn()
            } else {
                resetCards()
            }
        }
        .onAppear {
            if isVisible {
                animateCardsIn()
            }
        }
    }

    private func goalCardView(card: GoalCardData, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(card.title)
                .font(Font.custom(AppTitleFontFamily, size: 18).weight(.semibold))
                .foregroundColor(card.color)

            Text(card.description)
                .font(Font.custom(AppFontFamily, size: 13))
                .foregroundColor(card.color.opacity(0.85))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 190, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.black.opacity(0.4))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(card.color.opacity(0.8), lineWidth: 1.5)
        )
        .rotationEffect(.degrees(card.rotation))
        .offset(x: card.offset.x, y: card.offset.y)
        .opacity(cardStates[index] ? 1 : 0)
        .offset(y: cardStates[index] ? 0 : 40)
        .scaleEffect(cardStates[index] ? 1 : 0.9)
    }

    private func animateCardsIn() {
        for index in cards.indices {
            withAnimation(
                .spring(response: 0.5, dampingFraction: 0.75)
                .delay(Double(index) * 0.12)
            ) {
                cardStates[index] = true
            }
        }
    }

    private func resetCards() {
        cardStates = [false, false, false]
    }
}

// MARK: - Parallax Motion Manager

private class ParallaxMotionManager: ObservableObject {
    @Published var x: CGFloat = 0
    @Published var y: CGFloat = 0

    private var motionManager: CMMotionManager?

    init() {
        motionManager = CMMotionManager()
        motionManager?.deviceMotionUpdateInterval = 1 / 60

        guard let motionManager, motionManager.isDeviceMotionAvailable else { return }

        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let motion, let self else { return }

            withAnimation(.interpolatingSpring(stiffness: 50, damping: 10)) {
                // Use attitude (device orientation) for smooth parallax
                self.x = CGFloat(motion.attitude.roll)
                self.y = CGFloat(motion.attitude.pitch)
            }
        }
    }

    deinit {
        motionManager?.stopDeviceMotionUpdates()
    }
}
