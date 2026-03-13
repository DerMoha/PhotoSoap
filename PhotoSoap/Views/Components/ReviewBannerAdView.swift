import SwiftUI
import GoogleMobileAds

struct ReviewBannerAdView: UIViewControllerRepresentable {
    let adUnitID: String

    func makeUIViewController(context: Context) -> ReviewBannerAdViewController {
        ReviewBannerAdViewController(adUnitID: adUnitID)
    }

    func updateUIViewController(_ uiViewController: ReviewBannerAdViewController, context: Context) {
        uiViewController.updateAdUnitID(adUnitID)
    }
}

final class ReviewBannerAdViewController: UIViewController {
    private let bannerView = GADBannerView()
    private var adUnitID: String
    private var lastLoadedWidth: CGFloat = 0
    private var lastLoadedAdUnitID: String?

    init(adUnitID: String) {
        self.adUnitID = adUnitID
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .clear
        bannerView.translatesAutoresizingMaskIntoConstraints = false
        bannerView.rootViewController = self
        bannerView.adUnitID = adUnitID

        view.addSubview(bannerView)

        NSLayoutConstraint.activate([
            bannerView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            bannerView.topAnchor.constraint(equalTo: view.topAnchor),
            bannerView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        loadBannerIfNeeded()
    }

    func updateAdUnitID(_ adUnitID: String) {
        self.adUnitID = adUnitID
        bannerView.adUnitID = adUnitID
        loadBannerIfNeeded()
    }

    private func loadBannerIfNeeded() {
        let width = view.bounds.inset(by: view.safeAreaInsets).width
        guard width > 0 else { return }

        if lastLoadedWidth == width, lastLoadedAdUnitID == adUnitID {
            return
        }

        bannerView.adSize = GADCurrentOrientationAnchoredAdaptiveBannerAdSizeWithWidth(width)
        bannerView.load(GADRequest())
        lastLoadedWidth = width
        lastLoadedAdUnitID = adUnitID
    }
}
