import SwiftUI
import SwiftData
import PhotosUI
import UIKit

// MARK: - UI/UX, Apple Human Interface Guidelines
//
// Every screen below follows the HIG, in this order:
// 1. Clarity — one task per screen, one primary action, plain language.
//    System type styles only (.largeTitle / .title2 / .headline / .body /
//    .caption), so Dynamic Type and VoiceOver work without custom code.
// 2. Deference — content first, chrome minimal. No custom colours, no
//    custom fonts, no decorative gradients. Semantic colours only
//    (.primary / .secondary / .red / .orange / .green), so Light and Dark
//    Mode and increased contrast work for free.
// 3. Depth — hierarchy comes from system materials and grouping, not from
//    shadows or borders drawn by hand: cards use
//    Color(.secondarySystemBackground) with a 16pt corner radius, sheets
//    and the navigation bar use the system's Liquid Glass chrome
//    automatically in iOS 26/27. No custom glassEffect() is used.
// 4. Touch — every tappable control is at least 44pt tall. The primary
//    action is .borderedProminent + .controlSize(.large); Call 112 is
//    always reachable in the bottom safe area, never hidden in a menu.
// 5. Feedback — progress is always visible while the agent works,
//    success is confirmed with sensory feedback, errors name the next
//    step instead of only naming the problem.
// 6. Accessibility — every icon-only control has an accessibility label,
//    every destructive / irreversible-looking action says what it does
//    (approving a draft never sends it), and empty states use
//    ContentUnavailableView instead of a blank list.

// Two steps, not three (21 Nov 2026): the separate Review screen is
// gone. In a real emergency nobody should proofread a form before
// getting help — Analyse goes straight to the action plan, where the
// brief is shown at the top and still editable (Edit opens this same
// editor as a sheet; saving rebuilds the plan). The human gate moves,
// it does not disappear.
enum SiagaStep: Int, CaseIterable {
    case note = 1, plan
    var title: String {
        switch self {
        case .note: return "Describe"
        case .plan: return "Act"
        }
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [MedicalProfile]

    @State private var store = SiagaStore()
    @State private var agent: SiagaAgent?
    @State private var step: SiagaStep = .note
    @State private var draftBrief: EmergencyBrief?
    @State private var draftApproved = false
    @State private var showHistory = false
    @State private var showProfiles = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 21 Nov 2026: the step indicator above the title is gone
                // (Arief) — in an emergency the screen should show the
                // task, not the flow. The step state still drives which
                // screen shows; only the indicator was removed.
                switch step {
                case .note:
                    EmergencyNoteView(
                        messages: agent?.messages ?? [],
                        profiles: profiles,
                        selectedProfile: $store.selectedProfile,
                        isWorking: agent?.isWorking ?? false,
                        streamingText: agent?.streamingText ?? "",
                        problem: agent?.problem,
                        fallbackUsed: agent?.fallbackUsed ?? false,
                        unavailableReason: agent?.unavailableReason,
                        onSend: { text, image in
                            Task { await agent?.sendChat(text, image: image) }
                        },
                        onBuildPlan: { image in
                            Task {
                                if let brief = await agent?.analyse(image: image) {
                                    draftBrief = brief
                                    store.currentBrief = brief
                                    if let incident = store.saveIncident() {
                                        modelContext.insert(incident)
                                        try? modelContext.save()
                                        SiagaSpotlightIndexer.indexIncident(incident)
                                    }
                                    step = .plan
                                    await agent?.buildActionPlan()
                                }
                            }
                        }
                    )
                case .plan:
                    ActionPlanView(
                        store: store,
                        agent: agent,
                        brief: $draftBrief,
                        draftApproved: $draftApproved,
                        onNewIncident: {
                            agent?.newIncident()
                            draftBrief = nil
                            draftApproved = false
                            step = .note
                        }
                    )
                }
            }
            .navigationTitle("Siaga")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showProfiles = true } label: {
                        Label("Profiles", systemImage: "person.2.fill")
                    }
                    .accessibilityLabel("Family profiles")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showHistory = true } label: {
                        Label("History", systemImage: "clock.arrow.circlepath")
                    }
                    .accessibilityLabel("Incident history")
                }
            }
            .sheet(isPresented: $showHistory) {
                NavigationStack { HistoryView() }
            }
            .sheet(isPresented: $showProfiles) {
                NavigationStack { ProfilesView() }
            }
            // HIG: the way out is always visible and always reachable.
            // Call 112 lives in the bottom safe area, full width, 52pt
            // tall, red and prominent — never in a menu, never scrolled away.
            .safeAreaInset(edge: .bottom) {
                Call112Button()
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                    .background(.bar)
            }
            .sensoryFeedback(.success, trigger: step)
        }
        .task {
            let created = SiagaAgent(store: store)
            agent = created
            created.prewarm()
            created.greetIfNeeded()
        }
        .onAppear {
            seedProfilesIfNeeded()
            SiagaSpotlightIndexer.indexFirstAidCases(store.firstAidCases)
        }
        .onChange(of: profiles) { _, newValue in store.profiles = newValue }
    }

    // DEMO DATA ONLY. These 3 profiles exist so the hackathon demo works
    // out of the box. A real user deletes them in Profiles and adds their
    // own family. Nothing in the app depends on these names existing.
    private func seedProfilesIfNeeded() {
        store.profiles = profiles
        guard profiles.isEmpty else { return }
        let seed = [
            MedicalProfile(name: "Sari", age: 68, bloodType: "O+", allergies: "Penicillin", medications: "Amlodipine",
                           emergencyContactName: "Budi", emergencyContactRelation: "Son", emergencyContactPhone: "+62 812-0000-0001"),
            MedicalProfile(name: "Agus", age: 70, bloodType: "A", allergies: "None", medications: "None",
                           emergencyContactName: "Budi", emergencyContactRelation: "Son", emergencyContactPhone: "+62 812-0000-0001"),
            MedicalProfile(name: "Budi", age: 42, bloodType: "B+", allergies: "None", medications: "None",
                           emergencyContactName: "Sari", emergencyContactRelation: "Mother", emergencyContactPhone: "+62 812-0000-0002"),
        ]
        for profile in seed { modelContext.insert(profile) }
        try? modelContext.save()
        store.profiles = seed
    }
}

// MARK: - Always-on header

struct Call112Button: View {
    var body: some View {
        Link(destination: URL(string: "tel://112")!) {
            Label("Call 112", systemImage: "phone.fill")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 52)
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
        .accessibilityLabel("Call emergency services, 112")
        .accessibilityHint("Opens the phone app to call 112. Siaga does not call for you.")
    }
}

// MARK: - Shared card (HIG: grouping + depth from system materials)

struct SiagaCard<Content: View>: View {
    var icon: String
    var title: String
    var tint: Color = .accentColor
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(tint)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

extension Severity {
    var color: Color {
        switch self {
        case .critical: return .red
        case .high: return .orange
        case .medium: return .yellow
        case .low: return .green
        }
    }
    var label: String { rawValue.capitalized }
}

struct SeverityBadge: View {
    var severity: Severity
    var body: some View {
        Label(severity.label, systemImage: "exclamationmark.triangle.fill")
            .font(.subheadline.bold())
            .foregroundStyle(severity.color)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(severity.color.opacity(0.12), in: Capsule())
            .accessibilityLabel("Severity: \(severity.label)")
    }
}

// MARK: - Aligned label/value rows (Action Plan cards)

// 21 Nov 2026: the draft and handover cards used to be one plain Text,
// so a wrapped line started under the LABEL ("Severity:", "Person:",
// "Symptoms:") instead of under the value. A Grid sizes the label
// column to the widest label and wraps every value under itself.
struct LabeledRows: View {
    var rows: [(label: String, value: String)]

    var body: some View {
        Grid(alignment: .topLeading, horizontalSpacing: 10, verticalSpacing: 6) {
            ForEach(rows, id: \.label) { row in
                GridRow {
                    Text(row.label + ":")
                        .font(.body.bold())
                    Text(row.value)
                        .font(.body)
                }
            }
        }
    }
}

// MARK: - Step 1: Chat (Describe)

// Step 1 is a CHAT now (21 Nov 2026, WorkspaceAssistant pattern): the
// user talks to Siaga like Claude — messages stream in, the agent asks
// at most one short question at a time, and the brief is extracted from
// the whole conversation when the user taps "Build action plan". The old
// deterministic question detector (NoteKind) is gone: in a chat, a
// question is answered by the agent, not blocked by the input.
struct ChatBubble: View {
    var message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            Text(message.text)
                .font(.body)
                .padding(12)
                .background(message.role == .user ? Color.accentColor : Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
                .foregroundStyle(message.role == .user ? Color.white : Color.primary)
            if message.role == .agent { Spacer(minLength: 40) }
        }
    }
}

struct EmergencyNoteView: View {
    var messages: [ChatMessage]
    var profiles: [MedicalProfile]
    @Binding var selectedProfile: MedicalProfile?
    var isWorking: Bool
    var streamingText: String
    var problem: String?
    var fallbackUsed: Bool
    var unavailableReason: String?
    var onSend: (String, UIImage?) -> Void
    var onBuildPlan: (UIImage?) -> Void

    @State private var draft = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var photoImage: UIImage?
    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var photoLoadError: String?
    // 21 Nov 2026: the keyboard stays up after Send unless focus is
    // cleared explicitly — the user asked for it to close on send.
    @FocusState private var isComposerFocused: Bool

    private var hasUserMessage: Bool { messages.contains { $0.role == .user } }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // HIG hierarchy: one large title, one short explanation.
                    // 21 Nov 2026: the model was silently unavailable on the
                    // test iPhone, so every answer came from the template
                    // fallback and looked like the AI was not working. The
                    // reason now shows BEFORE anything is sent, with what
                    // to do about it — never a silent fallback again.
                    if let unavailableReason {
                        Label("\(unavailableReason) Until then Siaga uses the offline fallback, so answers look like templates.", systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                            .padding(12)
                            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                            .accessibilityLabel("Apple Intelligence unavailable. \(unavailableReason)")
                    }
                    Text("What happened?")
                        .font(.largeTitle.bold())
                        .accessibilityAddTraits(.isHeader)
                    Text("Tell me what happened. Siaga asks only what it needs, then builds the action plan.")
                        .font(.body)
                        .foregroundStyle(.secondary)

                    // Who is this about? The user picks a real profile here.
                    // Nothing is assumed: no selection means "Unknown", and the
                    // app never silently falls back to the first profile.
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Who is this about?")
                            .font(.headline)
                        Picker("Who is this about?", selection: $selectedProfile) {
                            Text("Someone else / unknown").tag(nil as MedicalProfile?)
                            ForEach(profiles) { profile in
                                Text(profile.name).tag(profile as MedicalProfile?)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(minHeight: 44)
                        .accessibilityLabel("Who is this about?")
                        if let selectedProfile {
                            Text(selectedProfile.summary).font(.subheadline).foregroundStyle(.secondary)
                        } else {
                            Text("Optional. Without a profile, Siaga skips allergy and contact details.")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }

                    // Samples are shortcuts that SEND, not text that fills
                    // a field — one tap starts the conversation.
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Try a sample")
                            .font(.headline)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(SampleNotes.all, id: \.title) { sample in
                                    Button(sample.title) {
                                        // A chip is a send too — the
                                        // keyboard closes, same as Send.
                                        isComposerFocused = false
                                        onSend(sample.text, nil)
                                    }
                                        .buttonStyle(.bordered)
                                        .frame(minHeight: 44)
                                        .disabled(isWorking)
                                }
                            }
                        }
                    }

                    // The conversation. The streaming reply shows as a
                    // live agent bubble while it arrives, word by word.
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(messages) { message in
                            ChatBubble(message: message)
                        }
                        if isWorking && !streamingText.isEmpty {
                            ChatBubble(message: ChatMessage(role: .agent, text: streamingText))
                        }
                    }

                    if fallbackUsed {
                        Label("Offline fallback is on (model unavailable). Please check the brief carefully.", systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                    }
                    if let problem {
                        Text(problem).font(.subheadline).foregroundStyle(.red)
                    }

                    // The plan is built on demand, from the whole
                    // conversation — the agent's questions and the user's
                    // answers are facts too.
                    if hasUserMessage {
                        Button { onBuildPlan(photoImage) } label: {
                            Label("Build action plan", systemImage: "list.clipboard.fill")
                                .frame(maxWidth: .infinity, minHeight: 52)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(isWorking)
                        .accessibilityHint("Siaga turns the conversation into a brief, then builds the action plan.")
                    }

                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) { composer }
            .onChange(of: messages.count) { _, _ in scrollToBottom(proxy) }
            .onChange(of: streamingText) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
        }
    }

    // The composer is pinned to the bottom of the note screen, chat-style:
    // + menu on the left, Send on the right. It sits above Call 112,
    // which keeps its own bottom safe-area inset in ContentView.
    private var composer: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Attached photo lives INSIDE the input box, like a chat app:
            // a small thumbnail with a remove button, above the text.
            // It used to be a large preview card above the conversation —
            // in an emergency the composer is where the photo belongs.
            // A failed library load used to fail silently (try?) — now it
            // says so, here in the composer.
            if let photoImage {
                HStack(alignment: .top, spacing: 8) {
                    Image(uiImage: photoImage)
                        .resizable().scaledToFill().frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .accessibilityLabel("Attached photo")
                    Text("Photo stays on this phone. Siaga describes it on-device.")
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(.top, 4)
                    Spacer()
                    Button {
                        self.photoImage = nil
                        photoItem = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("Remove photo")
                }
                .padding(.horizontal, 8)
                .padding(.top, 8)
            }
            if let photoLoadError {
                Text(photoLoadError)
                    .font(.subheadline).foregroundStyle(.red)
                    .padding(.horizontal, 8)
                    .padding(.top, 8)
            }
            // A vertical-axis TextField grows with the text, like a chat
            // app: one line when empty, up to 5 lines, then it scrolls
            // inside. The old TextEditor sat at its max height even when
            // empty, so the box looked big before a word was typed.
            TextField("Type a message…", text: $draft, axis: .vertical)
                .focused($isComposerFocused)
                .lineLimit(1...5)
                .padding(8)
            HStack {
                // Camera and Library are one + button inside the input
                // box. The menu holds Camera and Library only.
                Menu {
                    Button { showCamera = true } label: {
                        Label("Take Photo", systemImage: "camera.fill")
                    }
                    Button { showLibrary = true } label: {
                        Label("Choose from Library", systemImage: "photo")
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Add photo")
                .sheet(isPresented: $showCamera) {
                    CameraPicker(image: $photoImage)
                }
                .photosPicker(isPresented: $showLibrary, selection: $photoItem, matching: .images)
                .onChange(of: photoItem) { _, newValue in
                    Task {
                        do {
                            if let data = try await newValue?.loadTransferable(type: Data.self),
                               let image = UIImage(data: data) {
                                photoImage = image
                                photoLoadError = nil
                            } else if newValue != nil {
                                photoLoadError = "Could not load that photo. Try another one."
                            }
                        } catch {
                            photoLoadError = "Could not load that photo. Try another one."
                        }
                    }
                }
                Spacer()
                Button(action: send) {
                    if isWorking {
                        ProgressView()
                            .frame(minWidth: 44, minHeight: 44)
                    } else {
                        Label("Send", systemImage: "arrow.up.circle.fill")
                            .font(.headline)
                            .frame(minHeight: 44)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isWorking)
                .accessibilityLabel("Send message")
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .accessibilityLabel("Message Siaga")
    }

    private func send() {
        let text = draft
        let image = photoImage
        draft = ""
        // Like a chat app: sending clears the composer, attachment included.
        photoImage = nil
        photoItem = nil
        // And the keyboard closes: the user reads the reply, they do not
        // type the next message straight away in an emergency.
        isComposerFocused = false
        onSend(text, image)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
    }

}

enum SampleNotes {
    struct Sample: Identifiable { var id: String { title }; let title: String; let text: String }
    static let all: [Sample] = [
        Sample(title: "Mother fell, bleeding", text: "My mother fell in the bathroom, she is bleeding from her head, she is awake but dizzy. We are at home in Bandung, no signal here."),
        Sample(title: "Heart attack, chest pain", text: "My father is clutching his chest, the pain is spreading to his left arm. He is sweating and short of breath. We are at home."),
        Sample(title: "Child choking", text: "My 5-year-old son is choking on a grape, he cannot breathe."),
        Sample(title: "Burn", text: "My wife burned her hand cooking, blistering, in pain."),
        Sample(title: "Allergic reaction", text: "My brother ate peanuts, his lips are swelling, difficulty breathing."),
        Sample(title: "Fainting", text: "My father fainted in the living room, now awake but confused."),
        Sample(title: "Sprain", text: "I sprained my ankle playing football, swollen, cannot walk."),
        Sample(title: "Unknown: car accident", text: "There was a car accident outside our house, one driver is not moving."),
        Sample(title: "Vague", text: "Help, something is wrong with my dad."),
    ]
}

// MARK: - Brief editor (editable, severity can be overridden — Q20)
//
// Was a full step (Review) until 21 Nov 2026. Now it opens as a sheet
// from the action plan's brief card: same editor, same corrections,
// one less screen between a panicked user and help.

struct BriefEditorView: View {
    @Binding var brief: EmergencyBrief
    var onBack: () -> Void
    var onContinue: () -> Void
    var continueLabel: String = "Continue — build the action plan"
    @State private var symptomsText = ""

    var body: some View {
        Form {
            Section {
                // HIG: the most important fact first, in its own visual
                // group, with a colour that means something at a glance.
                HStack {
                    SeverityBadge(severity: brief.severity)
                    Spacer()
                    Text(brief.situationCode.rawValue)
                        .font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                Text("Brief — check it before anything else")
            } footer: {
                Text("Siaga never invents details. Correct anything wrong here — the action plan uses exactly what you see.")
            }

            Section("What happened") {
                TextField("Title", text: $brief.situationTitle)
                TextField("Person", text: $brief.personName)
                TextField("What happened", text: $brief.whatHappened, axis: .vertical)
                TextField("Location", text: $brief.locationDescription)
            }

            Section("Severity") {
                // HIG: 2–5 mutually exclusive options belong in a
                // segmented control, not a menu — the choice stays visible.
                Picker("Severity", selection: $brief.severity) {
                    ForEach(Severity.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Severity")
                Picker("Situation", selection: $brief.situationCode) {
                    ForEach(SituationCode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                Stepper("People involved: \(brief.peopleInvolved)", value: $brief.peopleInvolved, in: 1...20)
                Toggle("Ambulance needed", isOn: $brief.needsAmbulance)
            }

            Section("Symptoms") {
                TextField("Symptoms, comma-separated", text: $symptomsText)
                    .onAppear { symptomsText = brief.symptoms.joined(separator: ", ") }
                    .onChange(of: symptomsText) { _, newValue in
                        brief.symptoms = newValue.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    }
            }

            if brief.severity == .high || brief.severity == .critical {
                Section {
                    Label("Severity is \(brief.severity.rawValue). Call 112 now — do not wait for the draft message.", systemImage: "phone.fill")
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button("Back", action: onBack)
                    .frame(minHeight: 44)
                Button(continueLabel, action: onContinue)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }
}

// MARK: - Step 2: Action plan (tools, draft, handover)

struct ActionPlanView: View {
    let store: SiagaStore
    let agent: SiagaAgent?
    var brief: Binding<EmergencyBrief?>
    @Binding var draftApproved: Bool
    var onNewIncident: () -> Void
    @State private var draftCopied = false
    @State private var showBriefEditor = false

    // Opens Messages with the draft pre-filled to the emergency contact.
    // Nothing is sent by the app — the user taps Send in Messages, or
    // sends nothing at all. In Airplane Mode the compose sheet still
    // opens; sending waits for signal, which is honest, not a fake send.
    private func smsURL(for draft: String) -> URL? {
        guard let phone = store.lastProfile?.emergencyContactPhone else { return nil }
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        guard let body = draft.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        return URL(string: "sms:\(digits)&body=\(body)")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Action plan")
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
                Text("Everything below comes from tools and pre-approved steps — not from the model's imagination.")
                    .font(.body).foregroundStyle(.secondary)

                // 21 Nov 2026: buildActionPlan can fail (e.g. a capability
                // the model does not support) and the plan screen used to
                // show nothing at all — a silent failure. The error now
                // shows here, in red, with what it means.
                if let problem = agent?.problem {
                    Text(problem).font(.subheadline).foregroundStyle(.red)
                }

                // The brief lives here now that Review is not a separate
                // step. The user sees what Siaga understood at the top of
                // the plan — and can still correct it. Saving rebuilds
                // the plan from the corrected brief.
                if let briefValue = brief.wrappedValue {
                    SiagaCard(icon: "doc.text.fill", title: "Brief — what Siaga understood", tint: .blue) {
                        HStack {
                            SeverityBadge(severity: briefValue.severity)
                            Spacer()
                            Text(briefValue.situationCode.rawValue)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Text(briefValue.situationTitle).font(.headline)
                        Text("\(briefValue.personName) • \(briefValue.locationDescription)")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Text(briefValue.whatHappened).font(.body)
                        Button("Edit brief") { showBriefEditor = true }
                            .buttonStyle(.bordered)
                            .frame(minHeight: 44)
                    }
                    .sheet(isPresented: $showBriefEditor) {
                        if let briefBinding = Binding(brief) {
                            NavigationStack {
                                BriefEditorView(
                                    brief: briefBinding,
                                    onBack: { showBriefEditor = false },
                                    onContinue: {
                                        showBriefEditor = false
                                        store.currentBrief = brief.wrappedValue
                                        draftApproved = false
                                        draftCopied = false
                                        Task { await agent?.buildActionPlan() }
                                    },
                                    continueLabel: "Save — rebuild the plan"
                                )
                                .navigationTitle("Edit brief")
                                .navigationBarTitleDisplayMode(.inline)
                            }
                        }
                    }
                }

                if agent?.isWorking == true {
                    SiagaCard(icon: "brain.head.profile", title: "Siaga is working") {
                        ProgressView()
                        if let text = agent?.streamingText, !text.isEmpty {
                            Text(text).font(.body).foregroundStyle(.secondary)
                        }
                    }
                }
                if !store.actions.isEmpty {
                    SiagaCard(icon: "checkmark.circle.fill", title: "What Siaga did", tint: .green) {
                        // Same alignment problem as the label rows below:
                        // a plain "• text" wraps under the bullet. The
                        // bullet gets its own column, the text its own.
                        ForEach(store.actions, id: \.self) { action in
                            HStack(alignment: .top, spacing: 8) {
                                Text("•").font(.body)
                                Text(action).font(.body)
                            }
                        }
                    }
                }
                if let firstAid = store.lastFirstAid {
                    SiagaCard(icon: "cross.case.fill", title: "First aid: \(firstAid.title)", tint: .red) {
                        ForEach(Array(firstAid.steps.enumerated()), id: \.offset) { index, step in
                            HStack(alignment: .top, spacing: 8) {
                                Text("\(index + 1).").font(.body.bold())
                                Text(step).font(.body)
                            }
                        }
                    }
                }
                if let profile = store.lastProfile {
                    SiagaCard(icon: "person.fill", title: "Medical profile", tint: .blue) {
                        Text(profile.summary).font(.body)
                    }
                }
                if let draft = store.lastDraft {
                    SiagaCard(icon: "message.fill", title: "Draft message to send", tint: .orange) {
                        // UX fix 21 Nov 2026: the draft never said WHO it is
                        // for. It is an SMS to the family emergency contact
                        // from the selected profile — never to 112, and
                        // Siaga never sends it. The recipient line makes
                        // that unmistakable at a glance.
                        if let profile = store.lastProfile {
                            Label("To: \(profile.emergencyContactName) (\(profile.emergencyContactRelation)) • \(profile.emergencyContactPhone)", systemImage: "person.fill")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        Text("SMS draft for the family emergency contact — not for 112. Siaga only writes it; you send it from Messages.")
                            .font(.caption).foregroundStyle(.secondary)
                        // The draft reads as aligned rows, not one block
                        // of text: same content Copy sends (the plain
                        // string), laid out so wrapped lines stay under
                        // their value. The header and footer lines are
                        // short enough to stand on their own.
                        if let brief = store.currentBrief {
                            Text("EMERGENCY — \(brief.situationTitle)").font(.headline)
                        }
                        if store.draftRows.isEmpty {
                            Text(draft).font(.body)
                        } else {
                            LabeledRows(rows: store.draftRows)
                        }
                        if let personName = store.currentBrief?.personName {
                            Text("Please call 112 if you get this. I am with \(personName) now.").font(.body)
                        }
                        Text("— Sent from Siaga (draft, not sent yet)").font(.caption).foregroundStyle(.secondary)
                        // UX 21 Nov 2026: "Approve" did nothing useful —
                        // the draft's whole point is leaving this app. So
                        // the actions are Copy (paste it anywhere) and Open
                        // in Messages (pre-filled SMS to the contact).
                        // Either one counts as the user acting on the draft.
                        Button(draftCopied ? "Copied" : "Copy draft") {
                            UIPasteboard.general.string = draft
                            draftCopied = true
                            draftApproved = true
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .accessibilityHint("Copies the draft message so you can paste it into Messages.")
                        if let url = smsURL(for: draft) {
                            Button {
                                draftApproved = true
                                UIApplication.shared.open(url)
                            } label: {
                                Label("Open in Messages", systemImage: "message.fill")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity, minHeight: 52)
                            }
                            .buttonStyle(.bordered)
                            .accessibilityHint("Opens Messages with the draft pre-filled to the emergency contact. Nothing is sent until you tap Send there.")
                        }
                        Text("Copy it into Messages, or open it there directly. Siaga never sends it by itself.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .sensoryFeedback(.success, trigger: draftApproved)
                    .sensoryFeedback(.success, trigger: draftCopied)
                }
                if let handover = store.lastHandover {
                    SiagaCard(icon: "doc.text.fill", title: "Handover for paramedics", tint: .purple) {
                        if let brief = store.currentBrief {
                            Text("HANDOVER FOR PARAMEDICS — \(brief.situationTitle)").font(.headline)
                        }
                        let rows = store.handoverRows(includeStepsTaken: true)
                        if rows.isEmpty {
                            Text(handover).font(.body)
                        } else {
                            LabeledRows(rows: rows)
                        }
                    }
                }
                if let imageDescription = agent?.imageDescription {
                    SiagaCard(icon: "photo.fill", title: "Photo — described on-device", tint: .teal) {
                        Text(imageDescription).font(.body)
                    }
                }
                if let usage = store.lastTokenUsage {
                    Text(usage).font(.caption).foregroundStyle(.secondary)
                }
                Button("New incident", action: onNewIncident)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }
}

// MARK: - History, grouped by severity
//
// FIXED 21 Nov 2026: the sectioned @Query did not compile in Xcode 27 —
// `init(filter:sort:order:transaction:sectionBy:)` requires the property
// type to be SectionedResults, not [IncidentHistory]. History is now a
// plain @Query, grouped in Swift by the persisted severityName String.
// Same sections on screen, no sectionBy API involved.

struct HistoryView: View {
    @Query(sort: \IncidentHistory.createdAt, order: .reverse) private var history: [IncidentHistory]

    private var grouped: [(key: String, items: [IncidentHistory])] {
        Dictionary(grouping: history, by: \.severityName)
            .sorted { $0.key < $1.key }
            .map { (key: $0.key, items: $0.value) }
    }

    var body: some View {
        Group {
            if history.isEmpty {
                // HIG: an empty list is never a blank screen. Say why it
                // is empty and what to do next.
                ContentUnavailableView(
                    "No incidents yet",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Incidents you analyse will appear here, grouped by severity.")
                )
            } else {
                List {
                    ForEach(grouped, id: \.key) { group in
                        Section(group.key) {
                            ForEach(group.items) { incident in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(incident.snapshot.title).font(.headline)
                                    Text("\(incident.snapshot.personName) • \(incident.snapshot.situationCode) • \(incident.createdAt.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.subheadline).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.large)
    }
}

// MARK: - Profiles (CRUD — this is what makes Siaga usable for a real family)
//
// The 3 seeded profiles (Sari / Agus / Budi) are DEMO DATA ONLY, from the
// grilling rounds. They exist so the hackathon demo works out of the box.
// A real user deletes them and adds their own family here. Deleting is a
// swipe, adding is one form. No name is ever hardcoded anywhere else in
// the app: the note screen picks from this list, the agent is told the
// selected profile by name, and lookupProfile returns nil — never the
// first profile — when nothing matches.

struct ProfilesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [MedicalProfile]
    @State private var editing: MedicalProfile?
    @State private var adding = false

    var body: some View {
        Group {
            if profiles.isEmpty {
                ContentUnavailableView(
                    "No family profiles",
                    systemImage: "person.2.fill",
                    description: Text("Add the people Siaga should know about — allergies, medication and emergency contact.")
                )
            } else {
                List {
                    Section {
                        Text("These are your family profiles. Siaga uses the allergy, medication and emergency contact from the profile you pick on the note screen. Delete these profiles and add your own family.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Section("Family") {
                        ForEach(profiles) { profile in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(profile.name).font(.headline)
                                Text(profile.summary).font(.subheadline).foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { editing = profile }
                            .accessibilityHint("Double tap to edit this profile.")
                        }
                        .onDelete { offsets in
                            for index in offsets { modelContext.delete(profiles[index]) }
                            try? modelContext.save()
                        }
                    }
                }
            }
        }
        .navigationTitle("Profiles")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { adding = true } label: {
                    Label("Add", systemImage: "plus")
                }
                .accessibilityLabel("Add profile")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
        .sheet(isPresented: $adding) {
            NavigationStack { ProfileFormView(profile: nil) }
        }
        .sheet(item: $editing) { profile in
            NavigationStack { ProfileFormView(profile: profile) }
        }
    }
}

struct ProfileFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let profile: MedicalProfile?

    @State private var name = ""
    // Age is a String, not an Int: it used to be a Stepper, which cannot
    // be typed at all (21 Nov 2026, Arief). A TextField with a number
    // pad lets the user type the age; save() parses it back.
    @State private var ageText = "65"
    @State private var bloodType = "O+"
    @State private var allergies = "None"
    @State private var medications = "None"
    @State private var contactName = ""
    @State private var contactRelation = "Family"
    @State private var contactPhone = ""
    // The number pad has no Return key, so the keyboard needs its own
    // Done button — otherwise the user cannot dismiss it.
    @FocusState private var isAgeFocused: Bool

    var body: some View {
        Form {
            Section("Person") {
                TextField("Full name", text: $name)
                    .textContentType(.name)
                TextField("Age", text: $ageText)
                    .keyboardType(.numberPad)
                    .focused($isAgeFocused)
                    .toolbar {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button("Done") { isAgeFocused = false }
                        }
                    }
                Picker("Blood type", selection: $bloodType) {
                    ForEach(["O+", "O-", "A+", "A-", "B+", "B-", "AB+", "AB-", "Unknown"], id: \.self) { Text($0) }
                }
                TextField("Allergies (or None)", text: $allergies)
                TextField("Medications (or None)", text: $medications)
            }
            Section("Emergency contact") {
                TextField("Contact name", text: $contactName)
                    .textContentType(.name)
                TextField("Relation", text: $contactRelation)
                TextField("Phone", text: $contactPhone)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
            }
            Section {
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || contactName.trimmingCharacters(in: .whitespaces).isEmpty)
            } footer: {
                Text("Profiles stay on this phone. Siaga never uploads them.")
            }
        }
        .navigationTitle(profile == nil ? "Add profile" : "Edit profile")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            if let profile {
                name = profile.name; ageText = String(profile.age); bloodType = profile.bloodType
                allergies = profile.allergies; medications = profile.medications
                contactName = profile.emergencyContactName; contactRelation = profile.emergencyContactRelation
                contactPhone = profile.emergencyContactPhone
            }
        }
    }

    private func save() {
        // Non-numeric or empty input keeps the existing age (or 65 for a
        // new profile); anything outside 0...120 is clamped.
        let parsedAge = min(max(Int(ageText.trimmingCharacters(in: .whitespaces)) ?? profile?.age ?? 65, 0), 120)
        if let profile {
            profile.name = name; profile.age = parsedAge; profile.bloodType = bloodType
            profile.allergies = allergies; profile.medications = medications
            profile.emergencyContactName = contactName; profile.emergencyContactRelation = contactRelation
            profile.emergencyContactPhone = contactPhone
        } else {
            modelContext.insert(MedicalProfile(name: name, age: parsedAge, bloodType: bloodType, allergies: allergies, medications: medications, emergencyContactName: contactName, emergencyContactRelation: contactRelation, emergencyContactPhone: contactPhone))
        }
        try? modelContext.save()
        dismiss()
    }
}
