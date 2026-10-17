import SwiftUI
import UIKit
import AVFoundation

// The live camera picture, and everything your fingers do on it: tap to
// focus there, hold to lock focus and light, tap twice to flip, pinch to
// zoom, swipe sideways for the next filter, and slide up or down (after
// tapping) for brighter or darker.
struct CameraSurface: UIViewRepresentable {
    enum Phase { case began, changed, ended }

    let session: AVCaptureSession
    let renderer: FilterRenderer
    // A filter is on: its picture covers the plain one.
    var filtered: Bool
    // Sliding changes brightness (only while the focus square shows).
    var canSlide: Bool
    // Where you touched, on the screen and in the camera's own 0…1 space.
    var onTap: (CGPoint, CGPoint) -> Void
    var onHold: (CGPoint, CGPoint) -> Void
    var onDoubleTap: () -> Void
    var onPinch: (CGFloat, Phase) -> Void
    var onSwipe: (Int) -> Void
    var onSlide: (CGFloat, Phase) -> Void

    final class Surface: UIView {
        override static var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        var filterView: FilterSurfaceView?
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: CameraSurface
        // Which way the current one-finger drag goes: 1 sideways, 2 up and down.
        private var axis = 0

        init(_ parent: CameraSurface) { self.parent = parent }

        private func points(_ gesture: UIGestureRecognizer) -> (CGPoint, CGPoint)? {
            guard let view = gesture.view as? Surface else { return nil }
            let point = gesture.location(in: view)
            return (point, view.preview.captureDevicePointConverted(fromLayerPoint: point))
        }

        @objc func tapped(_ gesture: UITapGestureRecognizer) {
            guard let hit = points(gesture) else { return }
            parent.onTap(hit.0, hit.1)
        }

        @objc func doubleTapped(_ gesture: UITapGestureRecognizer) {
            parent.onDoubleTap()
        }

        @objc func held(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began, let hit = points(gesture) else { return }
            parent.onHold(hit.0, hit.1)
        }

        @objc func pinched(_ gesture: UIPinchGestureRecognizer) {
            switch gesture.state {
            case .began: parent.onPinch(1, .began)
            case .changed: parent.onPinch(gesture.scale, .changed)
            case .ended, .cancelled, .failed: parent.onPinch(gesture.scale, .ended)
            default: break
            }
        }

        @objc func panned(_ gesture: UIPanGestureRecognizer) {
            let moved = gesture.translation(in: gesture.view)
            switch gesture.state {
            case .began:
                let speed = gesture.velocity(in: gesture.view)
                axis = abs(speed.x) > abs(speed.y) ? 1 : (parent.canSlide ? 2 : 0)
                if axis == 2 { parent.onSlide(0, .began) }
            case .changed:
                if axis == 2 { parent.onSlide(-moved.y, .changed) }
            case .ended:
                if axis == 1 {
                    let speed = gesture.velocity(in: gesture.view)
                    if abs(moved.x) > 60 || abs(speed.x) > 500 { parent.onSwipe(moved.x < 0 ? 1 : -1) }
                } else if axis == 2 {
                    parent.onSlide(-moved.y, .ended)
                }
                axis = 0
            case .cancelled, .failed:
                if axis == 2 { parent.onSlide(-moved.y, .ended) }
                axis = 0
            default:
                break
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> Surface {
        let view = Surface()
        view.backgroundColor = .black
        view.preview.session = session
        view.preview.videoGravity = .resizeAspectFill
        let coordinator = context.coordinator
        let double = UITapGestureRecognizer(target: coordinator, action: #selector(Coordinator.doubleTapped(_:)))
        double.numberOfTapsRequired = 2
        let single = UITapGestureRecognizer(target: coordinator, action: #selector(Coordinator.tapped(_:)))
        single.require(toFail: double)
        let hold = UILongPressGestureRecognizer(target: coordinator, action: #selector(Coordinator.held(_:)))
        hold.minimumPressDuration = 0.6
        let pinch = UIPinchGestureRecognizer(target: coordinator, action: #selector(Coordinator.pinched(_:)))
        let pan = UIPanGestureRecognizer(target: coordinator, action: #selector(Coordinator.panned(_:)))
        pan.maximumNumberOfTouches = 1
        for gesture in [double, single, hold, pinch, pan] as [UIGestureRecognizer] {
            view.addGestureRecognizer(gesture)
        }
        showFilter(on: view)
        return view
    }

    func updateUIView(_ view: Surface, context: Context) {
        context.coordinator.parent = self
        showFilter(on: view)
    }

    static func dismantleUIView(_ view: Surface, coordinator: Coordinator) {
        coordinator.parent.renderer.deliver = nil
    }

    // A fresh filter layer each time a filter goes on (so the last filtered
    // picture never flashes up), gone again when it's off.
    private func showFilter(on view: Surface) {
        if filtered, view.filterView == nil {
            let surface = FilterSurfaceView(frame: view.bounds)
            surface.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(surface)
            view.filterView = surface
            renderer.deliver = { [weak surface] sample in surface?.show(sample) }
        } else if !filtered, let surface = view.filterView {
            renderer.deliver = nil
            surface.removeFromSuperview()
            view.filterView = nil
        }
    }
}

// The filtered camera: the camera's frames, with the filter on, queued on a
// display layer that fills the window like the camera itself.
final class FilterSurfaceView: UIView {
    private let display = AVSampleBufferDisplayLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        display.videoGravity = .resizeAspectFill
        layer.addSublayer(display)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        display.frame = bounds
        CATransaction.commit()
    }

    func show(_ sample: CMSampleBuffer) {
        if display.status == .failed { display.flush() }
        guard display.isReadyForMoreMediaData else { return }
        display.enqueue(sample)
    }
}
