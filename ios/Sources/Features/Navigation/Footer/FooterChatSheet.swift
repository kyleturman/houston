import SwiftUI
import UIKit


struct FooterChatSheet: View {
    @Environment(SessionManager.self) var session
    @Environment(NavigationViewModel.self) var navigationVM
    @Environment(KeyboardInsetManager.self) var keyboardInsetManager
    @Environment(StateManager.self) var stateManager
    @Binding var isPresented: Bool
    @Binding var footerMinY: CGFloat
    @State private var isAnimating: Bool = false
    @State private var contentHeight: CGFloat = 300
    @GestureState private var dragOffset: CGFloat = 0
    @State private var showingLearnings: Bool = false
    @State private var showingSessionHistory: Bool = false

    // Chat context
    let chatViewModel: ChatViewModel?
    let currentGoal: Goal?

    private let cornerRadius: CGFloat = 32
    private let dragHandleWidth: CGFloat = 44
    private let dragHandleHeight: CGFloat = 4
    private let headerHeight: CGFloat = 60
    private let trailingActions: some View = EmptyView()
    private let backgroundFill = Color.background["100"]
    private let overlayOpacity: Double = 0.35
    
    // Context-aware title
    private var title: String {
        if let goal = currentGoal {
            return goal.title
        }

        // Default user agent name
        return "Houston"
    }
    
    // Context-aware accent color
    private var accentColor: Color {
        Color.accent(currentGoal)
    }

    // Drag configuration
    private let dismissThreshold: CGFloat = 50 // Swipe distance to trigger dismiss (lowered for easier dismiss)
    private let dragStartThreshold: CGFloat = 5 // Minimum drag before interpolation starts (prevents jump)
    private let closedHeight: CGFloat = 200 // Height when sheet is closed
    private let elasticResistance: CGFloat = 0.25 // Resistance factor for upward drag (0-1, lower = more resistance)

    private var showChatSheet: Bool {
        isPresented || isAnimating
    }

    // Safe maximum height instead of .infinity
    private var maxSheetHeight: CGFloat {
        WindowHelper.height
    }

    // Maximum drag distance = actual visual height change for 1:1 ratio
    private var maxDragDistance: CGFloat {
        maxSheetHeight - closedHeight
    }

    // Drag progress (0 = fully open, 1 = fully closed, <0 = elastic expansion beyond open)
    private var dragProgress: CGFloat {
        guard showChatSheet else { return 1 }

        let progress = dragOffset / maxDragDistance

        // Clamp maximum (fully closed) but allow negative (elastic expansion)
        return min(1, progress)
    }

    // Easing curve functions
    private func easeLinear(_ t: CGFloat) -> CGFloat {
        return t
    }

    private func easeInQuad(_ t: CGFloat) -> CGFloat {
        return t * t
    }

    private func easeOutQuad(_ t: CGFloat) -> CGFloat {
        return t * (2 - t)
    }

    private func easeInOutQuad(_ t: CGFloat) -> CGFloat {
        return t < 0.5 ? 2 * t * t : -1 + (4 - 2 * t) * t
    }

    private func easeInCubic(_ t: CGFloat) -> CGFloat {
        return t * t * t * t
    }

    private func easeOutCubic(_ t: CGFloat) -> CGFloat {
        let p = t - 1
        return p * p * p + 1
    }

    // Helper function to interpolate between two values based on progress with optional easing
    private func interpolate(from: CGFloat, to: CGFloat, progress: CGFloat, easing: ((CGFloat) -> CGFloat)? = nil) -> CGFloat {
        let easedProgress = easing?(progress) ?? progress
        return from + (to - from) * easedProgress
    }

    // Computed animated values that respond to both state and drag
    private var currentMaxHeight: CGFloat {
        if showChatSheet {
            let maxHeight = interpolate(from: maxSheetHeight, to: closedHeight, progress: dragProgress)
            return maxHeight - WindowHelper.safeAreaTop
        }
        return closedHeight
    }

    private var currentScale: CGFloat {
        if showChatSheet {
            return interpolate(from: 1, to: 0.95, progress: dragProgress)
        }
        return 0.85
    }

    private var currentOpacity: CGFloat {
        if showChatSheet {
            // Use easeInCubic: stays at 1.0 longer, then fades quickly near the end
            return interpolate(from: 1, to: 0, progress: dragProgress, easing: easeInCubic)
        }
        return 0
    }
    
    private var currentContentOpacity: CGFloat {
        if showChatSheet {
            return interpolate(from: 1, to: 0, progress: dragProgress, easing: easeOutCubic)
        }
        return 0
    }

    private var currentOverlayOpacity: CGFloat {
        if showChatSheet {
            return interpolate(from: overlayOpacity, to: 0, progress: dragProgress)
        }
        return 0
    }

    private var isDragging: Bool {
        dragOffset > 0
    }

    // Calculate bottom inset based on footer position
    private var bottomInset: CGFloat {
        let screenHeight = WindowHelper.height
        // Distance from bottom of screen to footer top
        let footerFromBottom = screenHeight - footerMinY
        // Add some padding
        return max(0, footerFromBottom)
    }

    // Effective bottom inset - uses frozen value when a sheet is open to prevent content jumping
    private var effectiveBottomInset: CGFloat {
        keyboardInsetManager.isFrozen ? keyboardInsetManager.effectiveBottomInset : bottomInset
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Dimming background
            Color.black
                .opacity(currentOverlayOpacity)
                .transaction { transaction in
                    if !isDragging {
                        transaction.animation = .easeInOut(duration: 0.25)
                    }
                }
                .allowsHitTesting(false)

            // Container spacing for chat sheet
            VStack() {
                chatSheet
                    .compositingGroup() // Flatten compositing without full rasterization
                    .opacity(currentOpacity)
                    .frame(maxHeight: currentMaxHeight)
                    .scaleEffect(currentScale)
            }
            .padding(.top, WindowHelper.safeAreaTop)
            .allowsHitTesting(showChatSheet)
            // Single unified animation for all properties - prevents jitter from competing animations
            .animation(
                isDragging ? nil : (isPresented ? .spring(response: 0.35, dampingFraction: 0.85) : .easeOut(duration: 0.15)),
                value: isPresented
            )
        }
        .onChange(of: navigationVM.activeSheet) { oldSheet, newSheet in
            // Freeze bottom inset when a sheet opens to prevent content jumping
            if newSheet != nil && oldSheet == nil {
                keyboardInsetManager.freeze(value: bottomInset)
            } else if newSheet == nil && oldSheet != nil {
                // Don't unfreeze immediately - let keyboardDidShow handle it
                // This prevents content jumping while keyboard animates back
                // Fallback: unfreeze after delay if keyboard doesn't return (user wasn't typing)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
                    keyboardInsetManager.unfreeze()
                }
            }
        }
        .onChange(of: showingLearnings) { wasShowing, isShowing in
            if isShowing && !wasShowing {
                keyboardInsetManager.freeze(value: bottomInset)
            } else if !isShowing && wasShowing {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
                    keyboardInsetManager.unfreeze()
                }
            }
        }
        .onChange(of: showingSessionHistory) { wasShowing, isShowing in
            if isShowing && !wasShowing {
                keyboardInsetManager.freeze(value: bottomInset)
            } else if !isShowing && wasShowing {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
                    keyboardInsetManager.unfreeze()
                }
            }
        }
        .sheet(isPresented: $showingLearnings) {
            if let goal = currentGoal {
                LearningsView(goal: goal)
            } else {
                LearningsView(isUserAgent: true)
            }
        }
        .sheet(isPresented: $showingSessionHistory) {
            if let baseURL = session.serverURL {
                let client = APIClient(
                    baseURL: baseURL,
                    deviceTokenProvider: { session.deviceToken },
                    userTokenProvider: { session.userToken }
                )
                SessionHistoryView(
                    goalId: currentGoal?.id,
                    isUserAgent: currentGoal == nil,
                    client: client
                )
            }
        }
        .onReceive(stateManager.agentSessionResetPublisher) { event in
            // When a session is reset, refresh the chat messages
            let isRelevant: Bool
            if let goal = currentGoal {
                isRelevant = event.agentable_type == "Goal" && String(event.agentable_id) == goal.id
            } else {
                isRelevant = event.agentable_type == "UserAgent"
            }

            if isRelevant {
                Task {
                    await chatViewModel?.refreshMessages()
                }
            }
        }
    }

    private var chatSheet: some View {
        ZStack(alignment: .top) {
            chatSheetHeader
                .opacity(isPresented ? currentContentOpacity : 0)
                .zIndex(1000)

            // Use ChatView component for proper message rendering and scroll behavior
            // Only render when presented so ScrollView reconstructs fresh (resets scroll to bottom)
            Group {
                if let vm = chatViewModel, isPresented {
                    ChatView(
                        viewModel: vm,
                        topInset: headerHeight,
                        bottomInset: effectiveBottomInset,
                        contentPadding: EdgeInsets(top: 0, leading: 16, bottom: 12, trailing: 16)
                    )
                    .environment(navigationVM)
                    .opacity(currentContentOpacity)
                    .frame(maxHeight: .infinity)
                } else if isPresented {
                    // Empty state when no chat view model
                    VStack {
                        Spacer()
                        Text("No chat available")
                            .foregroundColor(Color.foreground["300"])
                            .opacity(currentContentOpacity)
                        Spacer()
                    }
                    .frame(maxHeight: .infinity)
                }
            }
            .mask(
                // Top fade out gradient
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .clear, location: 0.0375),
                        .init(color: .black, location: 0.125)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .cornerRadius(cornerRadius)
        .background(
            ZStack {
                // Background gradient
                UnevenRoundedRectangle(cornerRadii: .init(topLeading: cornerRadius, topTrailing: cornerRadius))
                    .fill(
                        LinearGradient(
                            colors: [Color.background["200"], Color.background["100"]],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .stroke(Color.foreground["000"].opacity(0.4), lineWidth: 0.5)
                
                // Accent gradient overlay
                UnevenRoundedRectangle(cornerRadii: .init(topLeading: cornerRadius, topTrailing: cornerRadius))
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: Color.accent(currentGoal), location: 0),
                                .init(color: Color.clear, location: 0.5)
                            ],
                            startPoint: .topTrailing,
                            endPoint: .bottomLeading
                        )
                    )
                    .opacity(0.075)
            }
        )
        .clipped()
    }

    private var chatSheetHeader: some View {
        VStack(spacing: 0) {
            // Drag handle
            RoundedRectangle(cornerRadius: 2.5)
                .fill(Color.foreground["300"])
                .frame(width: dragHandleWidth, height: dragHandleHeight)
                .opacity(0.6)
                .padding(.top, 10)
                .padding(.bottom, 9)

            // Title pill with menu
            HStack {
                Spacer()
                Menu {
                    Button {
                        // Delay to allow menu to dismiss before presenting sheet
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            showingLearnings = true
                        }
                    } label: {
                        Label("Learnings", systemImage: "lightbulb")
                    }

                    Button {
                        // Delay to allow menu to dismiss before presenting sheet
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            showingSessionHistory = true
                        }
                    } label: {
                        Label("Session History", systemImage: "clock.arrow.circlepath")
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(title)
                            .bodyLarge()
                            .foregroundColor(accentColor)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(Color.foreground["400"])
                    }
                    .padding(.vertical, 6)
                    .padding(.leading, 14)
                    .padding(.trailing, 10)
                    .glassBackground(cornerRadius: 14, strokeColor: accentColor.opacity(0.3))
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .updating($dragOffset) { value, state, transaction in
                    // Disable all animations during drag for smooth pixel-perfect tracking
                    transaction.animation = nil

                    if showChatSheet {
                        let translation = value.translation.height

                        if translation > 0 {
                            // Dragging down - normal behavior
                            state = translation
                        } else {
                            // Dragging up - apply elastic resistance
                            state = translation * elasticResistance
                        }
                    }
                }
                .onEnded { value in
                    // Check if this was a fast swipe using predictedEndTranslation
                    let predictedEnd = value.predictedEndTranslation.height
                    let shouldDismiss = predictedEnd > dismissThreshold

                    if shouldDismiss {
                        dismissSheet()
                    }
                    // If not a swipe, the sheet will bounce back automatically
                    // because dragOffset resets to 0 when gesture ends
                }
        )
    }

    private func dismissSheet() {
        isPresented = false
    }
}
