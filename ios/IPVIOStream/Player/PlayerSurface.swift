import AVKit
import SwiftUI

/// Video layer (AVPlayerLayer) without any system controls, plus Picture in Picture for it.
struct PlayerSurface: UIViewRepresentable {
    @ObservedObject var engine: PlayerEngine

    final class LayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    func makeUIView(context: Context) -> LayerView {
        let v = LayerView()
        v.backgroundColor = .black
        v.playerLayer.player = engine.player
        v.playerLayer.videoGravity = engine.gravity
        if AVPictureInPictureController.isPictureInPictureSupported() {
            let pip = AVPictureInPictureController(playerLayer: v.playerLayer)
            pip?.canStartPictureInPictureAutomaticallyFromInline = true
            engine.pip = pip
        }
        return v
    }

    func updateUIView(_ v: LayerView, context: Context) {
        if v.playerLayer.videoGravity != engine.gravity {
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.25)
            v.playerLayer.videoGravity = engine.gravity
            CATransaction.commit()
        }
    }
}

/// AirPlay button.
struct RoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView()
        v.tintColor = .white
        v.activeTintColor = UIColor(Theme.green)
        v.prioritizesVideoDevices = true
        return v
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
