import Flutter
import UIKit

/// Owns the opaque surface placed above Flutter while iOS is allowed to take
/// an app-switcher snapshot. The surface contains no user data and is removed
/// synchronously when the scene becomes active again.
@MainActor
final class EastPrivacyShieldController {
  static let shieldViewTag = 0x4541_5354

  private weak var coveredWindow: UIWindow?
  private var shieldView: EastPrivacyShieldView?

  var isCovering: Bool {
    shieldView?.superview != nil
  }

  func cover(window: UIWindow?) {
    guard let window else { return }

    if coveredWindow === window, let shieldView, shieldView.superview === window {
      shieldView.frame = window.bounds
      window.bringSubviewToFront(shieldView)
      return
    }

    reveal()

    let shieldView = EastPrivacyShieldView(frame: window.bounds)
    shieldView.tag = Self.shieldViewTag
    shieldView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    window.addSubview(shieldView)
    window.bringSubviewToFront(shieldView)

    coveredWindow = window
    self.shieldView = shieldView
  }

  func reveal() {
    shieldView?.removeFromSuperview()
    shieldView = nil
    coveredWindow = nil
  }
}

/// A deliberately content-free EAST. field for the iOS app switcher.
///
/// The explicit Appearance preference is read only to choose the same two
/// established palettes as Flutter. Missing/corrupt values safely resolve to
/// EAST.'s fresh-install Light default; System follows the scene's traits.
private final class EastPrivacyShieldView: UIView {
  private static let appearancePreferenceKey = "flutter.east_appearance_preference"

  private let ringView = UIView()
  private let titleLabel = UILabel()

  override init(frame: CGRect) {
    super.init(frame: frame)

    isOpaque = true
    isAccessibilityElement = true
    accessibilityLabel = "EAST."
    accessibilityViewIsModal = true

    ringView.translatesAutoresizingMaskIntoConstraints = false
    ringView.isAccessibilityElement = false
    ringView.layer.borderWidth = 0.8
    ringView.layer.cornerRadius = 18

    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    titleLabel.text = "EAST."
    titleLabel.textAlignment = .center
    titleLabel.font =
      UIFont(name: "EBGaramond-Regular", size: 31)
      ?? UIFont(name: "Georgia", size: 31)
      ?? UIFont.systemFont(ofSize: 31, weight: .regular)

    let stack = UIStackView(arrangedSubviews: [ringView, titleLabel])
    stack.translatesAutoresizingMaskIntoConstraints = false
    stack.axis = .vertical
    stack.alignment = .center
    stack.spacing = 22
    addSubview(stack)

    NSLayoutConstraint.activate([
      ringView.widthAnchor.constraint(equalToConstant: 36),
      ringView.heightAnchor.constraint(equalToConstant: 36),
      stack.centerXAnchor.constraint(equalTo: centerXAnchor),
      stack.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])

    applyPalette()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
    super.traitCollectionDidChange(previousTraitCollection)
    if previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle {
      applyPalette()
    }
  }

  private func applyPalette() {
    let storedMode = UserDefaults.standard.string(forKey: Self.appearancePreferenceKey)
    let useDark: Bool
    switch storedMode {
    case "dark":
      useDark = true
    case "system":
      useDark = traitCollection.userInterfaceStyle == .dark
    default:
      useDark = false
    }

    let background = useDark
      ? UIColor(red: 28 / 255, green: 27 / 255, blue: 24 / 255, alpha: 1)
      : UIColor(red: 226 / 255, green: 224 / 255, blue: 217 / 255, alpha: 1)
    let ink = useDark
      ? UIColor(red: 216 / 255, green: 212 / 255, blue: 203 / 255, alpha: 1)
      : UIColor(red: 44 / 255, green: 41 / 255, blue: 36 / 255, alpha: 1)

    backgroundColor = background
    titleLabel.textColor = ink
    ringView.layer.borderColor = ink.cgColor
  }
}

class SceneDelegate: FlutterSceneDelegate {
  private let privacyShieldController = EastPrivacyShieldController()

  override func sceneWillResignActive(_ scene: UIScene) {
    // Install before handing lifecycle control onward so the protected frame
    // is already present when SpringBoard captures the switcher snapshot.
    privacyShieldController.cover(window: appWindow(in: scene))
    super.sceneWillResignActive(scene)
  }

  override func sceneDidEnterBackground(_ scene: UIScene) {
    // Idempotent fallback for lifecycle paths that reach background without
    // a usable window during `sceneWillResignActive`.
    privacyShieldController.cover(window: appWindow(in: scene))
    super.sceneDidEnterBackground(scene)
  }

  override func sceneDidBecomeActive(_ scene: UIScene) {
    super.sceneDidBecomeActive(scene)
    privacyShieldController.reveal()
  }

  private func appWindow(in scene: UIScene) -> UIWindow? {
    guard let windowScene = scene as? UIWindowScene else { return nil }
    return windowScene.windows.first(where: \.isKeyWindow) ?? windowScene.windows.first
  }
}
