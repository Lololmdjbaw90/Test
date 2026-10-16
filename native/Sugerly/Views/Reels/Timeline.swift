import SwiftUI
import PhotosUI

// The timeline under the preview (like CapCut): the video's film strip, or
// the photos as slides as long as they show, and a bar for every text,
// sticker and photo on top. Drag a bar to move when it shows, pick it and
// drag its ends to make it shorter or longer, drag across the strip to
// scrub. Tap a slide to make it longer or shorter, move it or remove it.
//
// Kept calm on purpose: no boxes behind the bars, one colour per kind of
// bar, and the picked bar gets the iPhone's trim frame (white, with its
// handles inside it, so nothing sticks out or gets cut off at the edges).
struct ReelTimeline: View {
    let length: Double
    let playhead: Double
    let playing: Bool
    let thumbs: [UIImage]            // video film strip (the trimmed part)
    let slides: [UIImage]            // photos (empty for a video)
    @Binding var slideSeconds: [Double]
    @Binding var stickers: [TextSticker]
    @Binding var selected: UUID?
    @Binding var selectedSlide: Int?
    @Binding var photoItem: PhotosPickerItem?
    var onSeek: (Double) -> Void
    var onScrub: (Bool) -> Void
    var onTogglePlay: () -> Void
    var onAddText: () -> Void
    var onAddSticker: () -> Void
    var onEditText: (TextSticker) -> Void
    var onCheckpoint: () -> Void
    var onMoveSlide: (Int, Int) -> Void
    var onDeleteSlide: (Int) -> Void

    @State private var dragBase: (start: Double, end: Double)?
    // The bar being moved (it lifts while you hold it).
    @State private var lifting: UUID?
    @State private var scrubbing = false
    @State private var timingEditor = false

    private let trackHeight: CGFloat = 48
    private let laneHeight: CGFloat = 34
    private let rulerHeight: CGFloat = 16
    private let gap: CGFloat = 8
    private let barCorner: CGFloat = 9
    // The white trim handles inside a picked bar.
    private let tabWidth: CGFloat = 13
    private var isSlideshow: Bool { !slides.isEmpty }
    private var slideBounds: [Double] { Self.bounds(slideSeconds) }
    private var shortest: Double { isSlideshow ? 0.5 : 0.3 }

    var body: some View {
        VStack(spacing: 10) {
            controls
            GeometryReader { geo in
                let w = max(1, geo.size.width)
                ZStack(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: gap) {
                        ruler(w)
                        mainTrack(w)
                        lanes(w).frame(height: max(laneHeight + 8, geo.size.height - trackHeight - rulerHeight - gap * 2))
                    }
                    playheadLine(w, height: geo.size.height)
                }
            }
            selectionBar
        }
        .padding(.horizontal, 16)
        .sensoryFeedback(.selection, trigger: selected)
        .sensoryFeedback(.selection, trigger: selectedSlide)
        .sensoryFeedback(.impact(weight: .light), trigger: lifting) { _, new in new != nil }
        .sheet(isPresented: $timingEditor, onDismiss: { onScrub(false) }) {
            if let id = selected, let index = stickers.firstIndex(where: { $0.id == id }) {
                OverlayTimingEditor(sticker: $stickers[index], length: length, onSeek: onSeek) {
                    snap(id)
                }
                .presentationDetents([.medium, .large])
            }
        }
    }

    // MARK: top row

    private var controls: some View {
        HStack(spacing: 8) {
            Button(action: onTogglePlay) {
                Image(systemName: playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 36, height: 36)
                    .background(Theme.main, in: Circle())
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(BouncyStyle(scale: 0.88))
            .accessibilityLabel(playing ? "Pause" : "Play")
            (Text(Self.clock(playhead)).foregroundStyle(.white) + Text("  \(Self.clock(length))").foregroundStyle(.white.opacity(0.4)))
                .font(.jakarta(12, .heavy)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: 0)
            Button(action: onAddText) { addLabel("Text", "textformat") }
                .buttonStyle(BouncyStyle(scale: 0.9))
            Button(action: onAddSticker) { addLabel("Sticker", "star.fill") }
                .buttonStyle(BouncyStyle(scale: 0.9))
            PhotosPicker(selection: $photoItem, matching: .images) { addLabel("Photo", "photo.fill") }
                .buttonStyle(BouncyStyle(scale: 0.9))
        }
    }

    private func addLabel(_ title: String, _ icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 10, weight: .bold))
            Text(title).font(.jakarta(11, .heavy))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(EditorPalette.chip, in: Capsule())
    }

    // MARK: time ruler

    // A small tick and its time every step, a dot in between.
    private var rulerStep: Double {
        let raw = max(0.1, length) / 5
        return [0.5, 1, 2, 5, 10, 15, 30, 60].first { $0 >= raw } ?? 60
    }

    private func ruler(_ w: CGFloat) -> some View {
        let step = rulerStep
        let total = max(0.1, length)
        return Canvas { ctx, size in
            var t = 0.0
            while t <= total + 0.0001 {
                let x = min(size.width - 0.5, max(0.5, CGFloat(t / total) * size.width))
                var tick = Path()
                tick.move(to: CGPoint(x: x, y: size.height - 6))
                tick.addLine(to: CGPoint(x: x, y: size.height))
                ctx.stroke(tick, with: .color(.white.opacity(0.35)), lineWidth: 1)
                if t + step / 2 < total {
                    let hx = CGFloat((t + step / 2) / total) * size.width
                    ctx.fill(Path(ellipseIn: CGRect(x: hx - 1, y: size.height - 3, width: 2, height: 2)),
                             with: .color(.white.opacity(0.25)))
                }
                // The time sits just right of its tick, unless it would
                // run off the end.
                let label = ctx.resolve(Text(Self.seconds(t)).font(.jakarta(9, .bold)).foregroundStyle(.white.opacity(0.5)))
                if x + 4 + label.measure(in: size).width <= size.width {
                    ctx.draw(label, at: CGPoint(x: x + 4, y: size.height / 2 - 1), anchor: .leading)
                }
                t += step
            }
        }
        .frame(width: w, height: rulerHeight)
        .contentShape(Rectangle())
        .gesture(scrub(w, minimum: 0))
        .accessibilityHidden(true)
    }

    // MARK: main track (film strip or slides)

    @ViewBuilder
    private func mainTrack(_ w: CGFloat) -> some View {
        if isSlideshow {
            HStack(spacing: 3) {
                ForEach(slides.indices, id: \.self) { i in
                    let secs = slideSeconds.indices.contains(i) ? slideSeconds[i] : 3
                    let sw = max(12, CGFloat(secs / max(0.1, length)) * w - 3)
                    let picked = selectedSlide == i
                    Image(uiImage: slides[i]).resizable().scaledToFill()
                        .frame(width: sw, height: trackHeight).clipped()
                        .overlay(alignment: .bottomLeading) {
                            if sw > 30 {
                                Text(Self.seconds(secs)).font(.jakarta(9, .heavy)).foregroundStyle(.white)
                                    .monospacedDigit()
                                    .contentTransition(.numericText())
                                    .padding(.horizontal, 5).padding(.vertical, 2)
                                    .background(.black.opacity(0.45), in: Capsule())
                                    .padding(4)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.white, lineWidth: picked ? 2.5 : 0))
                        .opacity(selectedSlide == nil || picked ? 1 : 0.5)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selected = nil
                            selectedSlide = selectedSlide == i ? nil : i
                            if slideBounds.indices.contains(i) { onSeek(slideBounds[i]) }
                        }
                }
            }
            .frame(width: w, height: trackHeight, alignment: .leading)
            .motion(Motion.standard, value: selectedSlide)
            .gesture(scrub(w, minimum: 8))
        } else {
            HStack(spacing: 0) {
                ForEach(thumbs.indices, id: \.self) { i in
                    Image(uiImage: thumbs[i]).resizable().scaledToFill()
                        .frame(width: w / CGFloat(max(1, thumbs.count)), height: trackHeight).clipped()
                }
            }
            .frame(width: w, height: trackHeight, alignment: .leading)
            .background(.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.08), lineWidth: 1))
            .contentShape(Rectangle())
            .gesture(scrub(w, minimum: 0))
        }
    }

    private func scrub(_ w: CGFloat, minimum: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: minimum)
            .onChanged { v in
                if !scrubbing {
                    scrubbing = true
                    onScrub(true)
                }
                onSeek(Double(min(max(0, v.location.x), w) / w) * length)
            }
            .onEnded { _ in
                scrubbing = false
                onScrub(false)
            }
    }

    // A white line with a small rounded knob over the ruler. It stays inside
    // the timeline at both ends, and the knob grows a little while you scrub.
    private func playheadLine(_ w: CGFloat, height: CGFloat) -> some View {
        let knob: CGFloat = 10
        let x = CGFloat(min(max(0, playhead), length) / max(0.1, length)) * w
        let center = min(max(knob / 2, x), w - knob / 2)
        return VStack(spacing: -3) {
            RoundedRectangle(cornerRadius: 3.5, style: .continuous).fill(.white)
                .frame(width: knob, height: 15)
                .scaleEffect(scrubbing ? 1.18 : 1, anchor: .top)
            Capsule().fill(.white).frame(width: 2)
        }
        .frame(width: knob, height: height)
        .shadow(color: .black.opacity(0.4), radius: 1.5)
        .offset(x: center - knob / 2)
        .motion(Motion.release, value: scrubbing)
        .allowsHitTesting(false)
    }

    // MARK: overlay lanes

    private func lanes(_ w: CGFloat) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 6) {
                if stickers.isEmpty {
                    Button(action: onAddText) {
                        HStack(spacing: 7) {
                            Image(systemName: "plus.circle.fill").font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Theme.main)
                            Text("Add text, stickers or photos")
                                .font(.jakarta(12, .semibold)).foregroundStyle(.white.opacity(0.6))
                                .lineLimit(1).minimumScaleFactor(0.8)
                        }
                        .frame(width: w, height: laneHeight + 4)
                        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: barCorner, style: .continuous))
                    }
                    .buttonStyle(SoftPressStyle())
                    .transition(.opacity)
                }
                ForEach(stickers) { sticker in
                    lane(sticker, w)
                        .transition(.pop)
                }
            }
            // Room for a lifted bar's shadow (and the trim handles' wider
            // touch area) inside the scrolling area, so neither is cut off.
            .padding(.horizontal, 18)
            .padding(.vertical, 6)
            .motion(Motion.standard, value: stickers.map(\.id))
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDisabled(dragBase != nil)
        .padding(.horizontal, -18)
    }

    private func lane(_ sticker: TextSticker, _ w: CGFloat) -> some View {
        let total = max(0.1, length)
        let start = min(max(0, sticker.start), max(0, length - min(shortest, length)))
        let end = max(start, min(sticker.end ?? length, length))
        let isSelected = selected == sticker.id
        // A picked bar is never narrower than its two handles.
        let minWidth: CGFloat = isSelected ? tabWidth * 2 + 10 : 16
        let x0 = min(CGFloat(start / total) * w, max(0, w - minWidth))
        let x1 = min(w, max(x0 + minWidth, CGFloat(end / total) * w))
        let lifted = lifting == sticker.id
        return ZStack(alignment: .leading) {
            Color.clear
                .frame(width: w, height: laneHeight)
                .contentShape(Rectangle())
                .onTapGesture { selected = nil }
            bar(sticker, selected: isSelected, dimmed: selected != nil && !isSelected, lifted: lifted,
                width: x1 - x0, span: end - start)
                .frame(width: x1 - x0, height: laneHeight)
                .offset(x: x0)
                .zIndex(1)
                .onTapGesture {
                    selectedSlide = nil
                    selected = sticker.id
                    onSeek(start)
                }
                .highPriorityGesture(moveGesture(sticker.id, w))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Text track: \(label(sticker))")
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("overlay-track-\(sticker.id)")
            if isSelected {
                // Touch areas over the handles, wider than they look.
                grabArea(left: true)
                    .offset(x: x0 - 14)
                    .zIndex(2)
                    .highPriorityGesture(edgeGesture(sticker.id, w, left: true))
                    .accessibilityIdentifier("overlay-start")
                grabArea(left: false)
                    .offset(x: x1 - tabWidth - 13)
                    .zIndex(2)
                    .highPriorityGesture(edgeGesture(sticker.id, w, left: false))
                    .accessibilityIdentifier("overlay-end")
            }
        }
        .frame(width: w, height: laneHeight, alignment: .leading)
        .coordinateSpace(name: sticker.id)
    }

    private func bar(_ s: TextSticker, selected: Bool, dimmed: Bool, lifted: Bool, width: CGFloat, span: Double) -> some View {
        let shape = RoundedRectangle(cornerRadius: barCorner, style: .continuous)
        return shape.fill(barColor(for: s))
            .overlay(alignment: .leading) {
                HStack(spacing: 6) {
                    if let image = s.image {
                        Image(uiImage: image).resizable().scaledToFill()
                            .frame(width: 20, height: 20)
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    } else {
                        Image(systemName: s.isEmoji ? "face.smiling" : "textformat").font(.system(size: 10, weight: .bold))
                            .opacity(0.85)
                    }
                    Text(label(s)).font(.jakarta(11, .bold)).lineLimit(1)
                    if selected && width > 120 {
                        Spacer(minLength: 4)
                        Text(Self.seconds((span * 10).rounded() / 10)).font(.jakarta(10, .heavy)).monospacedDigit()
                            .contentTransition(.numericText())
                            .opacity(0.85)
                            .transition(.opacity)
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, selected ? tabWidth + 7 : 9)
            }
            .clipShape(shape)
            .overlay {
                if selected {
                    TrimFrame(corner: barCorner, tab: tabWidth)
                        .transition(frameIn)
                }
            }
            .scaleEffect(lifted ? 1.04 : 1)
            .shadow(color: .black.opacity(lifted ? 0.4 : 0), radius: lifted ? 8 : 0, y: lifted ? 5 : 0)
            .opacity(dimmed ? 0.5 : 1)
            .motion(Motion.standard, value: selected)
            .motion(Motion.release, value: lifted)
            .motion(Motion.fade, value: dimmed)
    }

    // The trim frame settles onto the bar from a touch bigger.
    private var frameIn: AnyTransition {
        Motion.reduced ? .opacity : .opacity.combined(with: .scale(scale: 1.08))
    }

    // One calm colour for each kind of bar.
    private func barColor(for s: TextSticker) -> Color {
        if s.framed { return Color(hex: 0x5FA8FF) }
        if s.image != nil { return Color(hex: 0x9F86FF) }
        return Theme.main
    }

    private func label(_ s: TextSticker) -> String {
        if s.framed { return "Photo" }
        if s.image != nil { return "Sticker" }
        return s.text.replacingOccurrences(of: "\n", with: " ")
    }

    // Where a finger can grab a handle: the handle plus some room around it.
    private func grabArea(left: Bool) -> some View {
        Color.clear
            .frame(width: tabWidth + 27, height: laneHeight + 8)
            .contentShape(Rectangle())
            .accessibilityElement()
            .accessibilityLabel(left ? "Trim start" : "Trim end")
            .accessibilityAddTraits(.isButton)
    }

    // Drag the whole bar: same length, new time.
    private func moveGesture(_ id: UUID, _ w: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .named(id))
            .onChanged { v in
                guard let i = stickers.firstIndex(where: { $0.id == id }) else { return }
                if dragBase == nil {
                    onScrub(true)
                    onCheckpoint()
                    selectedSlide = nil
                    selected = id
                    lifting = id
                    dragBase = (stickers[i].start, min(length, stickers[i].end ?? length))
                }
                guard let base = dragBase else { return }
                let span = max(shortest, base.end - base.start)
                let dt = Double(v.translation.width / w) * length
                let start = min(max(0, base.start + dt), max(0, length - span))
                stickers[i].start = start
                let end = start + span
                stickers[i].end = end >= length - 0.05 ? nil : end
                onSeek(start)
            }
            .onEnded { _ in
                dragBase = nil
                lifting = nil
                snap(id)
                onScrub(false)
            }
    }

    // Drag an end: shorter or longer.
    private func edgeGesture(_ id: UUID, _ w: CGFloat, left: Bool) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(id))
            .onChanged { v in
                guard let i = stickers.firstIndex(where: { $0.id == id }) else { return }
                if dragBase == nil {
                    onScrub(true)
                    onCheckpoint()
                    dragBase = (stickers[i].start, min(length, stickers[i].end ?? length))
                }
                guard let base = dragBase else { return }
                let dt = Double(v.translation.width / w) * length
                if left {
                    let start = min(max(0, base.start + dt), max(0, base.end - shortest))
                    stickers[i].start = start
                    onSeek(start)
                } else {
                    let end = max(min(length, base.end + dt), base.start + shortest)
                    stickers[i].end = end >= length - 0.05 ? nil : end
                    onSeek(max(base.start, end - 0.05))
                }
            }
            .onEnded { _ in
                dragBase = nil
                snap(id)
                onScrub(false)
            }
    }

    // Slideshows: bars line up with whole slides, so what you see is what
    // gets posted (each picture is posted with the overlays on it).
    private func snap(_ id: UUID) {
        guard isSlideshow, let i = stickers.firstIndex(where: { $0.id == id }) else { return }
        let b = slideBounds
        guard b.count > 1 else { return }
        func nearest(_ t: Double) -> Double { b.min { abs($0 - t) < abs($1 - t) } ?? t }
        var start = nearest(stickers[i].start)
        if start >= length - 0.01 { start = b[b.count - 2] }
        var end = nearest(stickers[i].end ?? length)
        if end <= start + 0.01 { end = b.first { $0 > start + 0.01 } ?? length }
        withMotion(Motion.standard) {
            stickers[i].start = start
            stickers[i].end = end >= length - 0.05 ? nil : end
        }
    }

    // MARK: bottom row

    // What the row under the timeline shows, so it can slide from one to
    // the next.
    private var selectionKey: String {
        if let selected { return selected.uuidString }
        if let selectedSlide { return "slide-\(selectedSlide)" }
        return "none"
    }

    private var selectionBar: some View {
        ZStack {
            selectionContent
        }
        .frame(height: 34)
        .frame(maxWidth: .infinity)
        .motion(Motion.standard, value: selectionKey)
    }

    @ViewBuilder
    private var selectionContent: some View {
        if let id = selected, let sticker = stickers.first(where: { $0.id == id }) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if sticker.image == nil { chip("Edit", "pencil") { onEditText(sticker) } }
                    chip("Timing", "clock") { onCheckpoint(); onScrub(true); timingEditor = true }
                    chip(isSlideshow ? "From this slide" : "Start here", "arrow.right.to.line") { setStart(id) }
                    chip(isSlideshow ? "To this slide" : "End here", "arrow.left.to.line") { setEnd(id) }
                    chip("Whole reel", "arrow.left.and.right") { whole(id) }
                    chip("Delete", "trash.fill", danger: true) { delete(id) }
                }
            }
            .id(id)
            .transition(.rise)
        } else if let i = selectedSlide, slideSeconds.indices.contains(i) {
            HStack(spacing: 8) {
                chip("", "chevron.left") { onMoveSlide(i, i - 1) }
                    .disabled(i == 0).opacity(i == 0 ? 0.4 : 1)
                chip("", "minus") { changeSlide(i, -0.5) }
                Text("Slide \(i + 1) · \(Self.seconds(slideSeconds[i]))")
                    .font(.jakarta(12, .bold)).foregroundStyle(.white).monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1).minimumScaleFactor(0.8)
                chip("", "plus") { changeSlide(i, 0.5) }
                chip("", "chevron.right") { onMoveSlide(i, i + 1) }
                    .disabled(i >= slides.count - 1).opacity(i >= slides.count - 1 ? 0.4 : 1)
                Spacer(minLength: 0)
                if slides.count > 1 { chip("", "trash.fill", danger: true) { onDeleteSlide(i) } }
            }
            .transition(.rise)
        } else {
            Text(isSlideshow ? "Tap a slide to change how long it shows · drag a bar to move it" : "Drag the strip to scrub · drag a bar to move it · tap it to trim")
                .font(.jakarta(11, .semibold)).foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity)
                .transition(.opacity)
        }
    }

    private func chip(_ title: String, _ icon: String, danger: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 11, weight: .bold))
                if !title.isEmpty { Text(title).font(.jakarta(11, .heavy)) }
            }
            .foregroundStyle(danger ? Palette.danger : .white)
            .padding(.horizontal, title.isEmpty ? 0 : 12)
            .frame(minWidth: 34, minHeight: 32)
            .background(danger ? AnyShapeStyle(Palette.danger.opacity(0.14)) : AnyShapeStyle(EditorPalette.chip), in: Capsule())
        }
        .buttonStyle(BouncyStyle(scale: 0.9))
    }

    private func setStart(_ id: UUID) {
        guard let i = stickers.firstIndex(where: { $0.id == id }) else { return }
        onCheckpoint()
        let end = min(length, stickers[i].end ?? length)
        stickers[i].start = min(max(0, playhead), max(0, end - shortest))
        snap(id)
    }

    private func setEnd(_ id: UUID) {
        guard let i = stickers.firstIndex(where: { $0.id == id }) else { return }
        onCheckpoint()
        var end = max(playhead, stickers[i].start + shortest)
        // On a slideshow, "to this slide" means up to the end of it.
        if isSlideshow, let next = slideBounds.first(where: { $0 > playhead + 0.01 }) { end = max(end, next) }
        stickers[i].end = end >= length - 0.05 ? nil : min(end, length)
        snap(id)
    }

    private func whole(_ id: UUID) {
        guard let i = stickers.firstIndex(where: { $0.id == id }) else { return }
        onCheckpoint()
        withMotion(Motion.standard) {
            stickers[i].start = 0
            stickers[i].end = nil
        }
    }

    private func delete(_ id: UUID) {
        onCheckpoint()
        withMotion(Motion.standard) { stickers.removeAll { $0.id == id } }
        selected = nil
    }

    private func changeSlide(_ i: Int, _ delta: Double) {
        guard slideSeconds.indices.contains(i) else { return }
        let next = min(10, max(1, slideSeconds[i] + delta))
        guard next != slideSeconds[i] else { return }
        onCheckpoint()
        let old = slideBounds
        withMotion(Motion.standard) {
            slideSeconds[i] = next
            Self.remap(&stickers, from: old, to: Self.bounds(slideSeconds))
        }
    }

    // MARK: helpers (shared with the studio)

    // Trimming a video must not leave an overlay beyond its new end.
    static func clamp(_ stickers: inout [TextSticker], length: Double) {
        let minimum = min(0.3, max(0, length))
        for index in stickers.indices {
            stickers[index].start = min(max(0, stickers[index].start), max(0, length - minimum))
            if let end = stickers[index].end {
                let finish = max(stickers[index].start + minimum, min(end, length))
                stickers[index].end = finish >= length ? nil : finish
            }
        }
    }

    // Where each slide starts, plus where the last one ends.
    static func bounds(_ seconds: [Double]) -> [Double] {
        seconds.reduce(into: [Double(0)]) { acc, s in acc.append((acc.last ?? 0) + s) }
    }

    // Keeps overlays on the same slides when slide lengths change.
    static func remap(_ stickers: inout [TextSticker], from old: [Double], to new: [Double]) {
        guard old.count == new.count, old.count > 1 else { return }
        func move(_ t: Double) -> Double {
            for j in 0..<(old.count - 1) where t <= old[j + 1] + 0.001 {
                let span = old[j + 1] - old[j]
                let f = span > 0 ? (t - old[j]) / span : 0
                return new[j] + max(0, min(1, f)) * (new[j + 1] - new[j])
            }
            return new.last ?? t
        }
        for i in stickers.indices {
            stickers[i].start = move(stickers[i].start)
            if let e = stickers[i].end { stickers[i].end = move(e) }
        }
    }

    // A slide from `from` to `to` was removed: later overlays move up, ones
    // that were only on that slide go.
    static func removeSlide(_ stickers: inout [TextSticker], from: Double, to: Double, newLength: Double) {
        let gap = to - from
        func shift(_ t: Double) -> Double { t <= from ? t : (t >= to ? t - gap : from) }
        stickers = stickers.compactMap { s in
            var s = s
            s.start = shift(s.start)
            if let e = s.end {
                let end = shift(e)
                if end <= s.start + 0.01 { return nil }
                s.end = end
            } else if s.start >= newLength - 0.01 {
                return nil
            }
            return s
        }
    }

    static func clock(_ t: Double) -> String {
        let t = max(0, t)
        return String(format: "%ld:%04.1f", Int(t) / 60, t.truncatingRemainder(dividingBy: 60))
    }

    static func seconds(_ t: Double) -> String {
        t.rounded() == t ? "\(Int(t))s" : String(format: "%.1fs", t)
    }
}

// The iPhone's trim frame around the picked bar: a white outline with a
// handle at each end, drawn inside the bar so it's never cut off.
private struct TrimFrame: View {
    let corner: CGFloat
    let tab: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(.white, lineWidth: 2.5)
            HStack(spacing: 0) {
                handle(leading: true)
                Spacer(minLength: 0)
                handle(leading: false)
            }
        }
        .allowsHitTesting(false)
    }

    private func handle(leading: Bool) -> some View {
        UnevenRoundedRectangle(topLeadingRadius: leading ? corner : 0,
                               bottomLeadingRadius: leading ? corner : 0,
                               bottomTrailingRadius: leading ? 0 : corner,
                               topTrailingRadius: leading ? 0 : corner,
                               style: .continuous)
            .fill(.white)
            .frame(width: tab)
            .overlay(Capsule().fill(Theme.main).frame(width: 2.5, height: 12))
    }
}
