import SwiftUI
import RimesCore

/// The AI assistant: the user's own presets, a small gallery of starters to copy, and the
/// quick entrance bar the keyboard shows. Presets are made and edited here only.
struct AssistantView: View {
    @EnvironmentObject private var model: SettingsModel
    @State private var editing: AssistantPreset?
    private var library: AssistantLibrary { model.value.assistantLibrary }
    private var chinese: Bool { L("中", "en") == "中" }
    private var unusedStarters: [AssistantStarter] {
        AssistantLibrary.starters.filter { starter in
            !library.presets.contains { $0.name == starter.nameZH || $0.name == starter.nameEN }
        }
    }
    private func update(_ change: (inout AssistantLibrary) -> Void) {
        var next = model.value.assistantLibrary; change(&next)
        model.value.assistantLibrary = next; model.save()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(L("每个助手是一条自己的指令，例如“哄睡”“高情商回复”。加入快捷入口栏后，在键盘候选行一键打开；写好内容再点 ▶ 才会发送。",
                       "Each assistant is your own instruction, such as a lullaby or a tactful reply. Add it to the quick entrance bar to open it from the keyboard's candidate row; nothing is sent until you tap ▶."))
                    .font(.callout).foregroundStyle(.secondary)
                NavigationLink { EntranceBarView() } label: {
                    HStack {
                        Label(L("快捷入口栏", "Quick entrance bar"), systemImage: "rectangle.3.group")
                        Spacer()
                        Text(L("\(library.entranceEntries.count) 项", "\(library.entranceEntries.count) shown")).foregroundStyle(.secondary)
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                    .padding(14).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }.buttonStyle(.plain).accessibilityIdentifier("assistant.entrance")

                section(L("我的助手", "My assistants")) {
                    GalleryGrid {
                        ForEach(library.presets) { preset in presetCard(preset) }
                        Button { editing = AssistantPreset() } label: { newCard }.buttonStyle(.plain).accessibilityIdentifier("assistant.new")
                    }
                }
                if !unusedStarters.isEmpty {
                    section(L("起步模板", "Starter presets")) {
                        GalleryGrid {
                            ForEach(unusedStarters) { starter in
                                GalleryCard(symbol: starter.symbol, title: chinese ? starter.nameZH : starter.nameEN,
                                            tagline: chinese ? starter.taglineZH : starter.taglineEN, status: .notInstalled,
                                            detail: L("模板", "Starter"), primaryTitle: L("添加", "Add"), primary: {
                                    update { _ = $0.save(starter.preset(chinese: chinese)) }
                                }).accessibilityIdentifier("assistant.starter.\(starter.id)")
                            }
                        }
                    }
                }
            }.padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(L("AI 助手", "AI assistant"))
        .sheet(item: $editing) { AssistantPresetEditor(preset: $0).environmentObject(model) }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) { Text(title).font(.title3.bold()); content() }
    }
    private var newCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "plus").font(.title2.weight(.semibold))
            Text(L("新建助手", "New assistant")).font(.subheadline.weight(.medium))
        }
        .frame(maxWidth: .infinity, minHeight: 150).foregroundStyle(.tint)
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])).foregroundStyle(.tint.opacity(0.5)))
    }
    private func presetCard(_ preset: AssistantPreset) -> some View {
        let onBar = library.entranceEntries.contains(preset.entryID)
        return GalleryCard(symbol: preset.symbol, title: preset.name, tagline: preset.instruction,
                           status: onBar ? .enabled : .installed, detail: onBar ? L("在入口栏", "On the bar") : L("不在入口栏", "Not on the bar"),
                           primaryTitle: onBar ? L("移出入口栏", "Remove from bar") : L("加入入口栏", "Add to bar"),
                           primaryIsProminent: !onBar, primary: { update { $0.setOnEntrance(preset.entryID, !onBar) } },
                           menu: [GalleryMenuItem(title: L("编辑", "Edit"), action: { editing = preset }),
                                  GalleryMenuItem(title: L("删除", "Delete"), destructive: true, action: { update { $0.remove(preset.id) } })],
                           onOpen: { editing = preset })
            .accessibilityIdentifier("assistant.preset.\(preset.id.uuidString)")
    }
}

/// Which entries sit on the keyboard's candidate-row bar, and in what order.
struct EntranceBarView: View {
    @EnvironmentObject private var model: SettingsModel
    private var library: AssistantLibrary { model.value.assistantLibrary }
    private func update(_ change: (inout AssistantLibrary) -> Void) {
        var next = model.value.assistantLibrary; change(&next)
        model.value.assistantLibrary = next; model.save()
    }
    private func plugin(_ entry: String) -> KeyboardPlugin? { KeyboardPlugin.entry(entry, in: library) }
    private var hidden: [String] { library.allEntries.filter { !library.entranceEntries.contains($0) } }

    var body: some View {
        List {
            Section {
                ForEach(library.entranceEntries, id: \.self) { entry in
                    if let plugin = plugin(entry) { Label(plugin.title, systemImage: plugin.symbol) }
                }
                .onMove { source, destination in update { $0.moveEntrance(from: source, to: destination) } }
                .onDelete { offsets in
                    let entries = library.entranceEntries
                    update { library in offsets.forEach { library.setOnEntrance(entries[$0], false) } }
                }
            } header: { Text(L("显示在键盘上", "Shown on the keyboard")) }
            footer: { Text(L("按住拖动排序，左滑移出。键盘空闲时，这一排会出现在候选行里；其余插件仍可从 Buffer 菜单打开。", "Drag to reorder, swipe to remove. The bar fills the keyboard's empty candidate row; other plugins stay in the Buffer menu.")) }
            if !hidden.isEmpty {
                Section(L("未显示", "Not shown")) {
                    ForEach(hidden, id: \.self) { entry in
                        if let plugin = plugin(entry) {
                            HStack {
                                Label(plugin.title, systemImage: plugin.symbol)
                                Spacer()
                                Button { update { $0.setOnEntrance(entry, true) } } label: { Image(systemName: "plus.circle.fill").font(.title3) }
                                    .buttonStyle(.borderless).accessibilityLabel(L("加入入口栏", "Add to bar"))
                            }
                        }
                    }
                }
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle(L("快捷入口栏", "Quick entrance bar"))
    }
}

struct AssistantPresetEditor: View {
    @EnvironmentObject private var model: SettingsModel
    @Environment(\.dismiss) private var dismiss
    @State var preset: AssistantPreset
    @State private var message = ""
    private static let symbols = ["sparkles", "moon.stars", "heart.text.square", "heart", "scissors", "face.smiling", "text.bubble", "pencil.and.outline",
                                  "briefcase", "graduationcap", "globe", "lightbulb", "megaphone", "gift", "leaf", "flame"]
    var body: some View {
        NavigationStack {
            Form {
                TextField(L("名称，如“哄睡”", "Name, e.g. “Lullaby”"), text: $preset.name).accessibilityIdentifier("assistant.name")
                Section(L("图标", "Icon")) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 8) {
                        ForEach(Self.symbols, id: \.self) { symbol in
                            Button { preset.symbol = symbol } label: {
                                Image(systemName: symbol).frame(width: 40, height: 40)
                                    .background(preset.symbol == symbol ? Color.accentColor.opacity(0.2) : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }.buttonStyle(.plain)
                        }
                    }
                }
                Section {
                    TextField(L("告诉 AI 要怎么做", "Tell the AI what to do"), text: $preset.instruction, axis: .vertical).lineLimit(5...12)
                        .accessibilityIdentifier("assistant.instruction")
                } header: { Text(L("指令", "Instruction")) } footer: {
                    Text(L("键盘输入行里写的内容会作为用户消息发给 AI。可以说明对象、语气、长度和语言。", "What is written in the keyboard's input line is sent as the user message. You can set audience, tone, length and language."))
                }
                TextField(L("输入行提示（可选）", "Input-line hint (optional)"), text: $preset.placeholder)
                if !message.isEmpty { Text(message).foregroundStyle(.red) }
            }
            .navigationTitle(L("助手", "Assistant"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("取消", "Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(L("保存", "Save")) { save() } }
            }
        }
    }
    private func save() {
        var next = model.value.assistantLibrary
        guard next.save(preset) else {
            message = preset.instruction.utf8.count > AssistantPreset.maxInstructionBytes ? L("指令太长", "Instruction is too long")
                : L("请填写名称和指令", "Enter a name and an instruction")
            return
        }
        model.value.assistantLibrary = next; model.save(); dismiss()
    }
}
