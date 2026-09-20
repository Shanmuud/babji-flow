import SwiftUI

struct DictionaryView: View {
    @ObservedObject var store = DictionaryStore.shared
    @State private var filter = 0
    @State private var search = ""
    @State private var showAdd = false
    @State private var editing: DictionaryEntry?
    @State private var showBanner = true
    @ObservedObject var snippets = SnippetStore.shared
    @State private var showAddSnippet = false
    @State private var editingSnippet: Snippet?

    var filtered: [DictionaryEntry] {
        store.entries.filter { e in
            (filter == 0 || (filter == 1 && e.source == .manual) || (filter == 2 && e.source == .learned)) &&
            (search.isEmpty || e.word.localizedCaseInsensitiveContains(search) || e.misheard.contains { $0.localizedCaseInsensitiveContains(search) })
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack { PageTitle(text: filter == 3 ? "Snippets" : "Dictionary"); Spacer(); Button(filter == 3 ? "New snippet" : "Add new") { if filter == 3 { showAddSnippet = true } else { showAdd = true } }.buttonStyle(PillButton()) }
                HStack(spacing: 18) {
                    Tab(label: "All", on: filter == 0) { filter = 0 }
                    Tab(label: "Manual", on: filter == 1) { filter = 1 }
                    Tab(label: "Learned ✨", on: filter == 2) { filter = 2 }
                    Tab(label: "Snippets", on: filter == 3) { filter = 3 }
                    Spacer()
                    TextField("Search", text: $search).textFieldStyle(.roundedBorder).frame(width: 180)
                }
                if filter == 3 {
                    Hero(title: "Say it once, paste it forever.", subtitle: "Snippets expand when you speak the trigger: say \"my email\" and Babji types the full address. Great for links, addresses, sign-offs and bios.", mascot: .speaking) { EmptyView() }
                    Card {
                        if snippets.snippets.isEmpty { Text("No snippets yet.").foregroundStyle(Theme.muted).font(.system(size: 13)) }
                        ForEach(snippets.snippets) { s in
                            HStack(alignment: .top, spacing: 10) {
                                Text(s.trigger).font(.system(size: 13, weight: .semibold)).frame(width: 140, alignment: .leading)
                                Text(s.expansion).font(.system(size: 13)).foregroundStyle(Theme.muted).lineLimit(2)
                                Spacer()
                                Button { editingSnippet = s } label: { Image(systemName: "pencil") }.buttonStyle(.plain)
                                Button { snippets.remove(s) } label: { Image(systemName: "trash") }.buttonStyle(.plain)
                            }.padding(.vertical, 6)
                            if s.id != snippets.snippets.last?.id { Divider() }
                        }
                    }
                } else if showBanner {
                    Hero(title: "Babji spells the way you do.", subtitle: "Correct a spelling once in any app and Babji learns it automatically (marked ✨). Or add personal terms, company jargon and uncommon names here so they are spelled right in dictations and meeting notes.", mascot: .happy) {
                        HStack(spacing: 8) {
                            Button("Add new word") { showAdd = true }.buttonStyle(PillButton(dark: false))
                            ForEach(["Babji Flow", "Tappr", "Parakeet"], id: \.self) { w in
                                Button(w) { store.add(word: w) }.buttonStyle(PillButton(dark: false)).opacity(0.85)
                            }
                        }
                    }.overlay(alignment: .topTrailing) {
                        Button { showBanner = false } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).padding(6).background(Color.black.opacity(0.08)).clipShape(Circle()) }
                            .buttonStyle(.plain).foregroundStyle(Color.black.opacity(0.6)).padding(10)
                    }
                }
                if filter != 3 { Card {
                    if filtered.isEmpty { Text(store.entries.isEmpty ? "No words yet." : "No matches.").foregroundStyle(Theme.muted).font(.system(size: 13)) }
                    ForEach(filtered) { e in
                        HStack(spacing: 8) {
                            Text(e.word).font(.system(size: 14))
                            if e.source == .learned { Text("✨").font(.system(size: 11)) }
                            if !e.misheard.isEmpty { Text("← " + e.misheard.joined(separator: ", ")).font(.system(size: 12)).foregroundStyle(Theme.muted) }
                            Spacer()
                            Button { editing = e } label: { Image(systemName: "pencil") }.buttonStyle(.plain)
                            Button { store.remove(e) } label: { Image(systemName: "trash") }.buttonStyle(.plain)
                            Button { store.toggleStar(e) } label: { Image(systemName: e.starred ? "star.fill" : "star") }.buttonStyle(.plain)
                        }.padding(.vertical, 6)
                        if e.id != filtered.last?.id { Divider() }
                    }
                } }
            }.padding(24)
        }
        .sheet(isPresented: $showAddSnippet) { SnippetEditor(snippet: Snippet(trigger: "", expansion: "")) { snippets.add(trigger: $0.trigger, expansion: $0.expansion) } }
        .sheet(item: $editingSnippet) { s in SnippetEditor(snippet: s) { snippets.update($0) } }
        .sheet(isPresented: $showAdd) { EntryEditor(entry: DictionaryEntry(word: "")) { store.add(word: $0.word, misheard: $0.misheard) } }
        .sheet(item: $editing) { e in EntryEditor(entry: e) { store.update($0) } }
    }
}

struct Tab: View {
    var label: String; var on: Bool; var action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Text(label).font(.system(size: 13, weight: on ? .semibold : .regular)).foregroundStyle(on ? .primary : Theme.muted)
                Rectangle().fill(on ? Color.primary : .clear).frame(height: 2)
            }
        }.buttonStyle(.plain)
    }
}

struct EntryEditor: View {
    @Environment(\.dismiss) var dismiss
    @State var entry: DictionaryEntry
    @State private var misheard = ""
    var onSave: (DictionaryEntry) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(entry.word.isEmpty ? "Add word" : "Edit word").font(.headline)
            TextField("Correct spelling (e.g. Tappr)", text: $entry.word)
            TextField("Often heard as (comma separated, e.g. tapper, tap her)", text: $misheard)
            Text("Words here are used as spelling hints for the AI polish, and any 'heard as' variants are replaced directly.").font(.system(size: 11)).foregroundStyle(Theme.muted)
            HStack { Spacer(); Button("Cancel") { dismiss() }; Button("Save") {
                entry.misheard = misheard.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                onSave(entry); dismiss()
            }.keyboardShortcut(.defaultAction).disabled(entry.word.trimmingCharacters(in: .whitespaces).isEmpty) }
        }.padding(20).frame(width: 420).onAppear { misheard = entry.misheard.joined(separator: ", ") }
    }
}


struct SnippetEditor: View {
    @Environment(\.dismiss) var dismiss
    @State var snippet: Snippet
    var onSave: (Snippet) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(snippet.trigger.isEmpty ? "New snippet" : "Edit snippet").font(.headline)
            TextField("Trigger phrase you'll say (e.g. my email)", text: $snippet.trigger)
            Text("Expands to").font(.system(size: 11)).foregroundStyle(Theme.muted)
            TextEditor(text: $snippet.expansion).font(.system(size: 13)).frame(height: 110).scrollContentBackground(.hidden).background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 8))
            HStack { Spacer(); Button("Cancel") { dismiss() }; Button("Save") { onSave(snippet); dismiss() }.keyboardShortcut(.defaultAction).disabled(snippet.trigger.trimmingCharacters(in: .whitespaces).isEmpty || snippet.expansion.isEmpty) }
        }.padding(20).frame(width: 440)
    }
}
