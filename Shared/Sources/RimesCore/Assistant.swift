import Foundation

/// One saved way of using the AI assistant: a name, an icon and the instruction the model
/// gets. Created and edited in the app only; the keyboard just runs it.
public struct AssistantPreset: Codable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    /// SF Symbol shown on the entrance bar.
    public var symbol: String
    public var instruction: String
    /// Hint shown in the empty Buffer; empty uses the keyboard's generic one.
    public var placeholder: String
    public init(id: UUID = UUID(), name: String = "", symbol: String = "sparkles", instruction: String = "", placeholder: String = "") {
        self.id = id; self.name = name; self.symbol = symbol; self.instruction = instruction; self.placeholder = placeholder
    }
    public var entryID: String { AssistantLibrary.presetPrefix + id.uuidString }
    public static let maxInstructionBytes = 4000
    public var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && instruction.utf8.count <= Self.maxInstructionBytes
    }
}

/// A ready-made preset the app offers to copy into the user's own list.
public struct AssistantStarter: Identifiable, Equatable {
    public var id: String
    public var nameZH: String, nameEN: String
    public var taglineZH: String, taglineEN: String
    public var symbol: String
    public var instructionZH: String, instructionEN: String
    public var placeholderZH: String, placeholderEN: String
    public func preset(chinese: Bool) -> AssistantPreset {
        .init(name: chinese ? nameZH : nameEN, symbol: symbol, instruction: chinese ? instructionZH : instructionEN,
              placeholder: chinese ? placeholderZH : placeholderEN)
    }
}

/// The user's presets and which entries sit on the keyboard's quick entrance bar.
/// Entrance entries are the built-in plugin ids (`apple.translation`, `ai.ask`, `ai.polish`,
/// `ai.poem`, `ai.art`) or `preset.<uuid>`.
public struct AssistantLibrary: Codable, Equatable {
    public static let presetPrefix = "preset."
    public static let builtInEntries = ["apple.translation", "ai.ask", "ai.polish", "ai.poem", "ai.art"]
    public static let maxPresets = 24
    public var presets: [AssistantPreset] = []
    /// nil keeps the default bar: every built-in plugin, in order.
    public var entrance: [String]?
    public init(presets: [AssistantPreset] = [], entrance: [String]? = nil) { self.presets = presets; self.entrance = entrance }

    public func preset(entry: String) -> AssistantPreset? {
        guard entry.hasPrefix(Self.presetPrefix), let id = UUID(uuidString: String(entry.dropFirst(Self.presetPrefix.count))) else { return nil }
        return presets.first { $0.id == id }
    }
    /// Entries that still exist, without repeats, in bar order.
    public var entranceEntries: [String] {
        var seen = Set<String>()
        return (entrance ?? Self.builtInEntries).filter { entry in
            (Self.builtInEntries.contains(entry) || preset(entry: entry) != nil) && seen.insert(entry).inserted
        }
    }
    /// Everything that could be on the bar.
    public var allEntries: [String] { Self.builtInEntries + presets.map(\.entryID) }

    public mutating func setOnEntrance(_ entry: String, _ on: Bool) {
        var list = entranceEntries
        list.removeAll { $0 == entry }
        if on { list.append(entry) }
        entrance = list
    }
    public mutating func moveEntrance(from: IndexSet, to: Int) {
        var list = entranceEntries
        // Same meaning as SwiftUI's move(fromOffsets:toOffset:), which Core cannot import.
        let moving = from.sorted().filter(list.indices.contains).map { list[$0] }
        let before = from.filter { $0 < to }.count
        for index in from.sorted().reversed() where list.indices.contains(index) { list.remove(at: index) }
        list.insert(contentsOf: moving, at: min(list.count, max(0, to - before)))
        entrance = list
    }
    /// Adds or replaces a preset. New presets are not placed on the bar until the user adds them.
    @discardableResult public mutating func save(_ preset: AssistantPreset) -> Bool {
        guard preset.isValid else { return false }
        var preset = preset
        preset.name = preset.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let index = presets.firstIndex(where: { $0.id == preset.id }) { presets[index] = preset }
        else { guard presets.count < Self.maxPresets else { return false }; presets.append(preset) }
        return true
    }
    public mutating func remove(_ id: UUID) {
        guard let preset = presets.first(where: { $0.id == id }) else { return }
        presets.removeAll { $0.id == id }
        if entrance != nil { entrance?.removeAll { $0 == preset.entryID } }
    }

    public static let starters: [AssistantStarter] = [
        .init(id: "sleep", nameZH: "哄睡", nameEN: "Lullaby", taglineZH: "用温柔的话把对方哄睡着", taglineEN: "Coax someone gently to sleep",
              symbol: "moon.stars",
              instructionZH: "把用户写的内容当作他想对对方说的意思或对方的情况，写一段哄对方入睡的话：语气温柔、放松、节奏慢，像在耳边轻声说；先接住情绪，再引导放松，最后道晚安。不超过 120 字，不用列表和 Markdown，只输出这段话。",
              instructionEN: "Treat the user's text as what they want to say or the other person's situation, and write a short message that coaxes that person to sleep: gentle, slow, soothing, like whispering beside them. Acknowledge feelings first, then guide relaxation, then say goodnight. Under 100 words, no lists or Markdown. Output only the message.",
              placeholderZH: "写下对方的情况，再点 ▶ 哄睡", placeholderEN: "Describe their situation, then tap ▶"),
        .init(id: "eq", nameZH: "高情商回复", nameEN: "Tactful reply", taglineZH: "把想说的话改成体面又暖心的回复", taglineEN: "Turn a blunt reply into a tactful one",
              symbol: "heart.text.square",
              instructionZH: "用户会给出对方说的话，或自己想回的意思。写一条高情商的回复：先认可对方的感受，再表达立场，语气真诚得体，不卑不亢，不说教。用与原文相同的语言，一到三句，只输出回复本身。",
              instructionEN: "The user gives what someone said, or what they want to reply. Write a tactful, emotionally intelligent reply: acknowledge the other person's feelings first, then state the position, sincere and composed, never preachy. Same language as the input, one to three sentences. Output only the reply.",
              placeholderZH: "写下对方的话或你想说的，再点 ▶", placeholderEN: "Write what they said or what you mean, then tap ▶"),
        .init(id: "gentle", nameZH: "更温柔", nameEN: "Softer", taglineZH: "保持原意，语气更柔和", taglineEN: "Same meaning, kinder tone",
              symbol: "heart",
              instructionZH: "保持原意和语言，把用户的文字改得更温柔、更体谅对方，不增加新的意思。只输出改写后的文字。",
              instructionEN: "Keep the meaning and language, but rewrite the user's text to be kinder and more considerate, without adding new points. Output only the rewrite.",
              placeholderZH: "写下要改温柔的话，再点 ▶", placeholderEN: "Write the text to soften, then tap ▶"),
        .init(id: "short", nameZH: "更简短", nameEN: "Shorter", taglineZH: "删去枝节，留下要点", taglineEN: "Cut it down to the point",
              symbol: "scissors",
              instructionZH: "保持原意和语言，把用户的文字压缩到最短，删去客套和重复，保留关键信息。只输出压缩后的文字。",
              instructionEN: "Keep the meaning and language, and compress the user's text as much as possible: drop filler and repetition, keep the key facts. Output only the shortened text.",
              placeholderZH: "写下要精简的话，再点 ▶", placeholderEN: "Write the text to shorten, then tap ▶"),
    ]
}
