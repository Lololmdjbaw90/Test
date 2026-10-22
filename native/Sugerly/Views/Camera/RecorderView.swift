import SwiftUI
import UIKit
import AVFoundation

// MARK: - The camera screen

// Opens straight away when you make a reel (like TikTok). The camera window
// is exactly the reel's shape. Tap the big button to film and again to
// pause, or hold it to film while you hold (slide up to zoom). Keep adding
// clips; tap the delete button twice to take the last one away. Down the
// right: flip, flash (the front light on the front camera), speed, filters
// (or swipe sideways on the picture), timer, grid and Align. Tap the picture
// to focus there and slide up or down for brighter or darker; hold it to
// lock focus and light; tap twice to flip.
struct RecorderView: View {
    @Binding var sound: Track?
    var onVideo: (URL, ReelFilter) -> Void
    var onPhotos: ([UIImage], ReelFilter) -> Void
    var onClose: () -> Void
    // Pick a video or photos from your library instead.
    var onUpload: (() -> Void)? = nil
    // Your saved drafts (none in chats).
    var draftCount = 0
    var onDrafts: (() -> Void)? = nil
    // What was just being edited, shown softly blurred while the camera
    // wakes up when you come back from the editor (instead of black).
    var backdrop: UIImage? = nil

    enum Mode: String, CaseIterable { case short = "15s", long = "60s", photo = "Photo" }
    private enum Panel { case speed, filters }

    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("sugerly.recorder.firstTip") private var tipShown = false
    @AppStorage("sugerly.recorder.lightTone") private var lightTone: FrontLightTone = .warm
    @State private var camera = CameraEngine()
    @State private var mode = Mode.long
    @State private var panel: Panel?
    @State private var timer = 0
    @State private var countdown = 0
    @State private var countdownJob: Task<Void, Never>?
    @State private var shots: [UIImage] = []
    @State private var lightBurst = false
    @State private var blink = false
    @State private var merging = false
    @State private var error: String?
    @State private var grid = false
    @State private var align = false
    @State private var pickingSound = false
    @State private var confirmRestart = false
    @State private var confirmClose = false
    // The delete button was tapped once: the last clip shows red until a
    // second tap deletes it (or a moment passes).
    @State private var armedDelete = false
    @State private var disarmJob: Task<Void, Never>?
    @State private var focusPoint: CGPoint?
    @State private var focusTick = 0
    @State private var focusJob: Task<Void, Never>?
    @State private var exposureStart: Float = 0
    @State private var pinchStart: CGFloat = 1
    @State private var hint: String?
    @State private var hintTick = 0
    @State private var filterName: String?
    @State private var filterTick = 0
    @State private var lensTick = 0
    // Holding the big button.
    @GestureState private var pressing = false
    @State private var pressStart: Date?
    @State private var heldClip = false
    @State private var holdZoom: CGFloat = 1
    @State private var savedBrightness: CGFloat?

    // Front camera with the flash on: the screen becomes a soft light.
    private var ringLight: Bool { camera.flash && camera.position == .front && camera.access == .granted }

    var body: some View {
        decorate(screen)
    }

    private var screen: some View {
        GeometryReader { geo in
            let frame = RecorderFrame(size: geo.size, insets: Self.screenInsets(geo.safeAreaInsets), light: ringLight)
            ZStack(alignment: .topLeading) {
                Color.black
                if ringLight { FrontLight(tone: lightTone).transition(.opacity) }
                cameraCard(frame)
                    .frame(width: frame.card.width, height: frame.card.height)
                    .clipShape(RoundedRectangle(cornerRadius: frame.corner, style: .continuous))
                    .offset(x: frame.card.minX, y: frame.card.minY)
                if frame.roomy {
                    modeBar
                        .frame(width: frame.strip.width, height: frame.strip.height)
                        .offset(y: frame.strip.minY)
                }
                if lightBurst {
                    (ringLight ? lightTone.color : Color.white)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
                if merging { joiningCover.transition(.opacity) }
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .statusBarHidden()
    }

    // The screen's real safe area (the Dynamic Island or status bar, and the
    // home bar). This screen reaches the edges, so it measures none itself,
    // and the buttons ended up under the Dynamic Island.
    private static func screenInsets(_ measured: EdgeInsets) -> EdgeInsets {
        let window = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first
        guard let insets = window?.safeAreaInsets else { return measured }
        return EdgeInsets(top: max(measured.top, insets.top), leading: max(measured.leading, insets.left),
                          bottom: max(measured.bottom, insets.bottom), trailing: max(measured.trailing, insets.right))
    }

    // Sheets, questions, and keeping the camera in step with the song, the
    // front light and the app going to the background.
    private func decorate<Content: View>(_ content: Content) -> some View {
        content
            .sheet(isPresented: $pickingSound) {
                SoundPicker { track in sound = track }
                    .presentationDetents([.medium, .large])
                    .presentationCornerRadius(30)
            }
            .confirmationDialog("Start over?", isPresented: $confirmRestart, titleVisibility: .visible) {
                Button("Delete all clips", role: .destructive) {
                    withMotion { camera.restart() }
                    align = false
                    armedDelete = false
                }
            }
            .confirmationDialog("Discard what you filmed?", isPresented: $confirmClose, titleVisibility: .visible) {
                Button("Discard", role: .destructive) {
                    camera.restart()
                    shots = []
                    leave()
                }
                Button("Keep filming", role: .cancel) {}
            }
            .task {
                camera.setSound(sound)
                camera.onPhoto = { image in withMotion(Motion.release) { shots.append(image) } }
                await camera.start()
                if !tipShown && camera.access == .granted {
                    tipShown = true
                    showHint("Tap to film, or hold the button to film while you hold")
                }
            }
            .onDisappear {
                countdownJob?.cancel()
                camera.stop()
                brighten(false)
            }
            .onChange(of: sound) { _, track in camera.setSound(track) }
            .onChange(of: ringLight) { _, on in brighten(on) }
            .onChange(of: scenePhase) { _, phase in brighten(phase == .active && ringLight) }
            .onChange(of: pressing) { _, now in
                // The touch was cut off (a call, an alert) without letting
                // go: a clip filmed by holding stops.
                guard !now else { return }
                Task {
                    try? await Task.sleep(for: .milliseconds(120))
                    if pressStart != nil { pressCancelled() }
                }
            }
            .onChange(of: camera.recording) { _, on in
                guard on else { return }
                disarmJob?.cancel()
                armedDelete = false
                withMotion(Motion.standard) { panel = nil }
            }
            .onChange(of: camera.refocused) { _, _ in
                withAnimation(.easeOut(duration: 0.3)) { focusPoint = nil }
            }
            .sensoryFeedback(.impact(weight: .light), trigger: countdown) { _, new in new > 0 }
            .sensoryFeedback(.selection, trigger: camera.filter)
            .sensoryFeedback(.selection, trigger: lensTick)
            .sensoryFeedback(.impact(weight: .medium), trigger: camera.focusLocked) { _, new in new }
            .animation(Motion.pick(.spring(response: 0.42, dampingFraction: 0.84)), value: ringLight)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: camera.clips.count)
            .animation(.easeInOut(duration: 0.25), value: align)
            .animation(Motion.fade, value: armedDelete)
    }

    // MARK: the camera window

    private func cameraCard(_ frame: RecorderFrame) -> some View {
        ZStack {
            cameraLayer
            if countdown > 0 { countdownNumber }
            controls(frame)
        }
        .animation(Motion.pick(.spring(response: 0.3, dampingFraction: 0.7)), value: countdown)
    }

    @ViewBuilder
    private var cameraLayer: some View {
        switch camera.access {
        case .denied:
            notice(icon: "camera.fill", title: "Camera access is off",
                   text: "Turn it on in Settings → Sugerly to film here.", settings: true)
        case .unavailable:
            notice(icon: "video.slash.fill", title: "The camera isn't available",
                   text: "You can still make a reel from your library.", settings: false)
        default:
            ZStack {
                waiting
                if camera.access == .granted {
                    liveCamera.opacity(camera.running ? 1 : 0)
                }
                if camera.switching || camera.paused {
                    Color.black.opacity(camera.paused ? 0.6 : 0.4)
                        .overlay {
                            if camera.paused {
                                Label("Camera paused", systemImage: "pause.fill")
                                    .font(.jakarta(14, .bold)).foregroundStyle(.white)
                            }
                        }
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
                if blink {
                    Color.black.opacity(0.45)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.35), value: camera.running)
            .animation(.easeOut(duration: 0.2), value: camera.switching)
        }
    }

    private var liveCamera: some View {
        CameraSurface(session: camera.core.session, renderer: camera.renderer,
                      filtered: camera.filter != .none, canSlide: focusPoint != nil,
                      onTap: { point, spot in tapFocus(point, spot, lock: false) },
                      onHold: { point, spot in tapFocus(point, spot, lock: true) },
                      onDoubleTap: { flip() },
                      onPinch: { scale, phase in pinch(scale, phase) },
                      onSwipe: { step in swipeFilter(step) },
                      onSlide: { amount, phase in slide(amount, phase) })
            .overlay { alignGhost }
            .overlay { if grid { CameraGrid() } }
            .overlay { focusLayer }
            .overlay { filterNameLayer }
    }

    // Behind the camera while it wakes up: what you were just editing,
    // softly blurred, or a dark pink wash.
    private var waiting: some View {
        Color.clear
            .overlay {
                if let backdrop {
                    Image(uiImage: backdrop).resizable().scaledToFill()
                        .blur(radius: 26)
                        .scaleEffect(1.15)
                        .overlay(Color.black.opacity(0.3))
                } else {
                    LinearGradient(colors: [Color(hex: 0x2A1320), Color(hex: 0x12080E)], startPoint: .top, endPoint: .bottom)
                }
            }
            .clipped()
            .allowsHitTesting(false)
    }

    private func notice(icon: String, title: String, text: String, settings: Bool) -> some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x2A1320), Color(hex: 0x12080E)], startPoint: .top, endPoint: .bottom)
            VStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 40)).foregroundStyle(Theme.gradient)
                Text(title).font(.display(24)).foregroundStyle(.white).multilineTextAlignment(.center)
                Text(text).font(.jakarta(14)).foregroundStyle(.white.opacity(0.7)).multilineTextAlignment(.center)
                if settings {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                    .buttonStyle(GradientButtonStyle(fullWidth: false))
                }
                if let onUpload {
                    Button("Choose from library", action: onUpload)
                        .font(.jakarta(15, .bold)).foregroundStyle(.white)
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, 32)
        }
    }

    // "Align": the end of your last clip, see-through over the camera.
    @ViewBuilder
    private var alignGhost: some View {
        if align, !camera.recording, let ghost = camera.clips.last?.ghost {
            Color.clear
                .overlay { Image(uiImage: ghost).resizable().scaledToFill() }
                .clipped()
                .opacity(0.38)
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }

    private var focusLayer: some View {
        ZStack {
            if let focusPoint {
                FocusMark(locked: camera.focusLocked, exposure: camera.exposure)
                    .position(focusPoint)
                    .id(focusTick)
                    .transition(.scale(scale: 1.35).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    // The filter's name, big for a moment, when you swipe to it.
    private var filterNameLayer: some View {
        ZStack {
            if let filterName {
                Text(filterName)
                    .font(.display(34)).foregroundStyle(.white)
                    .budgetShadow(color: .black.opacity(0.4), radius: 8)
                    .id(filterTick)
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    private var countdownNumber: some View {
        Text("\(countdown)")
            .font(.display(150)).foregroundStyle(.white)
            .budgetShadow(color: Theme.main.opacity(0.8), radius: 24)
            .id(countdown)
            .transition(.asymmetric(insertion: .scale(scale: 1.6).combined(with: .opacity),
                                    removal: .scale(scale: 0.7).combined(with: .opacity)))
            .allowsHitTesting(false)
    }

    // Putting the clips together into one video.
    private var joiningCover: some View {
        ZStack {
            Color.black.opacity(0.55)
            VStack(spacing: 14) {
                ZStack {
                    Circle().stroke(.white.opacity(0.2), lineWidth: 5)
                    Circle()
                        .trim(from: 0, to: max(0.03, min(1, camera.joinProgress)))
                        .stroke(Theme.gradient, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(Int(min(1, camera.joinProgress) * 100))%")
                        .font(.jakarta(15, .heavy)).foregroundStyle(.white)
                        .monospacedDigit()
                }
                .frame(width: 74, height: 74)
                .animation(.linear(duration: 0.15), value: camera.joinProgress)
                Text("Getting your video ready…").font(.jakarta(15, .bold)).foregroundStyle(.white)
            }
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .combine)
    }

    // MARK: controls

    private func controls(_ frame: RecorderFrame) -> some View {
        VStack(spacing: 0) {
            topArea
            HStack(alignment: .top, spacing: 0) {
                Spacer(minLength: 0)
                railFitting
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(.top, 8)
            bottomArea(frame)
        }
        .padding(.top, frame.top)
        .padding(.bottom, frame.bottom)
    }

    private var topArea: some View {
        VStack(spacing: 10) {
            if mode != .photo && (!camera.clips.isEmpty || camera.recording) {
                SegmentBar(clips: camera.clips.map(\.effective), current: max(0, camera.total - camera.filmed),
                           limit: camera.maxSeconds, armed: armedDelete, marker: mode == .long ? 15 : nil)
                    .padding(.horizontal, 12)
                    .transition(.opacity)
            }
            HStack(spacing: 10) {
                RoundIcon(icon: "xmark", label: "Close") { close() }
                Spacer(minLength: 6)
                soundPill
                Spacer(minLength: 6)
                if mode != .photo && !camera.clips.isEmpty {
                    RoundIcon(icon: "arrow.counterclockwise", label: "Start over") { confirmRestart = true }
                        .transition(.pop)
                } else {
                    Color.clear.frame(width: 44, height: 44)
                }
            }
            .padding(.horizontal, 12)
            .opacity(camera.recording ? 0 : 1)
            .allowsHitTesting(!camera.recording)
            if camera.focusLocked {
                Label("Focus and light locked", systemImage: "lock.fill")
                    .font(.jakarta(11, .heavy)).foregroundStyle(Color(hex: 0x2A1620))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color(hex: 0xFFD166), in: Capsule())
                    .transition(.opacity)
            }
            if let hint {
                Text(hint)
                    .font(.jakarta(13, .bold)).foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.black.opacity(0.5), in: Capsule())
                    .padding(.horizontal, 30)
                    .id(hintTick)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .padding(.top, 10)
        .background(alignment: .top) {
            LinearGradient(colors: [.black.opacity(0.4), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 150)
                .allowsHitTesting(false)
        }
        .animation(Motion.fade, value: camera.recording)
        .animation(Motion.fade, value: camera.focusLocked)
    }

    private var soundPill: some View {
        HStack(spacing: 0) {
            Button { if !camera.recording { pickingSound = true } } label: {
                HStack(spacing: 6) {
                    Image(systemName: "music.note").font(.system(size: 13, weight: .bold))
                    Text(sound?.title ?? "Add sound").font(.jakarta(13, .bold)).lineLimit(1)
                }
                .padding(.leading, 14)
                .padding(.trailing, sound == nil ? 14 : 4)
                .frame(height: 36)
                .contentShape(Rectangle())
            }
            .buttonStyle(SoftPressStyle())
            if sound != nil {
                Button { sound = nil } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .heavy))
                        .frame(width: 30, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(SoftPressStyle())
                .accessibilityLabel("Remove sound")
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: 210)
        .background(.black.opacity(0.4), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 1))
    }

    // The tools down the right, with their names when there's room (just the
    // icons on a short screen, scrolling on a very short one).
    private var railFitting: some View {
        ViewThatFits(in: .vertical) {
            rail(labeled: true)
            rail(labeled: false)
            ScrollView(.vertical, showsIndicators: false) { rail(labeled: false) }
        }
        .padding(.trailing, 4)
        .opacity(camera.recording ? 0 : 1)
        .allowsHitTesting(!camera.recording)
        .animation(Motion.fade, value: camera.recording)
    }

    private func rail(labeled: Bool) -> some View {
        VStack(spacing: labeled ? 10 : 8) {
            RailButton(icon: "arrow.triangle.2.circlepath.camera", title: "Flip", labeled: labeled) { flip() }
            RailButton(icon: camera.flash ? "bolt.fill" : "bolt.slash.fill", title: "Flash", active: camera.flash, labeled: labeled) {
                toggleFlash()
            }
            .overlay(alignment: .trailing) {
                if ringLight {
                    ToneTray(tone: lightTone) { pickTone($0) }
                        .fixedSize()
                        .offset(x: -62)
                        .transition(.scale(scale: 0.3, anchor: .trailing).combined(with: .opacity))
                }
            }
            .zIndex(1)
            if mode != .photo {
                RailButton(icon: "speedometer", title: "Speed", active: panel == .speed || camera.speed != 1,
                           badge: camera.speed != 1 ? SpeedPicker.label(camera.speed) : nil, labeled: labeled) {
                    togglePanel(.speed)
                }
            }
            RailButton(icon: "camera.filters", title: "Filters", active: panel == .filters || camera.filter != .none, labeled: labeled) {
                togglePanel(.filters)
            }
            RailButton(icon: "timer", title: "Timer", active: timer > 0, badge: timer > 0 ? "\(timer)s" : nil, labeled: labeled) {
                cycleTimer()
            }
            RailButton(icon: "grid", title: "Grid", active: grid, labeled: labeled) { grid.toggle() }
            if mode != .photo && !camera.clips.isEmpty {
                RailButton(icon: "square.on.square.dashed", title: "Align", active: align, labeled: labeled) { toggleAlign() }
                    .transition(.pop)
            }
        }
    }

    private func bottomArea(_ frame: RecorderFrame) -> some View {
        VStack(spacing: 14) {
            if let error {
                Text(error)
                    .font(.jakarta(13, .semibold)).foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Palette.danger, in: Capsule())
                    .padding(.horizontal, 20)
                    .onTapGesture { self.error = nil }
                    .transition(.opacity)
            }
            if mode == .photo && !shots.isEmpty { shotsStrip }
            panelArea
            recordRow
            if !frame.roomy {
                modeBar.frame(height: 48)
            }
        }
        .padding(.bottom, frame.roomy ? 16 : 4)
        .background(alignment: .bottom) {
            LinearGradient(colors: [.clear, .black.opacity(0.45)], startPoint: .top, endPoint: .bottom)
                .frame(height: 280)
                .allowsHitTesting(false)
        }
        .animation(Motion.standard, value: panel)
    }

    // Above the big button: the speed or filter picker when one is open,
    // otherwise the lens stops.
    @ViewBuilder
    private var panelArea: some View {
        switch panel {
        case .speed:
            SpeedPicker(speed: camera.speed) { pickSpeed($0) }
                .transition(.rise)
        case .filters:
            FilterStrip(selected: camera.filter) { pickFilter($0) }
                .transition(.rise)
        case nil:
            if camera.lenses.count > 1 {
                LensPicker(lenses: camera.lenses, zoom: camera.zoom) { pickLens($0) }
                    .transition(.opacity)
            }
        }
    }

    private var shotsStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(shots.indices, id: \.self) { i in
                    Image(uiImage: shots[i]).resizable().scaledToFill()
                        .frame(width: 46, height: 82)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(alignment: .topTrailing) {
                            Button { withMotion { _ = shots.remove(at: i) } } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 17))
                                    .foregroundStyle(.white, .black.opacity(0.6))
                            }
                            .offset(x: 6, y: -6)
                            .accessibilityLabel("Remove photo \(i + 1)")
                        }
                        .transition(.pop)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .frame(height: 96)
    }

    private var recordRow: some View {
        HStack(alignment: .center, spacing: 0) {
            leftSlot.frame(maxWidth: .infinity)
            recordButton
            rightSlot.frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 8)
    }

    // Left of the big button: delete the last clip, or your drafts before
    // you start.
    @ViewBuilder
    private var leftSlot: some View {
        if mode != .photo && !camera.clips.isEmpty && !camera.recording {
            RoundIcon(icon: "delete.backward.fill", label: armedDelete ? "Delete the last clip now" : "Delete last clip",
                      size: 48, tint: armedDelete ? Palette.danger : nil) { deleteTapped() }
                .transition(.pop)
        } else if draftCount > 0, let onDrafts, camera.clips.isEmpty, shots.isEmpty, !camera.recording {
            SideTile(icon: "tray.full.fill", title: "Drafts", action: onDrafts)
        } else {
            Color.clear.frame(width: 48, height: 48)
        }
    }

    // Right of it: done, or pick from your library before you start.
    @ViewBuilder
    private var rightSlot: some View {
        if ready {
            Button { Task { await finish() } } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 20, weight: .heavy)).foregroundStyle(.white)
                    .frame(width: 54, height: 54)
                    .background(Theme.gradient, in: Circle())
                    .budgetShadow(color: .black.opacity(0.25), radius: 8, y: 3)
            }
            .buttonStyle(BouncyStyle(scale: 0.85))
            .disabled(merging)
            .accessibilityLabel("Done")
            .transition(.pop)
        } else if let onUpload, camera.clips.isEmpty, shots.isEmpty, !camera.recording, countdown == 0 {
            SideTile(icon: "photo.on.rectangle.angled", title: "Upload", action: onUpload)
        } else {
            Color.clear.frame(width: 54, height: 54)
        }
    }

    private var ready: Bool {
        mode == .photo ? !shots.isEmpty : (!camera.clips.isEmpty && !camera.recording)
    }

    // The big button: tap to start / pause, or hold to film while you hold
    // (it grows, and sliding up zooms in).
    private var recordButton: some View {
        let filming = camera.live
        let limit = max(1, camera.maxSeconds)
        var marks: [Double] = []
        var sum = 0.0
        for clip in camera.clips {
            sum += clip.effective
            marks.append(sum / limit)
        }
        return RecordButton(photo: mode == .photo, filming: filming, pressed: pressStart != nil, held: heldClip,
                            progress: camera.total / limit, marks: marks)
            .contentShape(Circle())
            .gesture(DragGesture(minimumDistance: 0)
                .updating($pressing) { _, state, _ in state = true }
                .onChanged { value in
                    if pressStart == nil { pressDown() }
                    if heldClip, value.translation.height < -12 {
                        camera.setZoom(holdZoom + (-value.translation.height - 12) / 70, smooth: false)
                    }
                }
                .onEnded { _ in pressUp() })
            .allowsHitTesting(!merging)
            .opacity(merging ? 0.6 : 1)
            .sensoryFeedback(.impact(weight: .medium), trigger: filming)
            .accessibilityElement()
            .accessibilityLabel(mode == .photo ? "Take photo" : countdown > 0 ? "Cancel the timer" : filming ? "Stop filming" : "Film")
            .accessibilityHint(mode == .photo ? "" : "Tap to start and stop, or hold to film while you hold")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { shutter() }
    }

    // Under the camera (or on it, on a short phone): 15 s, 60 s or photos.
    private var modeBar: some View {
        let ink = ringLight ? Color(hex: 0x2A1620) : Color.white
        return HStack(spacing: 30) {
            ForEach(Mode.allCases, id: \.self) { m in
                Button { pickMode(m) } label: {
                    VStack(spacing: 5) {
                        Text(m.rawValue)
                            .font(.jakarta(15, .heavy))
                            .lineLimit(1)
                            .foregroundStyle(mode == m ? ink : ink.opacity(0.5))
                        Capsule().fill(Theme.gradient)
                            .frame(width: 18, height: 3)
                            .opacity(mode == m ? 1 : 0)
                    }
                    .frame(minWidth: 48, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(SoftPressStyle())
                .accessibilityLabel(m == .photo ? "Photo" : "\(m == .short ? 15 : 60) second video")
                .accessibilityAddTraits(mode == m ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(camera.recording ? 0.35 : 1)
        .allowsHitTesting(!camera.recording)
        .sensoryFeedback(.selection, trigger: mode)
        .animation(Motion.standard, value: mode)
    }

    // MARK: actions

    // Holding films straight away (no timer); a quick tap does the usual
    // thing when you let go.
    private func pressDown() {
        pressStart = .now
        guard mode != .photo, timer == 0, countdown == 0, !camera.recording, camera.canFilm else { return }
        error = nil
        holdZoom = camera.zoom
        camera.startClip()
        heldClip = camera.recording
    }

    private func pressUp() {
        let held = pressStart.map { Date.now.timeIntervalSince($0) } ?? 0
        pressStart = nil
        if heldClip {
            heldClip = false
            pinchStart = camera.zoom
            // Held: filming stops when you let go. A quick tap keeps
            // filming until you tap again.
            if held > 0.4 { camera.stopClip() }
            return
        }
        shutter()
    }

    private func pressCancelled() {
        pressStart = nil
        if heldClip {
            heldClip = false
            camera.stopClip()
        }
    }

    private func shutter() {
        error = nil
        if countdown > 0 || countdownJob != nil {
            countdownJob?.cancel()
            countdownJob = nil
            countdown = 0
            return
        }
        if mode != .photo && camera.recording {
            camera.stopClip()
            return
        }
        if mode != .photo && !camera.canFilm {
            if camera.running && !camera.paused {
                showHint("That's \(Int(camera.maxSeconds)) seconds: tap ✓ to carry on")
            }
            return
        }
        if timer > 0 {
            countdownJob = Task { await runCountdown() }
        } else {
            fire()
        }
    }

    private func runCountdown() async {
        for n in stride(from: timer, through: 1, by: -1) {
            countdown = n
            try? await Task.sleep(for: .seconds(1))
            if Task.isCancelled { return }
        }
        countdown = 0
        countdownJob = nil
        fire()
    }

    private func fire() {
        if mode == .photo {
            takePhoto()
        } else {
            camera.startClip()
        }
    }

    private func takePhoto() {
        guard shots.count < 10 else {
            showHint("10 photos at most: tap ✓ to carry on")
            return
        }
        if ringLight {
            // A burst of the front light for a selfie.
            Task {
                withAnimation(.easeOut(duration: 0.08)) { lightBurst = true }
                try? await Task.sleep(for: .milliseconds(160))
                camera.takePhoto()
                try? await Task.sleep(for: .milliseconds(160))
                withAnimation(.easeOut(duration: 0.3)) { lightBurst = false }
            }
        } else {
            camera.takePhoto()
            // The quick dark blink of the iPhone's camera.
            blink = true
            Task {
                try? await Task.sleep(for: .milliseconds(60))
                withAnimation(.easeOut(duration: 0.2)) { blink = false }
            }
        }
    }

    // The camera turns off by itself once this screen goes away.
    private func finish() async {
        if mode == .photo {
            onPhotos(shots, camera.filter)
            return
        }
        guard !merging, !camera.clips.isEmpty, !camera.recording else { return }
        withAnimation(Motion.fade) { merging = true }
        defer { withAnimation(Motion.fade) { merging = false } }
        do {
            let url = try await camera.makeVideo()
            onVideo(url, camera.filter)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func close() {
        if !camera.clips.isEmpty || !shots.isEmpty {
            confirmClose = true
        } else {
            leave()
        }
    }

    private func leave() {
        countdownJob?.cancel()
        camera.stop()
        onClose()
    }

    private func flip() {
        guard !camera.recording else { return }
        camera.flip()
        pinchStart = 1
        focusPoint = nil
    }

    private func toggleFlash() {
        camera.toggleFlash()
        if !camera.flash {
            showHint("Flash off")
        } else if camera.position == .front {
            showHint("Front light on: pick warm, cool or pink")
        } else {
            showHint(mode == .photo ? "Flash on" : "Light on")
        }
    }

    private func pickTone(_ tone: FrontLightTone) {
        withAnimation(.easeInOut(duration: 0.35)) { lightTone = tone }
        showHint("\(tone.title) light")
    }

    private func togglePanel(_ next: Panel) {
        withMotion(Motion.standard) { panel = panel == next ? nil : next }
    }

    private func pickSpeed(_ value: Double) {
        withMotion(Motion.standard) { camera.speed = value }
        if value == 1 {
            showHint("Normal speed")
        } else {
            showHint(value < 1 ? "Slow motion (\(SpeedPicker.label(value)))" : "Fast motion (\(SpeedPicker.label(value)))")
        }
    }

    private func pickFilter(_ filter: ReelFilter) {
        camera.setFilter(filter)
    }

    // Swiping sideways on the picture: the next or previous filter, with
    // its name shown big for a moment.
    private func swipeFilter(_ step: Int) {
        guard !camera.recording else { return }
        let all = ReelFilter.allCases
        guard let index = all.firstIndex(of: camera.filter) else { return }
        let next = all[(index + step + all.count) % all.count]
        camera.setFilter(next)
        filterTick += 1
        let tick = filterTick
        withAnimation(.snappy(duration: 0.2)) { filterName = next.rawValue }
        Task {
            try? await Task.sleep(for: .seconds(0.9))
            guard filterTick == tick else { return }
            withAnimation(.easeOut(duration: 0.3)) { filterName = nil }
        }
    }

    private func pickLens(_ lens: CameraLens) {
        camera.setZoom(lens.shown, smooth: true)
        pinchStart = lens.shown
        lensTick += 1
    }

    private func cycleTimer() {
        timer = timer == 0 ? 3 : timer == 3 ? 10 : 0
        showHint(timer == 0 ? "Timer off" : "\(timer)s timer: tap the button, then get ready")
    }

    private func toggleAlign() {
        withMotion(Motion.fade) { align.toggle() }
        if align { showHint("Line up with the end of your last clip") }
    }

    // First tap: the last clip turns red. Second tap: it's gone.
    private func deleteTapped() {
        disarmJob?.cancel()
        if armedDelete {
            withMotion(Motion.standard) {
                camera.deleteLast()
                armedDelete = false
            }
            if camera.clips.isEmpty { align = false }
            return
        }
        withMotion(Motion.fade) { armedDelete = true }
        showHint("Tap again to delete the last clip")
        disarmJob = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withMotion(Motion.fade) { armedDelete = false }
        }
    }

    private func pickMode(_ next: Mode) {
        guard next != mode, !camera.recording, countdown == 0 else { return }
        if next == .photo && !camera.clips.isEmpty {
            showHint("Finish or delete your clips to take photos")
            return
        }
        if next != .photo && !shots.isEmpty {
            showHint("Finish or delete your photos to film")
            return
        }
        if next == .short && camera.filmed > 15 {
            showHint("You've already filmed more than 15 seconds")
            return
        }
        withMotion(Motion.standard) {
            mode = next
            if next == .photo && panel == .speed { panel = nil }
        }
        camera.maxSeconds = next == .short ? 15 : 60
        camera.setPhotoMode(next == .photo)
    }

    private func tapFocus(_ point: CGPoint, _ spot: CGPoint, lock: Bool) {
        camera.focus(at: spot, lock: lock)
        exposureStart = 0
        focusTick += 1
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { focusPoint = point }
        if lock { showHint("Focus and light locked: tap anywhere to unlock") }
        scheduleFocusHide()
    }

    private func scheduleFocusHide() {
        focusJob?.cancel()
        focusJob = Task {
            try? await Task.sleep(for: .seconds(2.6))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) { focusPoint = nil }
        }
    }

    // Sliding up or down after tapping: brighter or darker.
    private func slide(_ amount: CGFloat, _ phase: CameraSurface.Phase) {
        if phase == .began { exposureStart = camera.exposure }
        camera.setExposure(exposureStart + Float(amount / 110))
        scheduleFocusHide()
    }

    private func pinch(_ scale: CGFloat, _ phase: CameraSurface.Phase) {
        switch phase {
        case .began:
            pinchStart = camera.zoom
        case .changed:
            camera.setZoom(pinchStart * scale, smooth: false)
        case .ended:
            camera.setZoom(pinchStart * scale, smooth: false)
            pinchStart = camera.zoom
        }
    }

    private func showHint(_ text: String) {
        hintTick += 1
        let tick = hintTick
        withAnimation(.snappy(duration: 0.25)) { hint = text }
        Task {
            try? await Task.sleep(for: .seconds(1.8))
            guard hintTick == tick else { return }
            withAnimation(.easeOut(duration: 0.3)) { hint = nil }
        }
    }

    // The front light turns the screen all the way up while it's on, and
    // puts your own brightness back after.
    private func brighten(_ on: Bool) {
        let screens = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.screen }
        guard let screen = screens.first else { return }
        if on {
            if savedBrightness == nil { savedBrightness = screen.brightness }
            screen.brightness = 1
        } else if let saved = savedBrightness {
            screen.brightness = saved
            savedBrightness = nil
        }
    }
}
