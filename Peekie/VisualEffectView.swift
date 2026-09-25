import SwiftUI

final class BlurView: NSVisualEffectView {
    static let maxRadius: CGFloat = 40

    var radius: CGFloat = 12 {
        didSet { if radius != oldValue { applyBlur() } }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        reapplyAfterSystemUpdates()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        reapplyAfterSystemUpdates()
    }

    private func reapplyAfterSystemUpdates() {
        applyBlur()
        for delay in [0.05, 0.2, 0.5] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.applyBlur() }
        }
    }

    override func layout() {
        super.layout()
        applyBlur()
    }

    private func backdropLayer(in layer: CALayer) -> CALayer? {
        if String(describing: type(of: layer)) == "CABackdropLayer" { return layer }
        for sub in layer.sublayers ?? [] {
            if let found = backdropLayer(in: sub) { return found }
        }
        return nil
    }

    private static func makeFilter(_ type: String) -> NSObject? {
        guard let filterClass = NSClassFromString("CAFilter") as? NSObject.Type,
              let filter = filterClass.perform(NSSelectorFromString("filterWithType:"), with: type)?
                  .takeUnretainedValue() as? NSObject else { return nil }
        return filter
    }

    private static func filterKind(_ filter: Any) -> String? {
        (filter as? NSObject)?.value(forKey: "type") as? String
    }

    func applyBlur() {
        guard let root = layer, let backdrop = backdropLayer(in: root) else {
            alphaValue = min(max(radius / 30, 0), 1)
            return
        }
        let current = (backdrop.filters ?? []).compactMap { $0 as? NSObject }
        let blur = current.first { Self.filterKind($0) == "gaussianBlur" }
        let hasSaturation = current.contains { Self.filterKind($0) == "colorSaturate" }

        let currentRadius = (blur?.value(forKey: "inputRadius") as? NSNumber)?.doubleValue
        if currentRadius != Double(radius) || hasSaturation {
            guard let newBlur = Self.makeFilter("gaussianBlur") else {
                alphaValue = min(max(radius / 30, 0), 1)
                return
            }
            newBlur.setValue(radius, forKey: "inputRadius")
            newBlur.setValue(true, forKey: "inputNormalizeEdges")

            let kept = current.filter {
                let kind = Self.filterKind($0)
                return kind != "gaussianBlur" && kind != "colorSaturate"
            }
            backdrop.filters = kept + [newBlur]
        }
        alphaValue = 1

        for sibling in backdrop.superlayer?.sublayers ?? [] where sibling !== backdrop && sibling.opacity != 0 {
            sibling.opacity = 0
        }
    }
}

struct VisualEffectView: NSViewRepresentable {
    var radius: Double

    func makeNSView(context: Context) -> BlurView {
        let view = BlurView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        view.radius = radius
        return view
    }

    func updateNSView(_ view: BlurView, context: Context) {
        view.radius = radius
    }
}
