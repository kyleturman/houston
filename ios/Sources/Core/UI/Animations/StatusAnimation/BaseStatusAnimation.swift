import SwiftUI
import UIKit

// MARK: - Animation Type
enum StatusAnimationType {
    case monitor  // Heart monitor/ECG style
    case wave     // Sine wave
    case helix    // Horizontal double helix
}

// MARK: - Animation State
enum StatusAnimationState {
    case idle
    case active
    case paused
    case custom(speed: CGFloat)
}

// MARK: - Animation Protocol
@MainActor
protocol AnimationRenderer {
    func setup(color: UIColor, state: StatusAnimationState, parentView: UIView)
    func updateState(_ state: StatusAnimationState)
    func updateColor(_ color: UIColor)
    func speed(for state: StatusAnimationState) -> CGFloat
    func render(in bounds: CGRect, phase: CGFloat)
}

// MARK: - SwiftUI View
struct StatusAnimation: View {
    let type: StatusAnimationType
    let height: CGFloat
    let color: Color?
    @Binding var state: StatusAnimationState
    
    init(
        type: StatusAnimationType,
        height: CGFloat = 40,
        color: Color? = nil,
        state: Binding<StatusAnimationState> = .constant(.active)
    ) {
        self.type = type
        self.height = height
        self.color = color
        self._state = state
    }
    
    var body: some View {
        let resolvedColor = color ?? (Color.foreground as Color.DynamicColorCategory)["000"]
        
        StatusAnimationViewRepresentable(
            type: type,
            color: UIColor(resolvedColor),
            state: state
        )
        .frame(height: height)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - UIViewRepresentable
struct StatusAnimationViewRepresentable: UIViewRepresentable {
    let type: StatusAnimationType
    let color: UIColor
    let state: StatusAnimationState
    
    func makeUIView(context: Context) -> AnimationContainerView {
        let view = AnimationContainerView()
        view.setup(type: type, color: color, state: state)
        return view
    }
    
    func updateUIView(_ uiView: AnimationContainerView, context: Context) {
        uiView.updateState(state)
        uiView.updateColor(color)
    }
}

// MARK: - Container View
class AnimationContainerView: UIView {
    private var renderer: AnimationRenderer?
    private var displayLink: CADisplayLink?
    private var phase: CGFloat = 0
    private var currentState: StatusAnimationState = .active
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func setup(type: StatusAnimationType, color: UIColor, state: StatusAnimationState) {
        self.currentState = state
        
        // Create appropriate renderer for animation type
        switch type {
        case .monitor:
            renderer = MonitorAnimation()
        case .wave:
            renderer = WaveAnimation()
        case .helix:
            renderer = HelixAnimation()
        }
        
        renderer?.setup(color: color, state: state, parentView: self)
        startAnimation()
    }
    
    func updateState(_ state: StatusAnimationState) {
        self.currentState = state
        renderer?.updateState(state)
    }
    
    func updateColor(_ color: UIColor) {
        renderer?.updateColor(color)
    }
    
    private func startAnimation() {
        displayLink?.invalidate()
        displayLink = CADisplayLink(target: self, selector: #selector(updateAnimation))
        displayLink?.add(to: .main, forMode: .common)
    }
    
    @objc private func updateAnimation() {
        let speed = renderer?.speed(for: currentState) ?? 1.0
        phase += speed * 0.05
        if phase > .pi * 2 {
            phase -= .pi * 2
        }
        
        renderer?.render(in: bounds, phase: phase)
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        renderer?.render(in: bounds, phase: phase)
    }
    
    deinit {
        MainActor.assumeIsolated {
            displayLink?.invalidate()
        }
    }
}

// MARK: - Preview
#Preview {
    let fg300 = (Color.foreground as Color.DynamicColorCategory)["300"]
    let bg000 = (Color.background as Color.DynamicColorCategory)["000"]
    let bg100 = (Color.background as Color.DynamicColorCategory)["100"]
    
    return VStack(spacing: 40) {
        VStack(spacing: 8) {
            Text("Monitor - Idle")
                .bodySmall()
                .foregroundColor(fg300)
            StatusAnimation(
                type: .monitor,
                height: 40,
                state: .constant(.idle)
            )
            .background(bg100)
        }
        
        VStack(spacing: 8) {
            Text("Monitor - Active")
                .bodySmall()
                .foregroundColor(fg300)
            StatusAnimation(
                type: .monitor,
                height: 40,
                color: .green,
                state: .constant(.active)
            )
            .background(bg100)
        }
        
        VStack(spacing: 8) {
            Text("Wave - Idle")
                .bodySmall()
                .foregroundColor(fg300)
            StatusAnimation(
                type: .wave,
                height: 40,
                state: .constant(.idle)
            )
            .background(bg100)
        }
        
        VStack(spacing: 8) {
            Text("Helix - Active")
                .bodySmall()
                .foregroundColor(fg300)
            StatusAnimation(
                type: .helix,
                height: 50,
                color: .blue,
                state: .constant(.active)
            )
            .background(bg100)
        }
    }
    .padding()
    .background(bg000)
}
