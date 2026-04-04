import SwiftUI
import UIKit

struct ZoomablePhotoView: UIViewRepresentable {
    let image: UIImage
    @Binding var zoomScale: CGFloat
    var minimumZoomScale: CGFloat = 1
    var maximumZoomScale: CGFloat = 5

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        let imageView = context.coordinator.imageView

        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = minimumZoomScale
        scrollView.maximumZoomScale = maximumZoomScale
        scrollView.zoomScale = minimumZoomScale
        scrollView.bouncesZoom = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.decelerationRate = .fast
        scrollView.backgroundColor = .clear

        imageView.image = image
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = false
        imageView.frame = scrollView.bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        scrollView.addSubview(imageView)

        let doubleTapRecognizer = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap(_:))
        )
        doubleTapRecognizer.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTapRecognizer)

        context.coordinator.scrollView = scrollView
        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.imageView.image = image

        if context.coordinator.imageView.frame.size != scrollView.bounds.size {
            context.coordinator.imageView.frame = scrollView.bounds
            context.coordinator.centerImage(in: scrollView)
        }

        scrollView.minimumZoomScale = minimumZoomScale
        scrollView.maximumZoomScale = maximumZoomScale

        let clampedZoomScale = min(max(zoomScale, minimumZoomScale), maximumZoomScale)
        if abs(scrollView.zoomScale - clampedZoomScale) > 0.01 {
            scrollView.setZoomScale(clampedZoomScale, animated: false)
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var parent: ZoomablePhotoView
        let imageView = UIImageView()
        weak var scrollView: UIScrollView?

        init(parent: ZoomablePhotoView) {
            self.parent = parent
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centerImage(in: scrollView)
            updateZoomScale(scrollView.zoomScale)
        }

        func centerImage(in scrollView: UIScrollView) {
            let boundsSize = scrollView.bounds.size
            var frameToCenter = imageView.frame

            frameToCenter.origin.x = frameToCenter.size.width < boundsSize.width
                ? (boundsSize.width - frameToCenter.size.width) / 2
                : 0
            frameToCenter.origin.y = frameToCenter.size.height < boundsSize.height
                ? (boundsSize.height - frameToCenter.size.height) / 2
                : 0

            imageView.frame = frameToCenter
        }

        @objc func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
            guard let scrollView else { return }

            let zoomedInScale = min(parent.maximumZoomScale, max(parent.minimumZoomScale * 2.5, 2.5))
            if scrollView.zoomScale > parent.minimumZoomScale + 0.01 {
                scrollView.setZoomScale(parent.minimumZoomScale, animated: true)
                return
            }

            let location = recognizer.location(in: imageView)
            let zoomRect = zoomRect(for: zoomedInScale, centeredAt: location, in: scrollView)
            scrollView.zoom(to: zoomRect, animated: true)
        }

        private func zoomRect(for scale: CGFloat, centeredAt center: CGPoint, in scrollView: UIScrollView) -> CGRect {
            CGRect(
                x: center.x - (scrollView.bounds.size.width / scale) / 2,
                y: center.y - (scrollView.bounds.size.height / scale) / 2,
                width: scrollView.bounds.size.width / scale,
                height: scrollView.bounds.size.height / scale
            )
        }

        private func updateZoomScale(_ scale: CGFloat) {
            guard abs(parent.zoomScale - scale) > 0.01 else { return }

            DispatchQueue.main.async { [weak self] in
                self?.parent.zoomScale = scale
            }
        }
    }
}
