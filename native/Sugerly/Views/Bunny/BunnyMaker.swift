import SwiftUI
import UIKit
import Photos

// The bunny maker: your bunny on a little stage at the top, then a row of
// tabs (fur, bow, collar, outfit, face, extras, scene) and the choices for
// the one you picked. Changes show straight away; Done keeps them. You can
// shuffle, save her to Photos, or make her your profile picture.
struct BunnyMakerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var store = BunnyStore.shared
    @State private var look = BunnyLook()
    @State private var tab: Tab = .fur
    @State private var loaded = false
    @State private var busy = false
    @State private var cheer = 0
    @State private var shuffles = 0

    enum Tab: String, CaseIterable, Identifiable {
        case fur, bow, collar, outfit, face, extras, scene
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
        var icon: String {
            switch self {
            case .fur: return "hare.fill"
            case .bow: return "gift.fill"
            case .collar: return "seal.fill"
            case .outfit: return "tshirt.fill"
            case .face: return "face.smiling.inverse"
            case .extras: return "crown.fill"
            case .scene: return "photo.fill"
            }
        }
        var candy: Candy {
            switch self {
            case .fur: return .berry
            case .bow: return .peach
            case .collar: return .grape
            case .outfit: return .sky
            case .face: return .lemon
            case .extras: return .lemon
            case .scene: return .mint
            }
        }
        var part: BunnyPart? {
            switch self {
            case .fur: return .fur
            case .bow: return .bow
            case .collar: return .collar
            case .outfit: return .outfit
            default: return nil
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                stage
                tabs
                choices
                    .id(tab)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
                actions
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 40)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .sugarBackground()
        .navigationTitle("Bunny maker")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !loaded else { return }
            store.use(model.me?.email ?? "")
            look = store.look
            loaded = true
        }
        .onChange(of: look) { _, next in if loaded { store.save(next) } }
        .sensoryFeedback(.selection, trigger: look)
        .sensoryFeedback(.success, trigger: cheer)
    }

    // MARK: stage

    private var stage: some View {
        BunnyPortrait(look: look)
            .frame(height: 340)
            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 32, style: .continuous).strokeBorder(Palette.rim(0.7), lineWidth: 1.5))
            .shadow(color: Theme.glow(0.22), radius: 18, y: 8)
            .overlay(alignment: .topTrailing) {
                Button {
                    shuffles += 1
                    withAnimation(Motion.playful) { look = BunnyLook.random() }
                } label: {
                    Image(systemName: "dice.fill")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Theme.main)
                        .symbolEffect(.bounce, value: shuffles)
                        .rotationEffect(.degrees(Double(shuffles) * 90))
                        .animation(Motion.playful, value: shuffles)
                        .frame(width: 44, height: 44)
                        .background(.white.opacity(0.9), in: Circle())
                        .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
                }
                .buttonStyle(BouncyStyle(scale: 0.88))
                .padding(14)
                .accessibilityLabel("Surprise me")
            }
            .overlay(alignment: .bottomLeading) {
                Text("Tap her!")
                    .font(.jakarta(12, .bold)).foregroundStyle(Palette.text2)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.white.opacity(0.85), in: Capsule())
                    .padding(14)
                    .accessibilityHidden(true)
            }
    }

    // MARK: tabs

    private var tabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Tab.allCases) { item in
                    let on = tab == item
                    Button {
                        withAnimation(Motion.playful) { tab = item }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: item.icon).font(.system(size: 13, weight: .bold))
                                .symbolEffect(.bounce, value: on)
                            Text(item.label).font(.jakarta(14, .semibold)).lineLimit(1)
                        }
                        .foregroundStyle(on ? .white : Palette.text2)
                        .padding(.horizontal, 14).frame(height: 38)
                        .background {
                            if on {
                                Capsule().fill(item.candy.gradient)
                                    .shadow(color: item.candy.color.softGlow(0.35), radius: 6, y: 3)
                            } else {
                                Capsule().fill(Palette.surface)
                                    .overlay(Capsule().strokeBorder(Palette.border, lineWidth: 1))
                            }
                        }
                    }
                    .buttonStyle(BouncyStyle(scale: 0.92))
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(.vertical, 4)
        }
        .scrollClipDisabled()
    }

    // MARK: choices

    @ViewBuilder
    private var choices: some View {
        if let part = tab.part {
            swatches(part)
        } else if tab == .face {
            tiles(BunnyFace.allCases.map { ($0.id, $0.label, $0.icon) }, selected: look.face.id) { id in
                if let face = BunnyFace(rawValue: id) { look.face = face }
            }
        } else if tab == .extras {
            tiles(BunnyExtra.allCases.map { ($0.id, $0.label, $0.icon) }, selected: look.extra.id) { id in
                if let extra = BunnyExtra(rawValue: id) { look.extra = extra }
            }
        } else {
            scenes
        }
    }

    private func swatches(_ part: BunnyPart) -> some View {
        let picked = look.index(part)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 14) {
            ForEach(Array(part.tints.enumerated()), id: \.element.id) { i, tint in
                let on = picked == i
                Button {
                    withAnimation(Motion.playful) { look.set(part, i) }
                } label: {
                    VStack(spacing: 6) {
                        Circle()
                            .fill(LinearGradient(colors: [Color(hex: Palette.mix(tint.swatch, 0xFFFFFF, 0.35)), Color(hex: tint.swatch)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .overlay(Circle().fill(LinearGradient(colors: [.white.opacity(0.55), .clear], startPoint: .top, endPoint: .center)).padding(3))
                            .overlay {
                                if on {
                                    Image(systemName: "checkmark").font(.system(size: 16, weight: .heavy)).foregroundStyle(.white)
                                        .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                                        .transition(.scale.combined(with: .opacity))
                                }
                            }
                            .frame(width: 52, height: 52)
                            .padding(4)
                            .overlay(Circle().strokeBorder(on ? Color(hex: tint.swatch) : .clear, lineWidth: 3))
                            .scaleEffect(on ? 1.06 : 1)
                            .shadow(color: Color(hex: tint.swatch).softGlow(on ? 0.45 : 0.18), radius: on ? 8 : 4, y: 3)
                        Text(tint.name).font(.jakarta(12, on ? .bold : .medium))
                            .foregroundStyle(on ? Palette.text : Palette.text2)
                            .lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(BouncyStyle(scale: 0.9))
                .accessibilityLabel("\(part.label): \(tint.name)")
                .accessibilityAddTraits(on ? .isSelected : [])
                .modifier(ChoicePop(index: i))
            }
        }
        .padding(16)
        .sugarCard(radius: 24)
    }

    private func tiles(_ items: [(String, String, String)], selected: String, pick: @escaping (String) -> Void) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
            ForEach(Array(items.enumerated()), id: \.element.0) { i, item in
                let on = selected == item.0
                Button {
                    withAnimation(Motion.playful) { pick(item.0) }
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: item.2)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(on ? .white : Theme.main)
                            .symbolEffect(.bounce, value: on)
                            .frame(width: 50, height: 50)
                            .background {
                                if on {
                                    Circle().fill(Theme.candy).shadow(color: Theme.glow(0.3), radius: 6, y: 3)
                                } else {
                                    Circle().fill(Theme.soft)
                                }
                            }
                        Text(item.1).font(.jakarta(13, .semibold))
                            .foregroundStyle(on ? Palette.text : Palette.text2)
                            .lineLimit(1).minimumScaleFactor(0.75)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(on ? Theme.soft : Color.clear, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(BouncyStyle(scale: 0.92))
                .accessibilityLabel(item.1)
                .accessibilityAddTraits(on ? .isSelected : [])
                .modifier(ChoicePop(index: i))
            }
        }
        .padding(12)
        .sugarCard(radius: 24)
    }

    private var scenes: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 12) {
            ForEach(Array(BunnyScene.allCases.enumerated()), id: \.element.id) { i, scene in
                let on = look.scene == scene
                Button {
                    withAnimation(Motion.playful) { look.scene = scene }
                } label: {
                    VStack(spacing: 6) {
                        BunnySceneView(scene: scene, animated: false)
                            .frame(height: 84)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(on ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Palette.border), lineWidth: on ? 3 : 1))
                            .overlay(alignment: .topTrailing) {
                                if on {
                                    Image(systemName: "checkmark.circle.fill").font(.system(size: 18)).foregroundStyle(.white, Theme.main)
                                        .padding(6).transition(.scale.combined(with: .opacity))
                                }
                            }
                            .scaleEffect(on ? 1.03 : 1)
                        Text(scene.label).font(.jakarta(12, on ? .bold : .medium))
                            .foregroundStyle(on ? Palette.text : Palette.text2).lineLimit(1)
                    }
                }
                .buttonStyle(BouncyStyle(scale: 0.93))
                .accessibilityLabel("Scene: \(scene.label)")
                .accessibilityAddTraits(on ? .isSelected : [])
                .modifier(ChoicePop(index: i))
            }
        }
        .padding(12)
        .sugarCard(radius: 24)
    }

    // MARK: actions

    private var actions: some View {
        VStack(spacing: 10) {
            Button { Task { await useAsPicture() } } label: {
                HStack(spacing: 8) {
                    if busy { ProgressView().tint(.white) } else { Image(systemName: "person.crop.circle.fill") }
                    Text("Use as my profile picture")
                }
            }
            .buttonStyle(GradientButtonStyle(height: 52))
            .disabled(busy || model.me == nil)
            HStack(spacing: 10) {
                Button { Task { await saveToPhotos() } } label: {
                    Label("Save to Photos", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(OutlineButtonStyle(fullWidth: true))
                Button {
                    withAnimation(Motion.playful) { look = BunnyLook() }
                } label: {
                    Label("Start over", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(OutlineButtonStyle(fullWidth: true))
            }
        }
    }

    private func useAsPicture() async {
        guard !busy, let image = BunnyPortrait.render(look, side: 720), let data = image.pngData() else { return }
        busy = true
        defer { busy = false }
        do {
            let url = try await StorageClient.upload(data, contentType: "image/png", fileExtension: "png")
            try await model.updateMe(["profile_picture": url])
            cheer += 1
            model.showToast("Your bunny is your profile picture now", icon: "hare.fill")
        } catch {
            model.showToast("Couldn't change your picture. Try again.", error: true)
        }
    }

    private func saveToPhotos() async {
        guard let image = BunnyPortrait.render(look, side: 1080), let data = image.pngData() else { return }
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            model.showToast("Allow Sugerly to add to Photos in Settings.", error: true)
            return
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
            }
            cheer += 1
            model.showToast("Saved to Photos", icon: "checkmark.circle.fill")
        } catch {
            model.showToast("Couldn't save it. Try again.", error: true)
        }
    }
}

// Choices pop in one after another when a tab opens.
private struct ChoicePop: ViewModifier {
    let index: Int
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(shown || reduceMotion ? 1 : 0.6)
            .opacity(shown || reduceMotion ? 1 : 0)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(Motion.playful.delay(Double(min(index, 10)) * 0.035)) { shown = true }
            }
    }
}
