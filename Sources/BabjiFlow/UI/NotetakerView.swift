import SwiftUI

struct NotetakerView: View {
    @ObservedObject var store = MeetingStore.shared
    @ObservedObject var recorder = MeetingRecorder.shared
    @ObservedObject var settings = Settings.shared
    @State private var selected: UUID?
    @State private var search = ""
    @State private var question = ""
    @State private var answer = ""
    @State private var asking = false

    var body: some View {
        HSplitView {
            list.frame(minWidth: 380, idealWidth: 460)
            detail.frame(minWidth: 380)
        }
        .onAppear { if selected == nil { selected = store.meetings.first?.id } }
    }

    var list: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                PageTitle(text: "Notetaker"); Spacer()
                if recorder.isRecording {
                    Button { Task { if let m = await recorder.stop() { selected = m.id } } } label: { Label("Stop", systemImage: "stop.fill") }.buttonStyle(PillButton())
                } else {
                    Button { Task { await recorder.start(app: MicActivityMonitor.likelyMeetingApp() ?? "Manual") } } label: { Label("New note", systemImage: "plus") }.buttonStyle(PillButton(dark: false))
                }
            }
            Card {
                Text(recorder.isRecording ? "RECORDING" : "TODAY").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.muted)
                if recorder.isRecording {
                    if !recorder.status.isEmpty { Text(recorder.status).font(.system(size: 12)).foregroundStyle(.orange) }
                    if recorder.liveSegments.isEmpty { Text("Listening… transcript appears in ~25 s chunks.").font(.system(size: 13)).foregroundStyle(Theme.muted) }
                    ScrollView { VStack(alignment: .leading, spacing: 6) { ForEach(recorder.liveSegments.suffix(12)) { s in
                        HStack(alignment: .top, spacing: 6) { Text(s.speaker).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.accent); Text(s.text).font(.system(size: 12.5)) }
                    } } }.frame(maxHeight: 160)
                } else {
                    let today = store.meetings.filter { Calendar.current.isDateInToday($0.date) }
                    if today.isEmpty { HStack(spacing: 12) { BabjiFace(mood: .thinking, height: 54); Text("No meetings today.\nBabji will ask to take notes when a call starts.").font(.system(size: 13)).foregroundStyle(Theme.muted) }.frame(maxWidth: .infinity).padding(.vertical, 6) }
                    ForEach(today) { m in row(m) }
                }
            }
            HStack { Tab(label: "Past notes", on: true) {}; Spacer(); TextField("Search", text: $search).textFieldStyle(.roundedBorder).frame(width: 160) }
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(store.grouped, id: \.0) { label, items in
                        let shown = items.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.transcriptText.localizedCaseInsensitiveContains(search) }
                        if !shown.isEmpty {
                            Text(label.uppercased()).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.muted).padding(.top, 8)
                            ForEach(shown) { m in row(m) }
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 6) {
                if !answer.isEmpty { ScrollView { Text(answer).font(.system(size: 13)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 140).padding(10).background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 10)) }
                HStack {
                    TextField("How should I prepare for my next meeting?", text: $question).textFieldStyle(.plain).onSubmit { askAll() }
                    if asking { ProgressView().controlSize(.small) } else { Button("Ask") { askAll() }.buttonStyle(PillButton(dark: false)).disabled(question.isEmpty) }
                }.padding(10).background(Theme.panel).clipShape(RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
            }
        }.padding(20)
    }

    func row(_ m: Meeting) -> some View {
        Button { selected = m.id } label: {
            HStack(spacing: 10) {
                Image(systemName: "doc.text").frame(width: 34, height: 34).background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) { Text(m.title).font(.system(size: 13.5)); Text(m.date.formatted(date: .omitted, time: .shortened)).font(.system(size: 11)).foregroundStyle(Theme.muted) }
                Spacer()
                if m.summary == nil { Image(systemName: "sparkles.slash").foregroundStyle(Theme.muted).help("No summary yet") }
            }.padding(8).background(selected == m.id ? Theme.card : .clear).clipShape(RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain)
    }

    func askAll() {
        guard !question.isEmpty, LLM.hasKey else { answer = LLM.hasKey ? "" : LLM.missingKeyMessage; return }
        let q = question; question = ""; answer = ""; asking = true
        Task {
            do { for try await t in TranscriptChat.askAll(store.meetings, question: q) { answer += t } } catch { answer = error.localizedDescription }
            asking = false
        }
    }

    @ViewBuilder var detail: some View {
        if let id = selected, let m = store.meeting(id) {
            MeetingDetail(meeting: m)
        } else {
            VStack(spacing: 10) { Spacer(); BabjiFace(mood: .happy, height: 110); Text("Pick a note, or ask Babji anything about your meetings.").font(.system(size: 13)).foregroundStyle(Theme.muted); Spacer() }.frame(maxWidth: .infinity)
        }
    }
}

struct MeetingDetail: View {
    var meeting: Meeting
    @ObservedObject var store = MeetingStore.shared
    @ObservedObject var settings = Settings.shared
    @State private var tab = 0
    @State private var question = ""
    @State private var streaming = ""
    @State private var asking = false
    @State private var showChat = false
    @State private var renaming: String?
    @State private var newName = ""
    @State private var regenerating = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(meeting.title).font(.system(size: 18, weight: .semibold))
                        Text("\(meeting.date.formatted(date: .abbreviated, time: .shortened)) · \(Int(meeting.duration / 60)) min · \(meeting.app)").font(.system(size: 12)).foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    Menu {
                        Button("Regenerate summary") { regenerate() }
                        Button("Copy summary") { copySummary() }
                        Button("Copy transcript") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(meeting.transcriptText, forType: .string) }
                        Divider()
                        Button("Delete note", role: .destructive) { store.delete(meeting) }
                    } label: { Image(systemName: "ellipsis.circle") }.menuStyle(.borderlessButton).frame(width: 30)
                }
                HStack(spacing: 18) { Tab(label: "Summary", on: tab == 0) { tab = 0 }; Tab(label: "Transcript", on: tab == 1) { tab = 1 }; Spacer(); Text("💡 \(meeting.readMinutes) MIN READ").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.muted) }
            }.padding(20)
            Divider()
            ScrollView { Group { if tab == 0 { summary } else { transcript } }.padding(20).frame(maxWidth: .infinity, alignment: .leading) }
            Divider()
            chatBar
        }
        .sheet(item: Binding(get: { renaming.map { RenameTarget(id: $0) } }, set: { renaming = $0?.id })) { t in
            VStack(alignment: .leading, spacing: 10) {
                Text("Rename \(t.id)").font(.headline)
                TextField("Name", text: $newName)
                HStack { Spacer(); Button("Cancel") { renaming = nil }; Button("Save") { var m = meeting; m.speakerNames[t.id] = newName; store.upsert(m); renaming = nil }.keyboardShortcut(.defaultAction) }
            }.padding(20).frame(width: 320)
        }
    }

    @ViewBuilder var summary: some View {
        if let s = meeting.summary {
            VStack(alignment: .leading, spacing: 18) {
                Text("OVERVIEW").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.muted)
                SpeakerText(text: s.overview, meeting: meeting, size: 14)
                ForEach(s.sections) { sec in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(sec.heading).font(.system(size: 14, weight: .semibold))
                        ForEach(sec.bullets, id: \.self) { b in HStack(alignment: .top, spacing: 8) { Text("•"); SpeakerText(text: b, meeting: meeting, size: 13.5) } }
                    }
                }
                if !s.nextSteps.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Next Steps").font(.system(size: 14, weight: .semibold))
                        ForEach(s.nextSteps) { st in HStack(alignment: .top, spacing: 8) { Text("•"); (Text("(\(meeting.displayName(for: st.owner))) ").foregroundStyle(Theme.accent) + Text(st.action)).font(.system(size: 13.5)) } }
                    }
                }
                if !s.decisions.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Decisions Made").font(.system(size: 14, weight: .semibold))
                        ForEach(s.decisions, id: \.self) { d in HStack(alignment: .top, spacing: 8) { Text("•"); Text(d).font(.system(size: 13.5)) } }
                    }
                }
            }.textSelection(.enabled)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text(meeting.summaryError ?? "No summary yet.").font(.system(size: 13)).foregroundStyle(Theme.muted)
                if !LLM.hasKey { Text(LLM.missingKeyMessage + " Summaries and chat need it.").font(.system(size: 12)).foregroundStyle(Theme.muted) }
                Button(regenerating ? "Summarising…" : "Generate summary") { regenerate() }.buttonStyle(PillButton()).disabled(regenerating || meeting.segments.isEmpty)
            }
        }
    }

    var transcript: some View {
        VStack(alignment: .leading, spacing: 10) {
            if meeting.segments.isEmpty { Text("Empty transcript.").foregroundStyle(Theme.muted) }
            ForEach(meeting.segments) { s in
                HStack(alignment: .top, spacing: 10) {
                    Text(String(format: "%02d:%02d", Int(s.start) / 60, Int(s.start) % 60)).font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.muted).frame(width: 40, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Button { renaming = s.speaker; newName = meeting.displayName(for: s.speaker) } label: { Text(meeting.displayName(for: s.speaker)).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.accent) }.buttonStyle(.plain).help("Rename speaker")
                        Text(s.text).font(.system(size: 13.5)).textSelection(.enabled)
                    }
                }
            }
        }
    }

    var chatBar: some View {
        VStack(spacing: 8) {
            if showChat && (!meeting.chat.isEmpty || !streaming.isEmpty) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(meeting.chat) { t in bubble(t.text, user: t.role == "user").id(t.id) }
                            if !streaming.isEmpty { bubble(streaming, user: false).id("stream") }
                        }.padding(.horizontal, 4)
                    }.frame(maxHeight: 260)
                    .onChange(of: streaming) { _, _ in proxy.scrollTo("stream", anchor: .bottom) }
                }
                HStack { Spacer(); Button("Clear chat") { var m = meeting; m.chat = []; store.upsert(m) }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Theme.muted) }
            }
            HStack {
                TextField("Ask anything about this meeting", text: $question).textFieldStyle(.plain).onSubmit { ask() }
                if asking { ProgressView().controlSize(.small) } else { Button { ask() } label: { Image(systemName: "arrow.up.circle.fill").font(.system(size: 22)) }.buttonStyle(.plain).disabled(question.isEmpty) }
            }.padding(10).background(Theme.panel).clipShape(RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
        }.padding(14)
    }

    func bubble(_ text: String, user: Bool) -> some View {
        HStack { if user { Spacer(minLength: 60) }
            Text(text).font(.system(size: 13)).textSelection(.enabled).padding(10)
                .background(user ? Color.primary : Theme.card).foregroundStyle(user ? Color(nsColor: .windowBackgroundColor) : .primary).clipShape(RoundedRectangle(cornerRadius: 12))
            if !user { Spacer(minLength: 60) } }
    }

    func ask() {
        guard !question.isEmpty else { return }
        guard LLM.hasKey else { var m = meeting; m.chat.append(ChatTurn(role: "user", text: question)); m.chat.append(ChatTurn(role: "assistant", text: LLM.missingKeyMessage)); store.upsert(m); question = ""; showChat = true; return }
        var m = meeting
        m.chat.append(ChatTurn(role: "user", text: question))
        store.upsert(m)
        question = ""; showChat = true; asking = true; streaming = ""
        let history = m.chat
        Task {
            var full = ""
            do { for try await t in TranscriptChat.ask(m, history: history) { full += t; streaming = full } } catch { full = (full.isEmpty ? "" : full + "\n\n") + "Error: " + error.localizedDescription }
            var m2 = store.meeting(meeting.id) ?? m
            m2.chat.append(ChatTurn(role: "assistant", text: full))
            store.upsert(m2)
            streaming = ""; asking = false
        }
    }

    func regenerate() {
        regenerating = true
        Task { let m = await Summarizer.summarise(meeting); store.upsert(m); regenerating = false }
    }
    func copySummary() {
        guard let s = meeting.summary else { return }
        var t = s.overview + "\n\n"
        for sec in s.sections { t += sec.heading + "\n" + sec.bullets.map { "• " + $0 }.joined(separator: "\n") + "\n\n" }
        if !s.nextSteps.isEmpty { t += "Next Steps\n" + s.nextSteps.map { "• (\(meeting.displayName(for: $0.owner))) \($0.action)" }.joined(separator: "\n") + "\n\n" }
        if !s.decisions.isEmpty { t += "Decisions Made\n" + s.decisions.map { "• " + $0 }.joined(separator: "\n") }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(t, forType: .string)
    }
}

struct RenameTarget: Identifiable { var id: String }

/// Renders text with "Speaker N" labels highlighted (and renamed if the user renamed them).
struct SpeakerText: View {
    var text: String; var meeting: Meeting; var size: CGFloat
    var body: some View {
        var out = Text("")
        let pattern = try! NSRegularExpression(pattern: #"Speaker \d+|You"#)
        let ns = text as NSString
        var last = 0
        for m in pattern.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            out = out + Text(ns.substring(with: NSRange(location: last, length: m.range.location - last)))
            let label = ns.substring(with: m.range)
            out = out + Text(meeting.displayName(for: label)).foregroundStyle(Theme.accent).underline()
            last = m.range.location + m.range.length
        }
        out = out + Text(ns.substring(from: last))
        return out.font(.system(size: size))
    }
}
