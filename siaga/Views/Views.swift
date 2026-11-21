import SwiftUI
import SwiftData
import PhotosUI

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

enum SiagaStep: Int, CaseIterable {
    case note = 1, brief, plan
    var title: String {
        switch self {
        case .note: return "Describe"
        case .brief: return "Review"
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
    @State private var note = ""
    @State private var draftBrief: EmergencyBrief?
    @State private var draftApproved = false
    @State private var showHistory = false
    @State private var showProfiles = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // HIG: orient the user. A 3-step flow always shows where
                // they are, so a panicked user never wonders what is next.
                StepProgressView(current: step)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                switch step {
                case .note:
                    EmergencyNoteView(
                        note: $note,
                        profiles: profiles,
                        selectedProfile: $store.selectedProfile,
                        isWorking: agent?.isWorking ?? false,
                        problem: agent?.problem,
                        fallbackUsed: agent?.fallbackUsed ?? false,
                        onAnalyse: { image in
                            Task {
                                if let brief = await agent?.analyse(note: note, image: image) {
                                    draftBrief = brief
                                    step = .brief
                                }
                            }
                        }
                    )
                case .brief:
                    if let briefBinding = Binding($draftBrief) {
                        BriefEditorView(
                            brief: briefBinding,
                            onBack: { step = .note },
                            onContinue: {
                                store.currentBrief = draftBrief
                                if let brief = draftBrief {
                                    let incident = IncidentHistory(brief: brief)
                                    modelContext.insert(incident)
                                    try? modelContext.save()
                                    SiagaSpotlightIndexer.indexIncident(incident)
                                }
                                step = .plan
                                Task { await agent?.buildActionPlan() }
                            }
                        )
                    }
                case .plan:
                    ActionPlanView(
                        store: store,
                        agent: agent,
                        draftApproved: $draftApproved,
                        onNewIncident: {
                            agent?.newIncident()
                            note = ""
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

// MARK: - Step progress (HIG: orientation)

struct StepProgressView: View {
    var current: SiagaStep

    var body: some View {
        HStack(spacing: 8) {
            ForEach(SiagaStep.allCases, id: \.self) { step in
                HStack(spacing: 6) {
                    Image(systemName: step.rawValue < current.rawValue ? "checkmark.circle.fill" : "\(step.rawValue).circle.fill")
                        .foregroundStyle(step == current ? Color.accentColor : Color.secondary)
                    Text("Step \(step.rawValue): \(step.title)")
                        .font(.caption.weight(step == current ? .semibold : .regular))
                        .foregroundStyle(step == current ? .primary : .secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Step \(step.rawValue) of 3: \(step.title)\(step == current ? ", current step" : "")")
                if step != .plan { Spacer(minLength: 4) }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Always-on header

struct OnDeviceBadge: View {
    var body: some View {
        Label("On-Device • Offline", systemImage: "wifi.slash")
            .font(.caption.bold())
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(.green.opacity(0.15), in: Capsule())
            .foregroundStyle(.green)
            .accessibilityLabel("On-device, offline. Nothing leaves this phone.")
    }
}

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

// MARK: - Step 1: Emergency note

struct EmergencyNoteView: View {
    @Binding var note: String
    var profiles: [MedicalProfile]
    @Binding var selectedProfile: MedicalProfile?
    var isWorking: Bool
    var problem: String?
    var fallbackUsed: Bool
    var onAnalyse: (UIImage?) -> Void
    @State private var photoItem: PhotosPickerItem?
    @State private var photoImage: UIImage?
    @State private var showCamera = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // HIG hierarchy: one large title, one short explanation.
                // The badge proves the offline claim at a glance.
                HStack {
                    OnDeviceBadge()
                    Spacer()
                }
                Text("What happened?")
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
                Text("Type or dictate it in your own words. Siaga turns it into a brief, checks the medical profile and first-aid steps, and drafts a message. Nothing leaves this phone.")
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
                        Text("No profile selected. Siaga will still build a brief, draft a message and show first-aid steps — but without allergy or contact details. Pick a profile above for the full flow.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }

                // HIG: a text field shows its purpose even when empty.
                // TextEditor has no placeholder, so one is drawn over it.
                VStack(alignment: .leading, spacing: 8) {
                    Text("Describe what happened")
                        .font(.headline)
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $note)
                            .frame(minHeight: 140)
                            .scrollContentBackground(.hidden)
                            .padding(8)
                        if note.isEmpty {
                            Text("Example: My mother fell in the bathroom, she is bleeding from her head, she is awake but dizzy.")
                                .font(.body)
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 16)
                                .allowsHitTesting(false)
                        }
                    }
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
                    .accessibilityLabel("Describe what happened")
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Photo (optional)").font(.headline)
                    HStack(spacing: 12) {
                        Button { showCamera = true } label: {
                            Label("Camera", systemImage: "camera.fill")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            Label("Library", systemImage: "photo")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                    }
                    .sheet(isPresented: $showCamera) {
                        CameraPicker(image: $photoImage)
                    }
                    .onChange(of: photoItem) { _, newValue in
                        Task {
                            if let data = try? await newValue?.loadTransferable(type: Data.self),
                               let image = UIImage(data: data) {
                                photoImage = image
                            }
                        }
                    }
                    // Bundled samples: one tap, image loads directly.
                    // Each sample also fills the matching note, so the demo
                    // is one tap, not type-then-pick-then-analyse.
                    ForEach(SamplePhoto.allCases) { sample in
                        Button {
                            photoImage = sample.load()
                            note = sample.note
                        } label: {
                            Label(sample.title, systemImage: sample.systemImage)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .frame(minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                    }
                    if let photoImage {
                        Image(uiImage: photoImage)
                            .resizable().scaledToFit().frame(maxHeight: 180)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .accessibilityLabel("Attached photo")
                        Text("Photo stays on this phone. Siaga describes it on-device.")
                            .font(.caption).foregroundStyle(.secondary)
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

                // HIG: one primary action per screen, large and unmistakable.
                Button(action: { onAnalyse(photoImage) }) {
                    if isWorking {
                        ProgressView("Siaga is working…")
                            .frame(maxWidth: .infinity, minHeight: 52)
                    } else {
                        Text("Analyse — build the brief")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 52)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isWorking)
                .accessibilityLabel("Analyse, build the brief")
                .accessibilityHint("Siaga reads your note on-device and builds a structured emergency brief.")

                VStack(alignment: .leading, spacing: 12) {
                    Text("Try a sample")
                        .font(.headline)
                    ForEach(SampleNotes.all, id: \.title) { sample in
                        Button(sample.title) { note = sample.text }
                            .buttonStyle(.bordered)
                            .frame(minHeight: 44)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .scrollDismissesKeyboard(.interactively)
    }
}

enum SampleNotes {
    struct Sample: Identifiable { var id: String { title }; let title: String; let text: String }
    static let all: [Sample] = [
        Sample(title: "Mother fell, bleeding", text: "My mother fell in the bathroom, she is bleeding from her head, she is awake but dizzy. We are at home in Bandung, no signal here."),
        Sample(title: "Child choking", text: "My 5-year-old son is choking on a grape, he cannot breathe."),
        Sample(title: "Burn", text: "My wife burned her hand cooking, blistering, in pain."),
        Sample(title: "Allergic reaction", text: "My brother ate peanuts, his lips are swelling, difficulty breathing."),
        Sample(title: "Fainting", text: "My father fainted in the living room, now awake but confused."),
        Sample(title: "Sprain", text: "I sprained my ankle playing football, swollen, cannot walk."),
        Sample(title: "Unknown: car accident", text: "There was a car accident outside our house, one driver is not moving."),
        Sample(title: "Vague", text: "Help, something is wrong with my dad."),
    ]
}

// MARK: - Step 2: Brief review (editable, severity can be overridden — Q20)

struct BriefEditorView: View {
    @Binding var brief: EmergencyBrief
    var onBack: () -> Void
    var onContinue: () -> Void
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
                Button("Continue — build the action plan", action: onContinue)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }
}

// MARK: - Step 3: Action plan (tools, draft approval, handover)

struct ActionPlanView: View {
    let store: SiagaStore
    let agent: SiagaAgent?
    @Binding var draftApproved: Bool
    var onNewIncident: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Action plan")
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
                Text("Everything below comes from tools and pre-approved steps — not from the model's imagination. Review it, then approve the draft.")
                    .font(.body).foregroundStyle(.secondary)

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
                        ForEach(store.actions, id: \.self) { Text("• \($0)").font(.body) }
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
                    SiagaCard(icon: "message.fill", title: "Draft message — needs your approval", tint: .orange) {
                        Text(draft).font(.body)
                        Button(draftApproved ? "Approved — not sent" : "Approve draft") {
                            draftApproved = true
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .disabled(draftApproved)
                        .accessibilityHint("Approving only marks the draft as reviewed. Siaga never sends it by itself.")
                        Text("Approving only marks the draft as reviewed. Siaga never sends it by itself.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .sensoryFeedback(.success, trigger: draftApproved)
                }
                if let handover = store.lastHandover {
                    SiagaCard(icon: "doc.text.fill", title: "Handover for paramedics", tint: .purple) {
                        Text(handover).font(.body)
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
    @State private var age = 65
    @State private var bloodType = "O+"
    @State private var allergies = "None"
    @State private var medications = "None"
    @State private var contactName = ""
    @State private var contactRelation = "Family"
    @State private var contactPhone = ""

    var body: some View {
        Form {
            Section("Person") {
                TextField("Full name", text: $name)
                    .textContentType(.name)
                Stepper("Age: \(age)", value: $age, in: 0...120)
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
                name = profile.name; age = profile.age; bloodType = profile.bloodType
                allergies = profile.allergies; medications = profile.medications
                contactName = profile.emergencyContactName; contactRelation = profile.emergencyContactRelation
                contactPhone = profile.emergencyContactPhone
            }
        }
    }

    private func save() {
        if let profile {
            profile.name = name; profile.age = age; profile.bloodType = bloodType
            profile.allergies = allergies; profile.medications = medications
            profile.emergencyContactName = contactName; profile.emergencyContactRelation = contactRelation
            profile.emergencyContactPhone = contactPhone
        } else {
            modelContext.insert(MedicalProfile(name: name, age: age, bloodType: bloodType, allergies: allergies, medications: medications, emergencyContactName: contactName, emergencyContactRelation: contactRelation, emergencyContactPhone: contactPhone))
        }
        try? modelContext.save()
        dismiss()
    }
}
