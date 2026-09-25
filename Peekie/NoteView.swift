import SwiftUI

struct NoteView: View {
    let model: NoteModel

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @AppStorage(PrefKey.backgroundOpacity) private var backgroundOpacity = PrefDefault.backgroundOpacity
    @AppStorage(PrefKey.blurRadius) private var blurRadius = PrefDefault.blurRadius
    @AppStorage(PrefKey.monospacedFont) private var monospaced = false
    @AppStorage(PrefKey.fontSize) private var fontSize = PrefDefault.fontSize

    private var tint: Color {
        colorScheme == .dark
            ? Color(red: 0.11, green: 0.12, blue: 0.15)
            : Color(red: 0.96, green: 0.96, blue: 0.97)
    }

    private var effectiveOpacity: Double {
        if reduceTransparency { return 1 }
        return contrast == .increased ? max(backgroundOpacity, 0.9) : backgroundOpacity
    }

    var body: some View {
        NoteTextEditor(model: model, fontSize: fontSize, monospaced: monospaced)
            .background {
                ZStack {
                    if !reduceTransparency {
                        VisualEffectView(radius: blurRadius)
                    }
                    tint.opacity(effectiveOpacity)
                }
                .ignoresSafeArea()
            }
    }
}
