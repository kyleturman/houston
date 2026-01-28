import UIKit

// MARK: - Wave Animation
/// Smooth sine wave animation
class WaveAnimation: AnimationRenderer {
    private var shapeLayer: CAShapeLayer?
    private var currentState: StatusAnimationState = .active
    
    func setup(color: UIColor, state: StatusAnimationState, parentView: UIView) {
        self.currentState = state
        
        let layer = CAShapeLayer()
        layer.strokeColor = color.cgColor
        layer.fillColor = UIColor.clear.cgColor
        layer.lineWidth = 1.0
        layer.lineCap = .round
        layer.lineJoin = .round
        
        parentView.layer.addSublayer(layer)
        self.shapeLayer = layer
    }
    
    func updateState(_ state: StatusAnimationState) {
        self.currentState = state
        // Wave animation changes speed based on state
        // Could also modify frequency or amplitude here
    }
    
    func updateColor(_ color: UIColor) {
        shapeLayer?.strokeColor = color.cgColor
    }
    
    func speed(for state: StatusAnimationState) -> CGFloat {
        switch state {
        case .idle: return 1.0
        case .active: return 2.0
        case .paused: return 0
        case .custom(let speed): return speed
        }
    }
    
    func render(in bounds: CGRect, phase: CGFloat) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        
        let path = createSineWave(
            width: bounds.width,
            height: bounds.height,
            phase: phase,
            frequency: 5.0
        )
        
        shapeLayer?.path = path.cgPath
        shapeLayer?.frame = bounds
    }
    
    private func createSineWave(
        width: CGFloat,
        height: CGFloat,
        phase: CGFloat,
        frequency: CGFloat
    ) -> UIBezierPath {
        let path = UIBezierPath()
        let midY = height / 2
        let maxAmplitude = height * 0.48  // Nearly full height with small padding

        let points = Int(width)
        for i in 0...points {
            let x = CGFloat(i)
            let relativeX = x / width
            
            // Sine wave
            let angle = relativeX * .pi * 2 * frequency - phase
            let wave = sin(angle)
            
            // Gaussian envelope (bell curve) - very wide spread so edges are nearly flat
            // Using a Gaussian function: exp(-((x-μ)²)/(2σ²))
            let center: CGFloat = 0.5  // Center of the wave (middle of screen)
            let spread: CGFloat = 0.25  // Narrower spread makes edges flatten more
            let distance = (relativeX - center) / spread
            let envelope = exp(-(distance * distance) / 2)
            
            // Apply envelope to amplitude
            let modulatedAmplitude = maxAmplitude * envelope
            let y = midY + wave * modulatedAmplitude
            
            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        
        return path
    }
}
