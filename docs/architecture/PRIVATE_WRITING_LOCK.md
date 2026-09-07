# Private writing lock

The optional iOS writing lock is available without Keeper. It starts disabled
and protects Kept, Reflection, Journal and Settings data export. It does not
participate in the daily wisdom clock, entitlement checks or ritual motion.

## Ownership

- `EastPrivateWritingLock` owns the device-local preference
  `east.privateWritingLock.enabled` in native UserDefaults. It is not synchronized
  through CloudKit or shared with widgets. Enabling and disabling both require
  successful device-owner authentication.
- `EastDeviceOwnerAuthenticator` uses a fresh `LAContext` with
  `deviceOwnerAuthentication`: Face ID / Touch ID with the device passcode as
  recovery. EAST never receives biometric data or the passcode. Permission copy
  is in `Runner/InfoPlist.xcstrings`; prompt reasons come from Flutter localization.
- `PrivateWritingLockController` owns the non-persistent foreground session and
  the set of open private scopes. Leaving the final scope revokes that session.
  Unknown native status fails closed. Duplicate authentication requests are
  suppressed; backgrounding invalidates pending results in both Swift and Dart.
- System authentication can temporarily make the app inactive. A valid result
  waits for resumed before allowing an export. A real background transition
  invalidates that result and requires a fresh authentication.

## Presentation and lifecycle

Each private screen wraps its actual content in `PrivateWritingGate`. While
locked, the existing content stays mounted but is offstage, excluded from
semantics, unable to receive focus and unable to receive pointer events. This
keeps a Reflection draft and its autosave coordinator alive without exposing it.

The pre-existing native EAST privacy shield covers app-switcher snapshots.
On return to a protected scope, SceneDelegate retains that shield until Flutter
acknowledges a newly painted protected frame. This avoids deliberately revealing
the previous private Flutter surface while lifecycle state catches up.

Native share/preview controllers are dismissed when a protected scope enters the
background. Data export and Kept share-card rendering recheck the current session
before requesting native presentation, so late rendering does not reopen a
preview after the session closes. Journal sharing uses its already-built PDF.

This is a UI access boundary layered over the existing protected local storage;
it is not a new encryption format or an alternative iCloud security system.

## Settings

The main Settings page presents everyday preferences, writing, membership, then
About. Privacy, iCloud and About have dedicated routes using the existing
controllers and services. The iCloud removal confirmation and transaction logic
are retained. The lock switch changes its value only after authentication.

Rows use the existing EAST serif fonts, light/dark palettes, thin dividers and
scrolling behavior. Long state labels wrap rather than shrink. At larger text
sizes, labels and values stack, while the lock switch remains aligned with its
label. The main content width is capped at 560 logical pixels.

## Verification and remaining device checks

Automated coverage includes failed/unavailable authentication, duplicate requests,
late background callbacks, draft persistence across locking, all three private
destinations, export authentication, deferred share presentation, toggle behavior,
unknown preferences and Settings navigation. All localized Settings sections are
exercised at 200% text size on a 320-pixel-wide viewport. Existing 300% Settings
scrolling and VoiceOver/Voice Control action checks remain active.

Before release, exercise Face ID success, rejection, cancellation and passcode
fallback on a physical iPhone; switch away while typing and while a share sheet
is open, then return. Automated authenticator doubles and simulator builds do
not establish physical sensor behavior or real-device snapshot timing.

Apple references:

- [Device-owner authentication](https://developer.apple.com/documentation/LocalAuthentication/LAPolicy/deviceOwnerAuthentication)
- [Localized authentication reason](https://developer.apple.com/documentation/localauthentication/lacontext/localizedreason)
- [Preparing UI for the background](https://developer.apple.com/documentation/uikit/preparing-your-ui-to-run-in-the-background?language=objc)
