import UIKit

// MARK: - Helix Animation
/// Double helix animation with two intertwined sine waves
class HelixAnimation: AnimationRenderer {
    private var shapeLayer1: CAShapeLayer?
    private var shapeLayer2: CAShapeLayer?
    private var currentState: StatusAnimationState = .active
    
    func setup(color: UIColor, state: StatusAnimationState, parentView: UIView) {
        self.currentState = state
        
        let layer1 = CAShapeLayer()
        layer1.strokeColor = color.cgColor
        layer1.fillColor = UIColor.clear.cgColor
        layer1.lineWidth = 1.0
        layer1.lineCap = .round
        layer1.lineJoin = .round
        
        let layer2 = CAShapeLayer()
        layer2.strokeColor = color.withAlphaComponent(0.6).cgColor
        layer2.fillColor = UIColor.clear.cgColor
        layer2.lineWidth = 1.0
        layer2.lineCap = .round
        layer2.lineJoin = .round
        
        parentView.layer.addSublayer(layer1)
        parentView.layer.addSublayer(layer2)
        self.shapeLayer1 = layer1
        self.shapeLayer2 = layer2
    }
    
    func updateState(_ state: StatusAnimationState) {
        self.currentState = state
        // Helix could change frequency or make strands move independently based on state
        // For example: strands could rotate around each other faster when active
    }
    
    func updateColor(_ color: UIColor) {
        shapeLayer1?.strokeColor = color.cgColor
        shapeLayer2?.strokeColor = color.withAlphaComponent(0.6).cgColor
    }
    
    func speed(for state: StatusAnimationState) -> CGFloat {
        switch state {
        case .idle: return 0.4
        case .active: return 1.2
        case .paused: return 0
        case .custom(let speed): return speed
        }
    }
    
    func render(in bounds: CGRect, phase: CGFloat) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        
        // First strand
        let path1 = createSineWave(
            width: bounds.width,
            height: bounds.height,
            phase: phase,
            offset: 0
        )
        
        // Second strand (180 degrees out of phase)
        let path2 = createSineWave(
            width: bounds.width,
            height: bounds.height,
            phase: phase,
            offset: .pi
        )
        
        shapeLayer1?.path = path1.cgPath
        shapeLayer1?.frame = bounds
        
        shapeLayer2?.path = path2.cgPath
        shapeLayer2?.frame = bounds
    }
    
    private func createSineWave(
        width: CGFloat,
        height: CGFloat,
        phase: CGFloat,
        offset: CGFloat
    ) -> UIBezierPath {
        let path = UIBezierPath()
        let midY = height / 2
        let amplitude = height * 0.3
        let frequency: CGFloat = 2.5
        
        let points = Int(width)
        for i in 0...points {
            let x = CGFloat(i)
            let relativeX = x / width
            let angle = relativeX * .pi * 2 * frequency - phase + offset
            let y = midY + sin(angle) * amplitude
            
            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        
        return path
    }
}
