import Foundation
import SpacePushClient

extension ActivePeriods {
    /// Kept as a JSON object in a file, since Android has no user defaults.
    static func file(path: String) -> ActivePeriods {
        let url = URL(fileURLWithPath: path)
        let reported = (try? JSONDecoder().decode(Labels.self, from: Data(contentsOf: url))) ?? [:]
        return ActivePeriods(reported: reported, save: { labels in
            try? JSONEncoder().encode(labels).write(to: url, options: .atomic)
        })
    }
}
