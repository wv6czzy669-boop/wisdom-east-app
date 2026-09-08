import CoreText
import Flutter
import UIKit

/// Owns the opaque surface placed above Flutter while iOS is allowed to take
/// an app-switcher snapshot. The surface contains no user data and is removed
/// when the scene becomes active again. Locked writing waits for Flutter's
/// protected frame before that opaque cover can be removed.
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
  private static let launchMarkWidthRatio: CGFloat = 0.585
  private static let launchMarkBorderAlpha: CGFloat = 0.70
  private static let launchMarkBorderWidth: CGFloat = 0.85
  private static let launchMarkTitleSize: CGFloat = 21.5
  private static let launchMarkTitleLineHeight: CGFloat = 1.28
  private static let launchMarkTitleLetterSpacing: CGFloat = 0.5
  private static let launchMarkTitleLift: CGFloat = 2.5

  private let ringView = UIView()
  private let titleLabel = UILabel()

  override init(frame: CGRect) {
    super.init(frame: frame)

    isOpaque = true
    isAccessibilityElement = true
    accessibilityLabel = "EAST."
    accessibilityViewIsModal = true

    ringView.isAccessibilityElement = false
    ringView.accessibilityIdentifier = "east-privacy-launch-ring"
    ringView.layer.borderWidth = Self.launchMarkBorderWidth
    addSubview(ringView)

    titleLabel.textAlignment = .center
    titleLabel.accessibilityIdentifier = "east-privacy-launch-title"
    updateTitleTypography()
    ringView.addSubview(titleLabel)

    applyPalette()
  }

  private func updateTitleTypography() {
    let size = Self.launchMarkTitleSize * Self.flutterTextScale(for: traitCollection.preferredContentSizeCategory)
    titleLabel.font = Self.launchMarkFont(size: size)
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.alignment = .center
    paragraphStyle.minimumLineHeight =
      titleLabel.font.pointSize * Self.launchMarkTitleLineHeight
    paragraphStyle.maximumLineHeight =
      titleLabel.font.pointSize * Self.launchMarkTitleLineHeight
    titleLabel.attributedText = NSAttributedString(
      string: "EAST.",
      attributes: [
        .font: titleLabel.font as Any,
        .kern: Self.launchMarkTitleLetterSpacing,
        .paragraphStyle: paragraphStyle,
      ]
    )
    setNeedsLayout()
  }

  // FlutterViewController.textScaleFactor scales iOS body sizes relative to
  // Large (17pt). UIFontMetrics uses a different curve for custom fonts, so
  // mirror the engine mapping; the ritual keeps its existing typography.
  private static func flutterTextScale(for category: UIContentSizeCategory) -> CGFloat {
    let bodySize: CGFloat
    switch category {
    case .extraSmall: bodySize = 14
    case .small: bodySize = 15
    case .medium: bodySize = 16
    case .extraLarge: bodySize = 19
    case .extraExtraLarge: bodySize = 21
    case .extraExtraExtraLarge: bodySize = 23
    case .accessibilityMedium: bodySize = 28
    case .accessibilityLarge: bodySize = 33
    case .accessibilityExtraLarge: bodySize = 40
    case .accessibilityExtraExtraLarge: bodySize = 47
    case .accessibilityExtraExtraExtraLarge: bodySize = 53
    default: bodySize = 17
    }
    return bodySize / 17
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    updateTitleTypography()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func layoutSubviews() {
    super.layoutSubviews()

    // Match Flutter's first ritual frame, which is centered inside SafeArea
    // rather than the full physical window. Without this correction the
    // privacy mark sits slightly higher on devices whose top and bottom safe
    // insets differ (for example Dynamic Island iPhones).
    let safeBounds = bounds.inset(by: safeAreaInsets)
    let diameter = min(bounds.width * Self.launchMarkWidthRatio, safeBounds.height)
    ringView.bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
    ringView.center = CGPoint(x: safeBounds.midX, y: safeBounds.midY)
    ringView.layer.cornerRadius = diameter / 2

    let titleSize = titleLabel.sizeThatFits(
      CGSize(width: diameter, height: .greatestFiniteMagnitude)
    )
    titleLabel.bounds = CGRect(
      x: 0,
      y: 0,
      width: ceil(titleSize.width),
      height: titleLabel.font.pointSize * Self.launchMarkTitleLineHeight
    )
    titleLabel.center = CGPoint(
      x: ringView.bounds.midX,
      y: ringView.bounds.midY - Self.launchMarkTitleLift
    )
  }

  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
    super.traitCollectionDidChange(previousTraitCollection)
    if previousTraitCollection?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory {
      updateTitleTypography()
    }
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
    ringView.layer.borderColor = ink.withAlphaComponent(Self.launchMarkBorderAlpha).cgColor
  }

  private static func launchMarkFont(size: CGFloat) -> UIFont {
    if let registeredFont = UIFont(
      name: "EBGaramond-Regular",
      size: size
    ) {
      return registeredFont
    }

    // Flutter already embeds this font for the opening ritual. Register that
    // exact asset for UIKit as well, avoiding both a Georgia fallback and a
    // second copy of the font in Runner's resources.
    let fontURL = Bundle.main.bundleURL
      .appendingPathComponent("Frameworks/App.framework", isDirectory: true)
      .appendingPathComponent("flutter_assets/assets/fonts", isDirectory: true)
      .appendingPathComponent("EBGaramond-Variable.ttf")
    if FileManager.default.fileExists(atPath: fontURL.path) {
      CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, nil)
    }

    return UIFont(name: "EBGaramond-Regular", size: size)
      ?? UIFont(name: "Georgia", size: size)
      ?? UIFont.systemFont(ofSize: size, weight: .regular)
  }
}

class SceneDelegate: FlutterSceneDelegate {
  private let privacyShieldController = EastPrivacyShieldController()
  private var protectedFrameObserver: NSObjectProtocol?
  private var waitingForProtectedFrame = false

  override init() {
    super.init()
    protectedFrameObserver = NotificationCenter.default.addObserver(
      forName: EastPrivateWritingLock.protectedFrameReady, object: nil, queue: .main
    ) { [weak self] _ in
      guard let self, self.waitingForProtectedFrame else { return }
      self.waitingForProtectedFrame = false
      self.privacyShieldController.reveal()
    }
  }

  deinit {
    if let protectedFrameObserver { NotificationCenter.default.removeObserver(protectedFrameObserver) }
  }

  override func sceneWillResignActive(_ scene: UIScene) {
    // Install before handing lifecycle control onward so the protected frame
    // is already present when SpringBoard captures the switcher snapshot.
    privacyShieldController.cover(window: appWindow(in: scene))
    super.sceneWillResignActive(scene)
  }

  override func sceneDidEnterBackground(_ scene: UIScene) {
    EastPrivateWritingLock.shared.didEnterBackground()
    // Idempotent fallback for lifecycle paths that reach background without
    // a usable window during `sceneWillResignActive`.
    privacyShieldController.cover(window: appWindow(in: scene))
    if EastPrivateWritingLock.shared.requiresProtectedFrame {
      // A native share/PDF sheet sits above Flutter's locked field. Dismiss
      // that private preview before it can survive into another session.
      appWindow(in: scene)?.rootViewController?.presentedViewController?.dismiss(animated: false)
    }
    super.sceneDidEnterBackground(scene)
  }

  override func sceneDidBecomeActive(_ scene: UIScene) {
    waitingForProtectedFrame = EastPrivateWritingLock.shared.requiresProtectedFrame
    super.sceneDidBecomeActive(scene)
    // For locked writing, keep the native cover until Flutter has painted a
    // protected frame. Ritual foreground behavior remains unchanged.
    if !waitingForProtectedFrame { privacyShieldController.reveal() }
  }

  private func appWindow(in scene: UIScene) -> UIWindow? {
    guard let windowScene = scene as? UIWindowScene else { return nil }
    return windowScene.windows.first(where: \.isKeyWindow) ?? windowScene.windows.first
  }
}
