import AppKit

struct ClosedNote {
    let content: NSAttributedString
    let zoom: CGFloat
    let frame: NSRect
}

@MainActor
final class NoteModel {
    let id: UUID
    weak var textView: NoteTextView?

    var onChange: (() -> Void)?

    var initialContent: NSAttributedString?
    var initialZoom: CGFloat = 0
    var initialImageWidths: [Double]?

    init(id: UUID = UUID()) {
        self.id = id
    }

    func snapshot(frame: NSRect) -> ClosedNote? {
        guard let textView, let storage = textView.textStorage,
              !storage.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return ClosedNote(content: NSAttributedString(attributedString: storage), zoom: textView.zoomDelta, frame: frame)
    }
}
