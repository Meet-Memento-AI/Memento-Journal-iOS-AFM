//
//  AddEntryView.swift
//  MeetMemento
//
//  Notion-style full-page journal entry editor with title and body fields.
//  A cover photo becomes a full-bleed max-blur backdrop (Figma 818:4006).
//  Capture (mic left, camera CTA right) matches 818:3843; the header lens
//  toggle and the revealed cover match 898:1784 / 824:4211.
//

import SwiftUI
import PhotosUI
import AVFoundation
import UIKit

// MARK: - Entry State

public enum EntryState: Hashable {
    case create                                          // Regular journal entry
    case createWithTitle(String)                         // Create with pre-filled title
    case createWithContent(title: String, content: String) // Create with pre-filled title and content (e.g., from chat summary)
    case edit(Entry)                                     // Existing entry (opens in view)
}

public struct AddEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// False once `EntryEditorPager` has swiped this page off screen. Always
    /// true outside the pager (create routes, previews), so nothing here
    /// changes for them.
    @Environment(\.editorPageIsActive) private var isActivePage

    /// Deliberately *not* observed. `EditorDictationPill` owns the dictation
    /// session and the observation that goes with it; the editor only reaches
    /// in to abandon a session on save or dismiss. Observing here re-rendered
    /// the whole page — backdrop, glass, body editor — on every one of the
    /// service's ~50 publishes per second while recording.
    private var speechService: SpeechService { .shared }

    /// Unique identifier for this view's speech session ownership
    private let speechOwnerId = "AddEntryView"

    @StateObject private var keyboardObserver = KeyboardObserver()

    @State private var title: String
    @State private var text: String
    @State private var isSaving = false
    /// Writable session for an existing entry. Create routes ignore this.
    /// Existing entries open `false` (view) and the pencil sets it `true`.
    @State private var isEditingExisting = false
    /// In-place save confirmation. Create still uses the journal-list toast.
    @State private var showEditCompleteToast = false
    /// Last values written through `onSave`. `commitPendingEdits` and
    /// in-place save compare against these so a later pager swipe does not
    /// rewrite `updatedAt` after the user already saved.
    @State private var lastSavedTitle: String
    @State private var lastSavedText: String
    @State private var lastSavedHadPhoto: Bool

    // MARK: Photo state
    @State private var photoData: Data?
    @State private var photoPreviewImage: UIImage?
    /// Downsampled average of the cover, used to adapt editor scrim/blur.
    @State private var photoSample: JournalBackdropSample?
    /// False until the user actually touches the photo this session — lets
    /// `.edit(entry)` preselect an existing photo without `save()` treating
    /// that preselection itself as a change.
    @State private var photoDidChange = false
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var showCameraCapture = false
    @State private var showCameraUnavailable = false
    @State private var showCameraPermissionDenied = false
    @State private var showCaptureOptions = false
    @State private var showLibraryPicker = false
    /// The cover shown untreated (Figma 824:4211). Not a separate screen: the
    /// editor's own backdrop dissolves its shader away, so every piece of
    /// chrome stays mounted and the page never unmounts.
    @State private var isViewingMemory = false
    /// Full-resolution cover, mounted only while `shaderRevealProgress < 1`.
    /// The always-present sharp layer is the list thumbnail so the zoom into
    /// the editor never samples a 1600px texture; a revealed memory still
    /// has to be the real photo, not an 800px thumbnail blown up.
    @State private var untreatedPhotoImage: UIImage?
    /// `editorDefaults` blur + saturation baked into one small bitmap by
    /// `JournalBackdropRenderer`, off-main. Nil until rendered; the sharp
    /// cover plus scrim shows meanwhile. Never a live `.blur` — that filter
    /// re-ran every frame of the zoom under four glass surfaces and stalled
    /// the editor on device.
    @State private var treatedPhotoImage: UIImage?
    /// Serial for treated renders so a stale one cannot land over a newer photo.
    @State private var treatedRenderToken = 0
    /// 0 = sharp cover, 1 = full treatment (opacity of `treatedPhotoImage`
    /// and the scrim). Animated after a pick, and driven to 0 and back by
    /// the header lens toggle. Never a transform — an animated `scaleEffect`
    /// on this layer stalled the editor on device the same way a live blur did.
    @State private var shaderRevealProgress: CGFloat = 0
    /// Everything that belongs to the entry rather than the photo: title,
    /// body, the save arrow and the mic. Held at 0 until the shader lands
    /// (Figma sequence: photo → shader → type) and while a memory is revealed.
    @State private var entryContentOpacity: Double = 1

    /// In-flight reduced-accuracy reverse geocode for new entries. Started
    /// when the editor appears so permission + lookup run ahead of save.
    /// No pin or tag — the string is persisted only.
    @State private var placePrefetch: Task<String?, Never>?
    @State private var resolvedPlaceName: String?
    /// Capture-only shader sequence. Cancelled on dismiss so the text-fade
    /// completion cannot start a second transaction after zoom-out.
    @State private var shaderRevealTask: Task<Void, Never>?

    @FocusState private var focusedField: Field?

    enum Field: Hashable {
        case title
        case body
    }

    let state: EntryState
    let onSave: (_ title: String, _ text: String, _ photoAction: PhotoAction, _ locationAction: LocationAction) -> Void

    public init(
        state: EntryState,
        onSave: @escaping (_ title: String, _ text: String, _ photoAction: PhotoAction, _ locationAction: LocationAction) -> Void
    ) {
        self.state = state
        self.onSave = onSave

        // Initialize title and text based on state
        switch state {
        case .create:
            _title = State(initialValue: "")
            _text = State(initialValue: "")
            _lastSavedTitle = State(initialValue: "")
            _lastSavedText = State(initialValue: "")
            _lastSavedHadPhoto = State(initialValue: false)
        case .createWithTitle(let prefillTitle):
            _title = State(initialValue: prefillTitle)
            _text = State(initialValue: "")
            _lastSavedTitle = State(initialValue: prefillTitle)
            _lastSavedText = State(initialValue: "")
            _lastSavedHadPhoto = State(initialValue: false)
        case .createWithContent(let prefillTitle, let prefillContent):
            _title = State(initialValue: prefillTitle)
            _text = State(initialValue: prefillContent)
            _lastSavedTitle = State(initialValue: prefillTitle)
            _lastSavedText = State(initialValue: prefillContent)
            _lastSavedHadPhoto = State(initialValue: false)
        case .edit(let entry):
            _title = State(initialValue: entry.title)
            _text = State(initialValue: entry.text)
            _lastSavedTitle = State(initialValue: entry.title)
            _lastSavedText = State(initialValue: entry.text)
            _lastSavedHadPhoto = State(initialValue: entry.hasPhoto)
        }
    }

    // MARK: - Computed Properties

    private var editingEntry: Entry? {
        if case .edit(let entry) = state { return entry }
        return nil
    }

    /// New entry — always the writable composer.
    private var isComposing: Bool { editingEntry == nil }

    /// Existing entry, read-only chrome (pencil, header lens).
    private var isViewingExisting: Bool { editingEntry != nil && !isEditingExisting }

    /// Existing entry after the pencil — mic + Capture, save stays on page.

    /// What to report to `onSave` — computed from the session's photo state,
    /// not diffed against `Data`, since the explicit `photoDidChange` flag is
    /// cheap and unambiguous (see `PhotoAction`'s doc comment).
    private var photoAction: PhotoAction {
        guard photoDidChange else { return .unchanged }
        if let photoData { return .set(photoData) }
        return .removed
    }

    private var hasCoverPhoto: Bool { photoPreviewImage != nil }

    /// Ink on Liquid Glass chrome. Black in light, white in dark — same
    /// as Journal / Chat — including over a cover. Title and body still
    /// use `titleForeground` (white on a treated photo).
    private var chromeForeground: Color { theme.foreground }

    private var titleForeground: Color {
        hasCoverPhoto ? BaseColors.white : theme.foreground
    }

    /// Filled body is 60% of the title color (Figma 818:3925 / 818:4006).
    private var bodyForeground: Color { titleForeground.opacity(0.6) }

    private var titlePlaceholderColor: Color { titleForeground.opacity(0.25) }

    private var bodyPlaceholderColor: Color { titleForeground.opacity(0.25) }

    /// Editor body (Figma body1): Figtree Medium 18 / 24 line box.
    private var editorBodyLineSpacing: CGFloat {
        type.extraLineSpacing(for: 18, lineHeight: 24)
    }

    /// View ⇄ edit chrome (footer, pencil/check). Title and body must not
    /// use this — they are the same string in two representations, and a
    /// crossfade stacks them for the duration of the spring.
    private static let modeTransition = Animation.spring(response: 0.45, dampingFraction: 0.88)

    /// Idle mic and Capture: 56pt minimum, width hugs content.
    private static let shaderRevealDuration: Double = 0.7
    private static let textRevealDuration: Double = 0.35
    private static let captureLabelGap: CGFloat = 8
    private static let capturePadding: CGFloat = 16

    /// How long the shader takes to dissolve off the cover, and back on.
    /// Longer than `shaderRevealDuration` on purpose: a capture reveal is the
    /// tail of a modal flow, this one is the whole gesture.
    private static let memoryRevealDuration: Double = 0.85
    /// Entry-only surfaces (type, save, mic) leaving or arriving.
    private static let memoryChromeFadeDuration: Double = 0.28
    /// The shader starts a beat after the type does, so the two overlap into
    /// one move instead of reading as two sequential steps.
    private static let memoryChromeFadeDelay: Double = 0.12
    /// Decelerating rather than symmetric: the blur should settle into place.
    private static var memoryRevealCurve: Animation {
        .timingCurve(0.22, 0.61, 0.36, 1, duration: memoryRevealDuration)
    }

    /// Resting: `windowBottom + 16`, same as Journal FAB / Chat composer.
    /// Keyboard up: 16pt above the keys. Applied *outside* the glass
    /// container — insets around `glassEffect` are ignored under
    /// `.ignoresSafeArea()`.
    private var keyboardBottomPadding: CGFloat {
        guard keyboardObserver.isKeyboardVisible else {
            return AppHeaderMetrics.windowBottom + AppHeaderMetrics.rowBottomPadding
        }
        return max(keyboardObserver.keyboardHeight - AppHeaderMetrics.windowBottom, 0)
            + AppHeaderMetrics.rowBottomPadding
    }

    /// Scroll content sits this far above the physical bottom so the last
    /// line of body text cannot crowd the footer FABs. Keyboard up: the
    /// same 16pt `contentGap` as rest, just measured from the lifted chrome.
    private var editorScrollBottomMargin: CGFloat {
        guard !isViewingExisting else { return 0 }
        return keyboardBottomPadding
            + AppHeaderMetrics.footerButtonSize
            + AppHeaderMetrics.contentGap
    }

    public var body: some View {
        // GeometryReader is the size: a plain VStack in a zooming
        // NavigationStack destination is proposed the source rect first (the
        // 64pt FAB) and can collapse to an empty white page. The reader
        // always fills whatever size the transition offers, then the screen.
        GeometryReader { _ in
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    titleField
                    bodyField
                }
                .padding(.top, AppHeaderMetrics.headerClearance + Spacing.xxl)
                .padding(.horizontal, AppHeaderMetrics.edgeInset)
                .opacity(hasCoverPhoto ? entryContentOpacity : 1)
                // Title and body are one field in both modes so glyphs do not
                // jump. Chrome still springs via `modeTransition`.
                .transaction(value: isViewingExisting) { $0.animation = nil }
            }
            .contentMargins(.bottom, editorScrollBottomMargin, for: .scrollContent)
            .scrollDismissesKeyboard(.interactively)
            .scrollEdgeEffectHidden(true, for: .top)
            .scrollEdgeEffectHidden(true, for: .bottom)
            // Scoped to the scroller, NOT the chrome: on the stack this hid
            // the chevron from VoiceOver whenever a memory was up.
            .accessibilityHidden(isViewingMemory)
            .allowsHitTesting(!isViewingMemory)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .overlay(alignment: .top) {
                // Floating glass only — no blur plate. Type scrolls under
                // the buttons the same way Journal/Chat headers work.
                pageHeader
            }
            .overlay(alignment: .bottom) {
                VStack(spacing: 12) {
                    if showEditCompleteToast {
                        JournalToast(message: "Edits saved") {
                            withAccessibleAnimation(Self.modeTransition, reduceMotion: reduceMotion) {
                                showEditCompleteToast = false
                            }
                        }
                        .padding(.bottom, isViewingExisting ? keyboardBottomPadding : 0)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    footerFABs
                }
                .accessibleAnimation(Self.modeTransition, value: showEditCompleteToast)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            // The fill has to ignore the safe area *itself*. `.ignoresSafeArea()`
            // on this view expands the chrome, but a `.background` child still
            // lays out in the inset rect — which is the white strip above the
            // Dynamic Island (the navigation container's default plate).
            editorFill.ignoresSafeArea()
        }
        .containerBackground(for: .navigation) {
            editorFill
        }
        .ignoresSafeArea()
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        // NO `.accessibilityIdentifier` on this root. A container identifier
        // overwrites the identifier of every SwiftUI-native descendant — the
        // header buttons, the mic and photo controls all reported
        // `journal.entryEditor` instead of their own ids, so `.back` and `.save`
        // never matched and both EntryZoomPageUITests failed. (Only the
        // UIKit-backed `.title`/`.body` fields survived it, because those set
        // the identifier on the underlying UIView.) Probe for "editor is up"
        // with `journal.entryEditor.back` instead.
        .task {
            await preloadExistingPhotoIfNeeded()
            startPlacePrefetchIfNeeded()
        }
        .onChange(of: photoPickerItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: data) {
                    handleNewPhoto(uiImage)
                }
                photoPickerItem = nil
            }
        }
        .confirmationDialog("Capture", isPresented: $showCaptureOptions, titleVisibility: .hidden) {
            Button("Take Photo") {
                presentCameraOrHandleUnavailable()
            }
            Button("Choose from Library") {
                showLibraryPicker = true
            }
            Button("Cancel", role: .cancel) {}
        }
        // Attach PhotosUI only when the library sheet is requested. The
        // modifier on the editor root was initializing PhotoKit during the
        // zoom into every card and freezing the process.
        .modifier(DeferredLibraryPicker(
            isPresented: $showLibraryPicker,
            selection: $photoPickerItem
        ))
        .fullScreenCover(isPresented: $showCameraCapture) {
            CameraCapturePicker(
                onCapture: { image in
                    showCameraCapture = false
                    handleNewPhoto(image)
                },
                onCancel: { showCameraCapture = false }
            )
            .ignoresSafeArea()
        }
        .alert("Camera Unavailable", isPresented: $showCameraUnavailable) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This device doesn't have a camera available.")
        }
        .alert("Camera Access Required", isPresented: $showCameraPermissionDenied) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Memento needs camera access to add a photo. Enable it in Settings > Privacy > Camera.")
        }
        .onChange(of: isActivePage) { _, isActive in
            if isActive {
                Task { await loadFullResolutionCoverIfNeeded() }
            } else {
                handleSwipedAway()
            }
        }
        .onChange(of: isEditingExisting) { _, isEditing in
            guard isEditing else { return }
            focusedField = .body
        }
        .onDisappear {
            placePrefetch?.cancel()
            placePrefetch = nil
            shaderRevealTask?.cancel()
            shaderRevealTask = nil
            Task { await cancelDictationIfOwned() }
        }
    }
    
    // MARK: - Subviews

    /// Canvas or cover, used both as the view background and as the
    /// navigation container fill so the status-bar / Dynamic Island strip
    /// is never the system's white plate.
    @ViewBuilder
    private var editorFill: some View {
        if let photoPreviewImage {
            editorBackdrop(sharp: photoPreviewImage)
        } else {
            theme.background
        }
    }

    /// Figma 818:4006 cover: the thumbnail underneath, the pre-rendered
    /// treatment and scrim crossfaded on top by `shaderRevealProgress`.
    /// Static layers and opacities only — nothing here is filtered,
    /// transformed or rebuilt per frame.
    ///
    /// Driving `shaderRevealProgress` to 0 *is* the View memory reveal
    /// (Figma 824:4211): the treatment and scrim dissolve off and the
    /// full-resolution cover fades up underneath them. There is no second
    /// screen.
    ///
    /// Read `JournalBackdropRenderer`'s header before adding anything here.
    /// This is a screen-sized layer with five Liquid Glass surfaces above it,
    /// every one of which re-samples it on every frame of the zoom. A live
    /// filter here stalled the editor on device once; so did an animated
    /// `scaleEffect`, and so did promoting the base layer to the
    /// full-resolution photo. All three were fine in the Simulator.
    private func editorBackdrop(sharp: UIImage) -> some View {
        let params = editorBackdropParameters
        return ZStack {
            Image(uiImage: sharp)
                .resizable()
                .scaledToFill()

            // The real photo, and the only layer that needs to be: it is
            // mounted solely while some of the cover is actually showing
            // through, so the card tap and the zoom into the editor never pay
            // for it. `sharp` above is the list thumbnail.
            if shaderRevealProgress < 1, let untreatedPhotoImage {
                Image(uiImage: untreatedPhotoImage)
                    .resizable()
                    .scaledToFill()
                    .opacity(1 - shaderRevealProgress)
            }

            if let treatedPhotoImage {
                Image(uiImage: treatedPhotoImage)
                    .resizable()
                    .scaledToFill()
                    .opacity(shaderRevealProgress)
                    .transition(.opacity)
            }

            if params.scrimOpacity > 0.001 {
                JournalBackdropShader.scrimColor
                    .opacity(params.scrimOpacity * shaderRevealProgress)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// `editorDefaults` adapted to this photo's average colour and the
    /// accessibility switches — same resolution the card backdrop uses.
    private var editorBackdropParameters: JournalBackdropParameters {
        JournalBackdropContrast.resolved(
            sample: photoSample,
            base: JournalBackdropShader.editorDefaults,
            increaseContrast: UIAccessibility.isDarkerSystemColorsEnabled,
            reduceTransparency: reduceTransparency
        )
    }

    /// Footer chrome depends on mode:
    /// - Viewing an existing entry: nothing (lens lives in the header).
    /// - Editing an existing entry: mic + Capture.
    /// - Composing: mic + Capture, including after a cover is attached.
    @ViewBuilder
    private var footerFABs: some View {
        if isViewingExisting {
            EmptyView()
        } else {
            GlassEffectContainer(spacing: Self.footerGlassSpacing) {
                HStack {
                    EditorDictationPill(
                        ownerId: speechOwnerId,
                        foreground: chromeForeground,
                        interactive: !reduceMotion,
                        onTranscript: insertTranscribedText
                    )
                    .opacity(entryChromeOpacity)
                    .allowsHitTesting(!isViewingMemory)
                    .accessibilityHidden(isViewingMemory)
                    .transition(.opacity)

                    Spacer(minLength: Self.footerGlassSpacing)

                    captureFAB
                }
            }
            .padding(.horizontal, AppHeaderMetrics.edgeInset)
            .padding(.bottom, keyboardBottomPadding)
            .accessibleAnimation(Self.modeTransition, value: isViewingExisting)
        }
    }

    /// Compose mic rides the same opacity as the type: it acts on the
    /// entry, and does not belong on a revealed memory. Header chrome and
    /// Capture stay up.
    private var entryChromeOpacity: Double {
        hasCoverPhoto ? entryContentOpacity : 1
    }

    private var pageHeader: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: AppHeaderMetrics.windowTop)
                .frame(maxWidth: .infinity)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    HeaderIconButton(
                        systemName: "chevron.left",
                        accessibilityLabel: "Back",
                        accessibilityHint: isViewingExisting
                            ? "Double-tap to close"
                            : "Double-tap to close without saving",
                        foreground: chromeForeground,
                        interactive: !reduceMotion
                    ) {
                        closeEditor()
                    }
                    .accessibilityIdentifier("journal.entryEditor.back")

                    Spacer(minLength: 12)

                    if hasCoverPhoto {
                        memoryToggleButton
                    }

                    trailingHeaderButton
                }
                .padding(.bottom, AppHeaderMetrics.rowBottomPadding)
                .rootEdgeInset()
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Pencil in view; check to finish an existing edit; arrow-up to save a
    /// new compose. Stays visible on a revealed memory (Figma 824:4211).
    @ViewBuilder
    private var trailingHeaderButton: some View {
        Group {
            if isComposing {
                if isSaving {
                    ProgressView()
                        .tint(chromeForeground)
                        .mementoGlassButtonChrome(interactive: false)
                        .accessibilityLabel("Saving entry")
                        .accessibilityIdentifier("journal.entryEditor.save")
                } else {
                    HeaderIconButton(
                        systemName: "arrow.up",
                        accessibilityLabel: "Save entry",
                        accessibilityHint: "Double-tap to save your journal entry",
                        foreground: chromeForeground,
                        interactive: !reduceMotion
                    ) {
                        save()
                    }
                    .disabled(!hasSaveableContent)
                    .opacity(hasSaveableContent ? 1 : 0.2)
                    .accessibilityIdentifier("journal.entryEditor.save")
                }
            } else {
                HeaderIconButton(
                    systemName: isEditingExisting ? "checkmark" : "pencil",
                    accessibilityLabel: isEditingExisting ? "Done editing" : "Edit entry",
                    accessibilityHint: isEditingExisting
                        ? "Double-tap to save and return to viewing"
                        : "Double-tap to edit this journal entry",
                    foreground: chromeForeground,
                    interactive: !reduceMotion
                ) {
                    if isEditingExisting {
                        saveExistingAndReturnToView()
                    } else {
                        beginEditingExisting()
                    }
                }
                .disabled(isEditingExisting && !hasSaveableContent)
                .opacity(isEditingExisting && !hasSaveableContent ? 0.2 : 1)
                .accessibilityIdentifier(
                    isEditingExisting ? "journal.entryEditor.save" : "journal.entryEditor.edit"
                )
            }
        }
    }

    private var titleField: some View {
        TextField("", text: $title, axis: .vertical)
            .font(type.h3)
            .foregroundStyle(titleForeground)
            .tint(isViewingExisting ? .clear : titleForeground)
            .focused($focusedField, equals: .title)
            .textInputAutocapitalization(.words)
            .submitLabel(.next)
            .onSubmit {
                focusedField = .body
            }
            .placeholder(when: !isViewingExisting && title.isEmpty, alignment: .topLeading) {
                Text("Give your entry a title...")
                    .font(type.h3)
                    .photoCoverForeground(titlePlaceholderColor, shadowed: hasCoverPhoto)
            }
            .allowsHitTesting(!isViewingExisting)
            .accessibilityIdentifier("journal.entryEditor.title")
    }

    private var bodyField: some View {
        ZStack(alignment: .topLeading) {
            if !isViewingExisting && text.isEmpty {
                Text("Start writing your journal...")
                    .font(type.inputLarge)
                    .lineSpacing(editorBodyLineSpacing)
                    .photoCoverForeground(bodyPlaceholderColor, shadowed: hasCoverPhoto)
                    .allowsHitTesting(false)
            }

            TextEditor(text: $text)
                .font(type.inputLarge)
                .lineSpacing(editorBodyLineSpacing)
                .foregroundStyle(bodyForeground)
                .tint(isViewingExisting ? .clear : titleForeground)
                .focused($focusedField, equals: .body)
                .scrollContentBackground(.hidden)
                // Outer ScrollView owns scrolling so the caret stays above the
                // footer inset instead of sitting flush against the FABs.
                .scrollDisabled(true)
                .background { FlushTextEditorInsets() }
                .frame(minHeight: 300, alignment: .topLeading)
                .allowsHitTesting(!isViewingExisting)
                .accessibilityIdentifier("journal.entryEditor.body")
        }
    }
    
    /// Gap between the mic pill and Capture.
    private static let footerGlassSpacing: CGFloat = 16

    /// Figma 818:3843 silhouette — camera + "Capture". Native clear glass
    /// with a hair of frost; 56pt minimum, width hugs the label.
    private var captureFAB: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showCaptureOptions = true
        } label: {
            HStack(spacing: Self.captureLabelGap) {
                Image(systemName: "camera")
                    .font(AppHeaderMetrics.controlSymbolFont)
                Text("Capture")
                    .font(type.button)
                    .lineLimit(1)
            }
            .foregroundStyle(chromeForeground)
            .padding(.horizontal, Self.capturePadding)
            .mementoFooterGlassButtonChrome(interactive: !reduceMotion)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Capture")
        .accessibilityHint("Double-tap to take a photo or choose one from your library")
        .accessibilityIdentifier("journal.entryEditor.capture")
    }

    /// One control, both directions (Figma 898:1784 ↔ 824:4211). A single
    /// `Button` keeps the glass capsule alive across the toggle, so the
    /// glyph swaps in place instead of one shape vanishing while another
    /// materializes. Lens-blur while treated; lens while revealed.
    private var memoryToggleButton: some View {
        HeaderIconButton(
            assetName: isViewingMemory ? "Lens" : "LensBlur",
            accessibilityLabel: memoryToggleTitle,
            accessibilityHint: isViewingMemory
                ? "Double-tap to return to the journal entry"
                : "Double-tap to see the original photo without the shader",
            foreground: chromeForeground,
            interactive: !reduceMotion
        ) {
            setViewingMemory(!isViewingMemory)
        }
        .accessibilityIdentifier(
            isViewingMemory
                ? "journal.entryEditor.viewEntry"
                : "journal.entryEditor.viewMemory"
        )
    }

    private var memoryToggleTitle: String {
        isViewingMemory ? "View entry" : "View memory"
    }

    // MARK: - Actions

    /// Pencil on an existing entry. Create never calls this.
    private func beginEditingExisting() {
        guard editingEntry != nil, !isEditingExisting else { return }
        if isViewingMemory {
            isViewingMemory = false
            shaderRevealProgress = 1
            entryContentOpacity = 1
        }
        withAccessibleAnimation(Self.modeTransition, reduceMotion: reduceMotion) {
            isEditingExisting = true
        }
    }

    /// Persist an existing entry and return to view. Does not dismiss.
    private func saveExistingAndReturnToView() {
        guard editingEntry != nil, !isSaving, hasSaveableContent || hasPendingDictation else { return }

        foldPendingDictationIntoBody()

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)

        isSaving = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        onSave(trimmedTitle, trimmedText, photoAction, locationActionForSave())
        lastSavedTitle = trimmedTitle
        lastSavedText = trimmedText
        lastSavedHadPhoto = photoPreviewImage != nil
        photoDidChange = false
        isSaving = false
        resignEditing()
        withAccessibleAnimation(Self.modeTransition, reduceMotion: reduceMotion) {
            isEditingExisting = false
            showEditCompleteToast = true
        }
    }

    /// Compose-and-dismiss for new entries only.
    private func save() {
        // Both guards run *before* the fold. Folding tears the dictation
        // session down, so a save that is about to be rejected — nothing to
        // write, or one already in flight — must not reach it, or a stray tap
        // would kill a live recording and discard the transcript with it.
        //
        // An attached photo is content in its own right — a photo with just a
        // title (or nothing else at all) is a valid entry, so don't gate purely
        // on body text or the photo becomes silently unsavable.
        guard isComposing, !isSaving, hasSaveableContent || hasPendingDictation else { return }

        // Fold an in-flight dictation into the body *before* composing the
        // entry. This used to run after `trimmedText` had been captured, so
        // saving mid-dictation dropped everything that had been said.
        foldPendingDictationIntoBody()

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)

        isSaving = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        // Location is prefetched on appear. Do not await GPS here — that
        // left the save spinner up through the permission sheet and a
        // slow fix, and a Back tap could dismiss before onSave ran.
        onSave(trimmedTitle, trimmedText, photoAction, locationActionForSave())
        closeEditor()
    }

    /// A swipe to the neighbouring entry is navigation, not a discard, so end
    /// this page's editing session cleanly and keep whatever the user typed.
    /// Deliberately does **not** `dismiss()` — the editor stays up on the entry
    /// the pager moved to.
    private func handleSwipedAway() {
        // Snap rather than animate: the page is off screen, and the next time
        // it is a neighbour it should already be showing the entry.
        if isViewingMemory {
            isViewingMemory = false
            shaderRevealProgress = 1
            entryContentOpacity = 1
        }
        resignEditing()
        commitPendingEdits()
        isEditingExisting = false
        showEditCompleteToast = false
    }

    /// Writes the page back only if something actually changed, so paging
    /// across the timeline doesn't churn `updatedAt` on every entry it passes.
    private func commitPendingEdits() {
        // Same ordering contract as `save()`: fold the live transcript in
        // *before* the body is read, or dictation is silently dropped.
        foldPendingDictationIntoBody()

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let hadPhoto = photoPreviewImage != nil
        guard editingEntry != nil, !isSaving,
              photoDidChange
                || hadPhoto != lastSavedHadPhoto
                || trimmedTitle != lastSavedTitle
                || trimmedText != lastSavedText
        else {
            isEditingExisting = false
            return
        }

        onSave(trimmedTitle, trimmedText, photoAction, locationActionForSave())
        lastSavedTitle = trimmedTitle
        lastSavedText = trimmedText
        lastSavedHadPhoto = hadPhoto
        // The page stays alive while it is the pager's neighbour; without this
        // a second swipe past it would re-encrypt and rewrite the same photo.
        photoDidChange = false
        isEditingExisting = false
    }

    /// New entries only. Fire-and-forget so `.task` cancellation (dismiss)
    /// does not cancel the lookup, and save never waits on it.
    private func startPlacePrefetchIfNeeded() {
        guard shouldPrefetchPlace else { return }
        ensurePlacePrefetch()
    }

    private var shouldPrefetchPlace: Bool {
        guard editingEntry == nil else { return false }
        let env = ProcessInfo.processInfo.environment
        if env["XCODE_RUNNING_FOR_PREVIEWS"] == "1" { return false }
        if env["XCTestConfigurationFilePath"] != nil { return false }
        if ProcessInfo.processInfo.arguments.contains("-UITesting") { return false }
        return true
    }

    private func ensurePlacePrefetch() {
        guard shouldPrefetchPlace, placePrefetch == nil else { return }
        placePrefetch = Task {
            let name = try? await EntryLocationService.shared.resolvePlaceName()
            guard !Task.isCancelled else { return name }
            await MainActor.run { resolvedPlaceName = name }
            return name
        }
    }

    private func locationActionForSave() -> LocationAction {
        guard editingEntry == nil else { return .unchanged }
        if let name = resolvedPlaceName { return .set(name) }
        return .unchanged
    }

    /// Pop the overlay stack so the system can reverse the zoom into the
    /// matched source (FAB or card). Keyboard down first so it does not
    /// cover the shrink.
    private func closeEditor() {
        placePrefetch?.cancel()
        placePrefetch = nil
        shaderRevealTask?.cancel()
        shaderRevealTask = nil
        Task { await cancelDictationIfOwned() }
        resignEditing()
        dismiss()
    }

    /// Drops the keyboard from wherever it is. Clearing `focusedField` alone
    /// does not do it for the UIKit-backed body editor.
    private func resignEditing() {
        focusedField = nil
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil, from: nil, for: nil
        )
    }

    /// Back and zoom-dismiss must not leave the mic open. Cancel rather than
    /// stop — abandoned audio should not land in the body after the page is gone.
    private func cancelDictationIfOwned() async {
        guard speechService.isOwner(speechOwnerId) else { return }
        await speechService.cancelRecording()
    }

    /// A live transcript `hasSaveableContent` cannot see, because it is still
    /// held by the service rather than folded into `text`. Saving while the
    /// mic is open is otherwise indistinguishable from saving an empty entry.
    private var hasPendingDictation: Bool {
        guard speechService.isOwner(speechOwnerId) else { return false }
        return !speechService.bestAvailableTranscript
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    /// Whether there's anything worth saving: body text or an attached photo.
    private var hasSaveableContent: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || photoData != nil
            || photoPreviewImage != nil
    }

    /// Downscales/compresses the new photo and installs it as the current
    /// selection — used by both the camera and library paths. Replaces
    /// whatever photo was selected before (single photo per entry).
    ///
    /// The downscale + JPEG encode runs off the main thread: a 12MP camera
    /// photo through `UIGraphicsImageRenderer` is tens-to-hundreds of ms, which
    /// visibly stutters the capture-confirm transition if done inline.
    private func handleNewPhoto(_ image: UIImage) {
        Task {
            let prepared: (data: Data, image: UIImage, sample: JournalBackdropSample)? = await Task.detached(priority: .userInitiated) {
                guard let data = ImageProcessor.prepareForStorage(image) else { return nil }
                let uiImage = UIImage(data: data) ?? image
                return (data, uiImage, JournalBackdropContrast.sample(image: uiImage))
            }.value

            guard let prepared else { return }
            shaderRevealTask?.cancel()
            shaderRevealTask = nil
            if !reduceMotion {
                shaderRevealProgress = 0
                entryContentOpacity = 0
            }
            photoData = prepared.data
            photoPreviewImage = prepared.image
            untreatedPhotoImage = prepared.image
            photoSample = prepared.sample
            photoDidChange = true
            isViewingMemory = false
            treatedPhotoImage = nil
            // The crossfade needs its destination first; this is one small
            // CoreImage pass off-main, well under the reveal's first frame.
            await renderTreatedBackdrop(from: prepared.image, sample: prepared.sample)
            revealCoverPhoto(animated: true)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    /// Bakes `editorDefaults` blur + saturation for `image` off the main
    /// thread and installs the bitmap, unless a newer photo superseded this
    /// render. Fades in when the treatment is already fully revealed (an
    /// existing entry) so the cover does not pop from sharp to blurred.
    private func renderTreatedBackdrop(from image: UIImage, sample: JournalBackdropSample?) async {
        treatedRenderToken &+= 1
        let token = treatedRenderToken
        let params = JournalBackdropContrast.resolved(
            sample: sample,
            base: JournalBackdropShader.editorDefaults,
            increaseContrast: UIAccessibility.isDarkerSystemColorsEnabled,
            reduceTransparency: reduceTransparency
        )
        let displaySize = JournalBackdropRenderer.currentDisplaySize()
        let rendered = await Task.detached(priority: .userInitiated) {
            JournalBackdropRenderer.treated(image, params: params, displaySize: displaySize)
        }.value
        guard !Task.isCancelled, token == treatedRenderToken else { return }
        if shaderRevealProgress >= 1, !reduceMotion {
            withAnimation(.easeOut(duration: 0.2)) {
                treatedPhotoImage = rendered
            }
        } else {
            treatedPhotoImage = rendered
        }
    }

    /// The View memory / View entry choreography, both directions.
    ///
    /// Nothing mounts or unmounts. The entry's own surfaces fade and the
    /// backdrop's shader dissolves a beat behind them. Overlapping those is
    /// what makes the two read as a single move rather than a sequence of
    /// steps.
    private func setViewingMemory(_ viewing: Bool) {
        guard isViewingMemory != viewing else { return }
        // A capture reveal, and a return from a memory, both write state on a
        // timer. A toggle part-way through one must not have that land on top
        // of it.
        shaderRevealTask?.cancel()
        shaderRevealTask = nil
        if viewing { resignEditing() }

        guard !reduceMotion else {
            isViewingMemory = viewing
            shaderRevealProgress = viewing ? 0 : 1
            entryContentOpacity = viewing ? 0 : 1
            return
        }

        if viewing {
            withAnimation(.easeInOut(duration: Self.memoryChromeFadeDuration)) {
                isViewingMemory = true
                entryContentOpacity = 0
            }
            withAnimation(Self.memoryRevealCurve.delay(Self.memoryChromeFadeDelay)) {
                shaderRevealProgress = 0
            }
        } else {
            withAnimation(Self.memoryRevealCurve) {
                shaderRevealProgress = 1
            }
            // The glyph flips straight away so the tap is acknowledged. The
            // type and the compose mic arrive as the shader lands — the
            // same photo → shader → type staging a capture uses.
            withAnimation(.easeInOut(duration: Self.memoryChromeFadeDuration)) {
                isViewingMemory = false
            }
            withAnimation(
                .easeInOut(duration: Self.textRevealDuration)
                    .delay(Self.memoryRevealDuration - Self.textRevealDuration)
            ) {
                entryContentOpacity = 1
            }
        }
    }

    /// Photo first (sharp), shader eases in, then title/body fade in.
    /// Reduce Motion skips the sequence. Dismiss cancels the follow-up fade
    /// so it cannot overlap the zoom-out transaction.
    private func revealCoverPhoto(animated: Bool) {
        shaderRevealTask?.cancel()
        shaderRevealTask = nil
        if reduceMotion || !animated {
            shaderRevealProgress = 1
            entryContentOpacity = 1
            return
        }
        shaderRevealProgress = 0
        entryContentOpacity = 0
        withAnimation(.easeInOut(duration: Self.shaderRevealDuration)) {
            shaderRevealProgress = 1
        }
        shaderRevealTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.shaderRevealDuration))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: Self.textRevealDuration)) {
                entryContentOpacity = 1
            }
        }
    }

    /// On `.edit(entry)` where the entry already has a photo, show the list
    /// thumbnail immediately (already decoded) so the zoom is not a full-file
    /// decrypt. Bytes for save / View memory load afterward, and only on the
    /// active pager page — neighbours must not triple that cost on mount.
    private func preloadExistingPhotoIfNeeded() async {
        guard let entry = editingEntry, entry.hasPhoto,
              photoPreviewImage == nil, !photoDidChange else { return }

        let entryId = entry.id
        if let cached = PhotoThumbnailCache.shared.image(for: entryId) {
            let sample = PhotoThumbnailCache.shared.sample(for: entryId)
            photoPreviewImage = cached
            photoSample = sample
            revealCoverPhoto(animated: false)
        }

        guard isActivePage else { return }
        await loadFullResolutionCoverIfNeeded()
    }

    /// Full-file decrypt plus the CoreImage treated bake. Gated on the
    /// pager's active page so a `TabView` neighbour never pays for a cover
    /// nobody can see. Driven from `.task` (the opened card) and from
    /// `.onChange(of: isActivePage)` (a swipe onto this page).
    private func loadFullResolutionCoverIfNeeded() async {
        guard isActivePage, let entry = editingEntry, entry.hasPhoto,
              !photoDidChange else { return }

        let entryId = entry.id
        if treatedPhotoImage == nil, let preview = photoPreviewImage {
            await renderTreatedBackdrop(from: preview, sample: photoSample)
            guard !Task.isCancelled else { return }
        }

        guard untreatedPhotoImage == nil || photoData == nil else { return }

        let loaded: (data: Data, image: UIImage, sample: JournalBackdropSample)? = await Task.detached(priority: .userInitiated) {
            guard let encrypted = PhotoStorage.shared.loadEncrypted(entryId: entryId),
                  let data = JournalService.shared.encryptionService.decryptData(encrypted),
                  let uiImage = UIImage(data: data) else { return nil }
            return (data, uiImage, JournalBackdropContrast.sample(image: uiImage))
        }.value

        guard !Task.isCancelled, let loaded, !photoDidChange else { return }
        photoData = loaded.data
        untreatedPhotoImage = loaded.image
        if photoPreviewImage == nil {
            photoPreviewImage = loaded.image
            photoSample = loaded.sample
            revealCoverPhoto(animated: false)
            await renderTreatedBackdrop(from: loaded.image, sample: loaded.sample)
        }
    }

    /// Guards camera availability (always false on Simulator) and permission
    /// before presenting, mirroring the microphone's `showPermissionDenied` pattern.
    private func presentCameraOrHandleUnavailable() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            showCameraUnavailable = true
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            showCameraCapture = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        showCameraCapture = true
                    } else {
                        showCameraPermissionDenied = true
                    }
                }
            }
        case .denied, .restricted:
            showCameraPermissionDenied = true
        @unknown default:
            showCameraPermissionDenied = true
        }
    }

    /// `EditorDictationPill` callback. The pill has already ended the session
    /// and trimmed the text; this only places it.
    private func insertTranscribedText(_ transcript: String) {
        appendToBody(transcript)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        focusedField = .body
    }

    /// Save while the mic is still open: take whatever has been heard, then
    /// abandon the session rather than stopping it — the page is going away,
    /// so a late finalization has nowhere to land.
    private func foldPendingDictationIntoBody() {
        guard speechService.isOwner(speechOwnerId) else { return }
        let pending = speechService.bestAvailableTranscript
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !pending.isEmpty {
            appendToBody(pending)
        }
        speechService.clearTranscription()
        Task { await speechService.cancelRecording() }
    }

    private func appendToBody(_ transcript: String) {
        if text.isEmpty {
            text = transcript
        } else {
            text += "\n\n" + transcript
        }
    }
}

#if DEBUG
extension AddEntryView {
    /// Seeds a cover so canvas previews can show the photo-backed chrome.
    fileprivate init(
        state: EntryState,
        previewPhoto: UIImage,
        previewTitle: String,
        previewBody: String,
        previewViewingMemory: Bool = false,
        onSave: @escaping (_ title: String, _ text: String, _ photoAction: PhotoAction, _ locationAction: LocationAction) -> Void
    ) {
        self.state = state
        self.onSave = onSave
        _isViewingMemory = State(initialValue: previewViewingMemory)
        _title = State(initialValue: previewTitle)
        _text = State(initialValue: previewBody)
        _lastSavedTitle = State(initialValue: previewTitle)
        _lastSavedText = State(initialValue: previewBody)
        _lastSavedHadPhoto = State(initialValue: true)
        _photoPreviewImage = State(initialValue: previewPhoto)
        _photoData = State(initialValue: previewPhoto.jpegData(compressionQuality: 0.8))
        let sample = JournalBackdropContrast.sample(image: previewPhoto)
        _photoSample = State(initialValue: sample)
        _untreatedPhotoImage = State(initialValue: previewPhoto)
        _treatedPhotoImage = State(initialValue: JournalBackdropRenderer.treated(
            previewPhoto,
            params: JournalBackdropShader.editorDefaults,
            displaySize: CGSize(width: 402, height: 874)
        ))
        // The revealed state is the shader dissolved away, not a second view,
        // so the preview flag has to seed the same scalars the toggle drives.
        _shaderRevealProgress = State(initialValue: previewViewingMemory ? 0 : 1)
        _entryContentOpacity = State(initialValue: previewViewingMemory ? 0 : 1)
    }
}

private enum AddEntryPreviewAssets {
    static let photo: UIImage = {
        let size = CGSize(width: 8, height: 12)
        return UIGraphicsImageRenderer(size: size).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }()
}
#endif

// MARK: - Deferred library picker

/// PhotosUI stays off the editor until Capture → Library. Attaching
/// `.photosPicker` on the zoom destination initialized PhotoKit for every
/// card tap and stalled the process.
private struct DeferredLibraryPicker: ViewModifier {
    @Binding var isPresented: Bool
    @Binding var selection: PhotosPickerItem?

    func body(content: Content) -> some View {
        content.background {
            if isPresented || selection != nil {
                Color.clear
                    .frame(width: 0, height: 0)
                    .photosPicker(isPresented: $isPresented, selection: $selection, matching: .images)
            }
        }
    }
}

// MARK: - TextEditor inset reset

/// `TextEditor` wraps `UITextView`, which ships with an 8pt container inset
/// and 5pt line-fragment padding. That shifts the body off the title
/// `TextField`'s leading edge and inflates the gap past the 8pt stack spacing.
private struct FlushTextEditorInsets: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            guard let textView = Self.nearestTextView(from: uiView) else { return }
            if textView.textContainerInset != .zero {
                textView.textContainerInset = .zero
            }
            if textView.textContainer.lineFragmentPadding != 0 {
                textView.textContainer.lineFragmentPadding = 0
            }
        }
    }

    /// Prefer a sibling `UITextView` so we reset the body editor, not the
    /// title field further up the hosting tree.
    private static func nearestTextView(from view: UIView) -> UITextView? {
        var node: UIView? = view
        while let current = node {
            if let textView = current as? UITextView { return textView }
            if let parent = current.superview {
                for sibling in parent.subviews where sibling !== current {
                    if let textView = findTextView(in: sibling) { return textView }
                }
            }
            node = current.superview
        }
        return nil
    }

    private static func findTextView(in view: UIView) -> UITextView? {
        if let textView = view as? UITextView { return textView }
        for subview in view.subviews {
            if let found = findTextView(in: subview) { return found }
        }
        return nil
    }
}

// MARK: - Previews

#Preview("Create Entry") {
    AddEntryView(state: .create) { _, _, _, _ in }
        .useTheme()
        .useTypography()
}

#Preview("Create Entry • Photo") {
    AddEntryView(
        state: .create,
        previewPhoto: AddEntryPreviewAssets.photo,
        previewTitle: "A quiet morning in September makes me always remember more than I wish to",
        previewBody: "The air had that unmistakable crispness this morning — summer finally loosening its grip."
    ) { _, _, _, _ in }
        .useTheme()
        .useTypography()
}

/// The shader dissolved off, which is all a revealed memory is.
#Preview("Memory Revealed") {
    AddEntryView(
        state: .create,
        previewPhoto: AddEntryPreviewAssets.photo,
        previewTitle: "A quiet morning in September makes me always remember more than I wish to",
        previewBody: "The air had that unmistakable crispness this morning — summer finally loosening its grip.",
        previewViewingMemory: true
    ) { _, _, _, _ in }
        .useTheme()
        .useTypography()
}

#Preview("Edit Entry") {
    AddEntryView(state: .edit(Entry.sampleEntries[0])) { _, _, _, _ in }
        .useTheme()
        .useTypography()
}

#Preview("Create Entry • Dark") {
    AddEntryView(state: .create) { _, _, _, _ in }
        .useTheme()
        .useTypography()
        .preferredColorScheme(.dark)
}

#Preview("Page Presentation") {
    NavigationStack {
        AddEntryView(state: .create) { _, _, _, _ in }
    }
    .useTheme()
    .useTypography()
}
