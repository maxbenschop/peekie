import AppKit

@MainActor
enum UpdateChecker {
    static let releasesPage = URL(string: "https://github.com/maxbenschop/peekie/releases/latest")!
    private static let latestReleaseAPI = URL(string: "https://api.github.com/repos/maxbenschop/peekie/releases/latest")!

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        func parts(_ version: String) -> [Int] {
            let trimmed = version.hasPrefix("v") ? String(version.dropFirst()) : version
            let core = trimmed.split(separator: "-", maxSplits: 1).first.map(String.init) ?? trimmed
            return core.split(separator: ".").map { Int($0) ?? 0 }
        }
        let a = parts(candidate), b = parts(current)
        let count = max(a.count, b.count)
        for index in 0..<count {
            let x = index < a.count ? a[index] : 0
            let y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return false
    }

    static func check() {
        var request = URLRequest(url: latestReleaseAPI)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Peekie/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        Task { @MainActor in
            do {
                let (data, _) = try await URLSession.shared.data(for: request)
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                guard let tag = json?["tag_name"] as? String else {
                    throw URLError(.badServerResponse)
                }
                let page = (json?["html_url"] as? String).flatMap(URL.init) ?? releasesPage
                present(latest: tag, page: page)
            } catch {
                let alert = NSAlert()
                alert.messageText = "Couldn't check for updates"
                alert.informativeText = error.localizedDescription
                alert.addButton(withTitle: "Open Releases Page")
                alert.addButton(withTitle: "OK")
                if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(releasesPage) }
            }
        }
    }

    private static func present(latest tag: String, page: URL) {
        let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        let alert = NSAlert()
        if isNewer(latest, than: currentVersion) {
            alert.messageText = "Peekie \(latest) is available"
            alert.informativeText = "You have \(currentVersion). Download the new version from the releases page and replace the app in Applications."
            alert.addButton(withTitle: "Download")
            alert.addButton(withTitle: "Later")
            if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(page) }
        } else {
            alert.messageText = "You're up to date"
            alert.informativeText = "Peekie \(currentVersion) is the latest version."
            alert.runModal()
        }
    }
}
