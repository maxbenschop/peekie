import AppKit

struct SavedNote: Codable {
    var id: UUID

    var frame: [Double]
    var zoom: Double
    var pinned: Bool
    var modified: Date

    var imageWidths: [Double]?

    var rect: NSRect? {
        frame.count == 4 ? NSRect(x: frame[0], y: frame[1], width: frame[2], height: frame[3]) : nil
    }
}

@MainActor
final class NoteStore {
    static var shared = NoteStore()

    let directory: URL

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Peekie/Notes", isDirectory: true)
    }

    var isEnabled: Bool { UserDefaults.standard.bool(forKey: PrefKey.saveNotes) }

    private func noteURL(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString + ".note") }
    private func metaURL(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString + ".json") }

    static func isEmpty(_ note: NSAttributedString) -> Bool {
        let text = note.string
        return !text.contains("\u{FFFC}") && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func save(id: UUID, content: NSAttributedString, frame: NSRect, zoom: Double, pinned: Bool, imageWidths: [Double] = []) {
        guard !Self.isEmpty(content) else {
            delete(id: id)
            return
        }
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
            )

            let portable = NoteTextView.strippingDefaultColour(from: content)
            guard let data = portable.rtfd(from: NSRange(location: 0, length: portable.length), documentAttributes: [:]) else { return }
            try data.write(to: noteURL(id), options: .atomic)

            let meta = SavedNote(
                id: id, frame: [frame.minX, frame.minY, frame.width, frame.height],
                zoom: zoom, pinned: pinned, modified: Date(), imageWidths: imageWidths.isEmpty ? nil : imageWidths
            )
            try JSONEncoder().encode(meta).write(to: metaURL(id), options: .atomic)
        } catch {
            NSLog("Peekie: couldn't save note \(id): \(error)")
        }
    }

    func delete(id: UUID) {
        try? FileManager.default.removeItem(at: noteURL(id))
        try? FileManager.default.removeItem(at: metaURL(id))
    }

    func deleteAll() {
        try? FileManager.default.removeItem(at: directory)
    }

    func loadAll() -> [(meta: SavedNote, content: NSAttributedString)] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        var notes: [(SavedNote, NSAttributedString)] = []
        for file in files where file.pathExtension == "json" {
            guard let meta = (try? Data(contentsOf: file)).flatMap({ try? JSONDecoder().decode(SavedNote.self, from: $0) }),
                  let data = try? Data(contentsOf: noteURL(meta.id)),
                  let content = NSAttributedString(rtfd: data, documentAttributes: nil),
                  !Self.isEmpty(content) else { continue }
            notes.append((meta, content))
        }
        return notes.sorted { $0.0.modified < $1.0.modified }
    }
}
