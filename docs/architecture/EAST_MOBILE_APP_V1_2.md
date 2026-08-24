# EAST. Mobile Architecture v1.2

**Status:** Current Flutter/iOS architecture
**Scope:** The local-first EAST. mobile app and its widget presentation
**Primary rule:** Screens render and route; controllers coordinate; services
and repositories own durable behavior.

## Product invariants

These rules are independent of UI structure and must not be weakened by a
refactor:

- One wisdom may be revealed per rolling 24-hour occurrence.
- `revealId` is the stable occurrence identity.
- Kept and Reflection writes are local-first.
- CloudKit unavailability never blocks local reading or editing.
- Daily ritual access state never enters CloudKit.
- Widget state is presentation-only and never becomes ritual identity.
- Settings, Keeper entitlement, audio, haptics, and analytics remain outside
  ritual phase progression.

## Composition root

`lib/services/app_services.dart` is the sole production composition root. It
constructs the shared storage, purchase, notification, analytics, Kept, and
CloudKit graph. Screens may accept injected services for tests and fall back
to this graph in production.

Do not add a second service locator, dependency-injection package, or parallel
CloudKit graph. The current top-level wiring is deliberate and protected by
layering tests.

## Home ritual boundaries

`HomeScreen` remains the visual host and navigation boundary. Its non-visual
responsibilities are split as follows:

- `RitualFlowController`: legal ritual phase transitions.
- `RitualAccessCoordinator`: newest-wins loading of current daily access.
- `RitualAccessViewState`: immutable UI projection of daily access status.
- `RitualCommitCoordinator`: one typed timeout/late-completion contract for
  fresh and retried reveal commits.
- `RitualCompletionCoordinator`: post-reveal persistence and optional side
  effects without changing ritual identity.
- `HomeKeptController`: Home's Kept projection, reveal-identity matching,
  persistence result mapping, and newest-wins incoming-sync refresh.
- `HomeSwipeToKeptTracker`: gesture recognition only.
- `KeptDiscoveryTimerController`: discovery animation timing and cancellation.
- `NotificationOfferGate`: delayed single-flight permission offer lifecycle.
- `WidgetPresentationSyncCoordinator`: app/widget appearance and language
  reconciliation, owned above Home by `WisdomApp`.

Home's Kept feature is also separated at the library level:

- `home_screen.dart` retains ritual lifecycle and the root widget composition.
- `home_screen_kept.dart` retains only Kept-bound overlay, navigation, and
  swipe presentation that requires the live Home `State`/`BuildContext`.
- `HomeKeptController` remains the independently tested source of the Kept
  projection and identity behavior; the part file contains no persistence.

New non-visual Home behavior should first be tested as a controller or service.
It should stay in `HomeScreen` only when it directly needs `BuildContext`,
widget layout, animation controllers, or route presentation.

## Protected persistence boundary

Kept state, local sync intents, and CloudKit sync state keep separate domain
envelopes and public store errors, but share the two destructive filesystem
algorithms:

- `protected_file_recovery.dart` selects and restores the newest valid backup.
- `protected_file_rollback.dart` restores a prior value after a failed atomic
  replacement.

Both algorithms preserve the original backup until a separate recovery file
and the authoritative final have been protected, decoded, and compared by
value. Existing but wholly unusable backups fail closed; they are never
treated as proof that the store was never written. New protected JSON stores
must reuse these helpers rather than copy either algorithm.

## Reflection boundary

`ReflectionScreen` owns the editor, localized prompt, visual delete decision,
and route gestures. `ReflectionAutosaveCoordinator` owns debounce, newest-edit
draining, retry, and flush-before-leave behavior.

Both the back control and iOS leading-edge gesture call the same flush path.
A failed final local write keeps the editor open so text is never silently
discarded.

## Kept and Journal boundary

`SavedReflectionsScreen` owns list presentation, row actions, and navigation.
It does not calculate Journal pagination or build PDF pages.

- `JournalLayout` decides how many complete entries fit without overflow.
- `JournalPdfBuilder` creates export pages and embeds the emoji fallback.
- `JournalScreen` owns the visible journal and Keeper-gated export action.

There is no fixed three-entry product limit: a page may show more entries when
their complete content fits.

## Widget presentation boundary

Flutter publishes final display text plus optional appearance and locale
presentation fields. The App Group store validates those optional fields
independently from content. Missing fields from an older snapshot fall back to
system appearance and system locale without hiding valid content.

The widget extension never receives `wisdomId` or `revealId`. It renders the
presentation snapshot and applies the stored unlock boundary; it does not
select wisdom or alter daily access.

## Validation gates

Before a release commit:

1. `dart format .`
2. `flutter analyze`
3. `flutter test --reporter compact`
4. Runner XCTest on an iOS simulator
5. Release iOS build
6. Physical-device checks for interactive edge swipe, widget refresh,
   appearance/language changes, Arabic RTL, emoji PDF export, and CloudKit
   continuity

Generated screenshots, trace captures, DerivedData, build output, and
scratchpad investigations are release artifacts, not source files.
