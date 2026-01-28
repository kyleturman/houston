import UIKit

// MARK: - Monitor Animation
/// ECG/heart monitor style animation with sharp spikes
class MonitorAnimation: AnimationRenderer {
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
        // Monitor can change spike frequency or amplitude based on state
        // For example: more frequent spikes when active
    }
    
    func updateColor(_ color: UIColor) {
        shapeLayer?.strokeColor = color.cgColor
    }
    
    func speed(for state: StatusAnimationState) -> CGFloat {
        switch state {
        case .idle: return 0.5
        case .active: return 1.5
        case .paused: return 0
        case .custom(let speed): return speed
        }
    }
    
    func render(in bounds: CGRect, phase: CGFloat) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        
        let path = createMonitorPath(width: bounds.width, height: bounds.height, phase: phase)
        shapeLayer?.path = path.cgPath
        shapeLayer?.frame = bounds
    }
    
    private func createMonitorPath(width: CGFloat, height: CGFloat, phase: CGFloat) -> UIBezierPath {
        let path = UIBezierPath()
        let midY = height / 2
        let amplitude = height * 0.3
        
        path.move(to: CGPoint(x: 0, y: midY))
        
        let cycles = 3
        let cycleWidth = width / CGFloat(cycles)
        
        for cycle in 0..<cycles {
            let cycleStart = CGFloat(cycle) * cycleWidth
            
            // Flat line before spike
            let flatLength = cycleWidth * 0.6
            path.addLine(to: CGPoint(x: cycleStart + flatLength, y: midY))
            
            // ECG spike pattern
            let spikeStart = cycleStart + flatLength
            let spikeWidth = cycleWidth * 0.4
            
            // Small dip
            path.addLine(to: CGPoint(x: spikeStart + spikeWidth * 0.2, y: midY + amplitude * 0.2))
            // Sharp spike up
            path.addLine(to: CGPoint(x: spikeStart + spikeWidth * 0.4, y: midY - amplitude))
            // Quick drop
            path.addLine(to: CGPoint(x: spikeStart + spikeWidth * 0.6, y: midY + amplitude * 0.3))
            // Recovery to baseline
            path.addLine(to: CGPoint(x: spikeStart + spikeWidth, y: midY))
        }
        
        path.addLine(to: CGPoint(x: width, y: midY))
        
        // Animate by translating the path
        let translation = -phase / (.pi * 2) * (width / CGFloat(cycles))
        let transform = CGAffineTransform(translationX: translation, y: 0)
        path.apply(transform)
        
        return path
    }
}
