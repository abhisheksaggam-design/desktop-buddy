import AppKit

let defaultSound = "Glass"
let noSound = "None"

/// The alert sounds that come with macOS (/System/Library/Sounds).
enum Sounds {
    static let all = ["Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero",
                      "Morse", "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink"]

    /// Most urgent first: when several things arrive together, the most urgent one's sound plays.
    static let priority: [ItemSource] = [.meeting, .chat, .mail, .task, .reminder]

    /// The type whose sound a batch of new items plays.
    static func leadSource(of items: [BuddyItem]) -> ItemSource? {
        let present = Set(items.map(\.source))
        return priority.first(where: present.contains)
    }

    static func play(_ name: String) {
        guard name != noSound else { return }
        let sound = NSSound(named: name) ?? NSSound(named: defaultSound)
        sound?.stop()
        sound?.play()
    }
}
