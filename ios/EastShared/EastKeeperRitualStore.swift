import Foundation

enum EastKeeperRitualPhase: String, Codable, Equatable {
    case pause
    case feel
    case heart
}

struct EastKeeperRitualCandidate: Codable, Equatable {
    let candidateId: String
    let canonicalText: String
    let displayText: String
    let wisdomId: String
    let preparedAt: Date
    let activationAt: Date
}

struct EastKeeperRitualReveal: Codable, Equatable {
    let candidateId: String
    let canonicalText: String
    let displayText: String
    let wisdomId: String
    let revealedAt: Date
    let unlockAt: Date
    let revealId: String?
    let needsAppCommit: Bool
}

enum EastKeeperRitualContent: Equatable {
    case keeperRequired
    case waiting(activationAt: Date?)
    case pause
    case feel
    case heart
    case revealed(EastKeeperRitualReveal)
}

struct EastKeeperRitualSnapshot: Equatable {
    let content: EastKeeperRitualContent
    let presentation: EastWidgetPresentation
}

struct EastKeeperRitualAdvanceResult: Equatable {
    let snapshot: EastKeeperRitualSnapshot
    let newlyRevealed: EastKeeperRitualReveal?
    let changed: Bool
}

/// One compact App Group document for the Keeper widget. Flutter remains the
/// only wisdom selector and the daily-access repository remains the only
/// authority that mints a revealId. The widget may record a provisional
/// reveal boundary, but the app must reconcile that request into its daily
/// record before the occurrence is considered authoritative.
enum EastKeeperRitualStore {
    static let schemaVersion = 1
    static let lockDuration: TimeInterval = 24 * 60 * 60

    private static let documentKey = "east_keeper_ritual_document_v1"
    private static var productionDefaults: UserDefaults? {
        UserDefaults(suiteName: EastWidgetSnapshotStore.appGroupIdentifier)
    }

    private struct Document: Codable, Equatable {
        var schemaVersion: Int
        var isKeeper: Bool
        var phase: EastKeeperRitualPhase
        var currentCandidate: EastKeeperRitualCandidate?
        var nextCandidate: EastKeeperRitualCandidate?
        var reveal: EastKeeperRitualReveal?
        var presentation: EastWidgetPresentation
        var revision: Int

        static let empty = Document(
            schemaVersion: EastKeeperRitualStore.schemaVersion,
            isKeeper: false,
            phase: .pause,
            currentCandidate: nil,
            nextCandidate: nil,
            reveal: nil,
            presentation: .systemDefault,
            revision: 0
        )
    }

    @discardableResult
    static func setKeeperEntitlement(_ isKeeper: Bool) -> Bool {
        setKeeperEntitlement(isKeeper, defaults: productionDefaults)
    }

    @discardableResult
    static func setKeeperEntitlement(
        _ isKeeper: Bool,
        defaults: UserDefaults?
    ) -> Bool {
        mutate(defaults: defaults) { document in
            guard document.isKeeper != isKeeper else { return false }
            document.isKeeper = isKeeper
            return true
        }
    }

    @discardableResult
    static func publishPrepared(
        candidate: EastKeeperRitualCandidate,
        presentation: EastWidgetPresentation,
        now: Date
    ) -> Bool {
        publishPrepared(
            candidate: candidate,
            presentation: presentation,
            now: now,
            defaults: productionDefaults
        )
    }

    @discardableResult
    static func publishPrepared(
        candidate: EastKeeperRitualCandidate,
        presentation: EastWidgetPresentation,
        now: Date,
        defaults: UserDefaults?
    ) -> Bool {
        guard isValid(candidate) else { return false }
        return mutate(defaults: defaults) { document in
            var changed = document.presentation != presentation
            document.presentation = presentation
            if let reveal = document.reveal, reveal.unlockAt > now {
                guard candidate.activationAt >= reveal.unlockAt,
                      candidate.candidateId != reveal.candidateId
                else { return changed }
                if document.nextCandidate != candidate {
                    document.nextCandidate = candidate
                    changed = true
                }
                return changed
            }

            if candidate.activationAt > now {
                if document.nextCandidate != candidate {
                    document.nextCandidate = candidate
                    changed = true
                }
                return changed
            }

            if document.currentCandidate?.candidateId == candidate.candidateId {
                if document.currentCandidate != candidate {
                    document.currentCandidate = candidate
                    changed = true
                }
                return changed
            }

            document.currentCandidate = candidate
            document.reveal = nil
            document.phase = .pause
            changed = true
            return changed
        }
    }

    @discardableResult
    static func publishActive(
        reveal: EastKeeperRitualReveal,
        presentation: EastWidgetPresentation,
        now: Date
    ) -> Bool {
        publishActive(
            reveal: reveal,
            presentation: presentation,
            now: now,
            defaults: productionDefaults
        )
    }

    @discardableResult
    static func publishActive(
        reveal: EastKeeperRitualReveal,
        presentation: EastWidgetPresentation,
        now: Date,
        defaults: UserDefaults?
    ) -> Bool {
        guard isValid(reveal), reveal.unlockAt > now else { return false }
        return mutate(defaults: defaults) { document in
            let authoritativeReveal = EastKeeperRitualReveal(
                candidateId: reveal.candidateId,
                canonicalText: reveal.canonicalText,
                displayText: reveal.displayText,
                wisdomId: reveal.wisdomId,
                revealedAt: reveal.revealedAt,
                unlockAt: reveal.unlockAt,
                revealId: reveal.revealId,
                needsAppCommit: false
            )
            var next = document.nextCandidate
            if next?.candidateId == reveal.candidateId
                || (next?.activationAt ?? .distantPast) < reveal.unlockAt {
                next = nil
            }
            let changed = document.reveal != authoritativeReveal
                || document.currentCandidate != nil
                || document.nextCandidate != next
                || document.presentation != presentation
                || !document.isKeeper
            document.isKeeper = true
            document.reveal = authoritativeReveal
            document.currentCandidate = nil
            document.nextCandidate = next
            document.phase = .pause
            document.presentation = presentation
            return changed
        }
    }

    static func resolvedSnapshot(now: Date) -> EastKeeperRitualSnapshot {
        resolvedSnapshot(now: now, defaults: productionDefaults)
    }

    static func resolvedSnapshot(
        now: Date,
        defaults: UserDefaults?
    ) -> EastKeeperRitualSnapshot {
        guard let document = read(defaults: defaults) else {
            return EastKeeperRitualSnapshot(
                content: .keeperRequired,
                presentation: .systemDefault
            )
        }
        return resolvedSnapshot(document: document, now: now)
    }

    static func advance(now: Date) -> EastKeeperRitualAdvanceResult {
        advance(now: now, defaults: productionDefaults)
    }

    static func advance(
        now: Date,
        defaults: UserDefaults?
    ) -> EastKeeperRitualAdvanceResult {
        guard let defaults else {
            let snapshot = EastKeeperRitualSnapshot(
                content: .keeperRequired,
                presentation: .systemDefault
            )
            return EastKeeperRitualAdvanceResult(
                snapshot: snapshot,
                newlyRevealed: nil,
                changed: false
            )
        }

        var newlyRevealed: EastKeeperRitualReveal?
        var didChange = false
        _ = mutate(defaults: defaults) { document in
            guard document.isKeeper else { return false }
            didChange = promoteNextCandidateIfNeeded(document: &document, now: now)
            guard document.reveal == nil,
                  let candidate = document.currentCandidate,
                  candidate.activationAt <= now
            else { return didChange }

            switch document.phase {
            case .pause:
                document.phase = .feel
            case .feel:
                document.phase = .heart
            case .heart:
                let reveal = EastKeeperRitualReveal(
                    candidateId: candidate.candidateId,
                    canonicalText: candidate.canonicalText,
                    displayText: candidate.displayText,
                    wisdomId: candidate.wisdomId,
                    revealedAt: now,
                    unlockAt: now.addingTimeInterval(lockDuration),
                    revealId: nil,
                    needsAppCommit: true
                )
                document.reveal = reveal
                document.currentCandidate = nil
                document.phase = .pause
                newlyRevealed = reveal
            }
            didChange = true
            return true
        }

        return EastKeeperRitualAdvanceResult(
            snapshot: resolvedSnapshot(now: now, defaults: defaults),
            newlyRevealed: newlyRevealed,
            changed: didChange
        )
    }

    static func bridgePayload(now: Date) -> [String: Any] {
        bridgePayload(now: now, defaults: productionDefaults)
    }

    static func bridgePayload(
        now: Date,
        defaults: UserDefaults?
    ) -> [String: Any] {
        guard let document = read(defaults: defaults) else {
            return ["isKeeper": false, "state": "unavailable"]
        }
        var payload: [String: Any] = [
            "isKeeper": document.isKeeper,
            "state": stateName(for: resolvedSnapshot(document: document, now: now).content),
        ]
        if let candidate = effectiveCandidate(document: document, now: now) {
            payload["candidate"] = candidatePayload(candidate)
        }
        if let next = document.nextCandidate {
            payload["nextCandidate"] = candidatePayload(next)
        }
        if let reveal = document.reveal, reveal.unlockAt > now {
            payload["reveal"] = revealPayload(reveal)
        }
        return payload
    }

    private static func resolvedSnapshot(
        document: Document,
        now: Date
    ) -> EastKeeperRitualSnapshot {
        let content: EastKeeperRitualContent
        if !document.isKeeper {
            content = .keeperRequired
        } else if let reveal = document.reveal, reveal.unlockAt > now {
            content = .revealed(reveal)
        } else if let candidate = effectiveCandidate(document: document, now: now) {
            if candidate.activationAt > now {
                content = .waiting(activationAt: candidate.activationAt)
            } else {
                let phase = document.reveal == nil && document.currentCandidate?.candidateId == candidate.candidateId
                    ? document.phase
                    : .pause
                switch phase {
                case .pause: content = .pause
                case .feel: content = .feel
                case .heart: content = .heart
                }
            }
        } else {
            content = .waiting(activationAt: nil)
        }
        return EastKeeperRitualSnapshot(
            content: content,
            presentation: document.presentation
        )
    }

    private static func effectiveCandidate(
        document: Document,
        now: Date
    ) -> EastKeeperRitualCandidate? {
        if let reveal = document.reveal, reveal.unlockAt > now { return nil }
        if let current = document.currentCandidate { return current }
        return document.nextCandidate
    }

    private static func promoteNextCandidateIfNeeded(
        document: inout Document,
        now: Date
    ) -> Bool {
        if let reveal = document.reveal, reveal.unlockAt > now { return false }
        if document.currentCandidate != nil { return false }
        guard let next = document.nextCandidate, next.activationAt <= now else {
            if document.reveal != nil {
                document.reveal = nil
                document.phase = .pause
                return true
            }
            return false
        }
        document.reveal = nil
        document.currentCandidate = next
        document.nextCandidate = nil
        document.phase = .pause
        return true
    }

    private static func mutate(
        defaults: UserDefaults?,
        operation: (inout Document) -> Bool
    ) -> Bool {
        guard let defaults else { return false }
        var document = read(defaults: defaults) ?? .empty
        guard operation(&document) else { return false }
        document.revision = document.revision == Int.max ? 1 : document.revision + 1
        guard let encoded = try? JSONEncoder().encode(document) else { return false }
        defaults.set(encoded, forKey: documentKey)
        return true
    }

    private static func read(defaults: UserDefaults?) -> Document? {
        guard let data = defaults?.data(forKey: documentKey),
              let document = try? JSONDecoder().decode(Document.self, from: data),
              document.schemaVersion == schemaVersion,
              isValid(document)
        else { return nil }
        return document
    }

    private static func isValid(_ document: Document) -> Bool {
        if let current = document.currentCandidate, !isValid(current) { return false }
        if let next = document.nextCandidate, !isValid(next) { return false }
        if let reveal = document.reveal, !isValid(reveal) { return false }
        return document.revision >= 0
    }

    private static func isValid(_ candidate: EastKeeperRitualCandidate) -> Bool {
        isValidCandidateId(candidate.candidateId)
            && isValidText(candidate.canonicalText)
            && isValidText(candidate.displayText)
            && isCanonicalWisdomId(candidate.wisdomId)
            && isFinite(candidate.preparedAt)
            && isFinite(candidate.activationAt)
            && candidate.activationAt >= candidate.preparedAt
    }

    private static func isValid(_ reveal: EastKeeperRitualReveal) -> Bool {
        isValidCandidateId(reveal.candidateId)
            && isValidText(reveal.canonicalText)
            && isValidText(reveal.displayText)
            && isCanonicalWisdomId(reveal.wisdomId)
            && isFinite(reveal.revealedAt)
            && isFinite(reveal.unlockAt)
            && abs(reveal.unlockAt.timeIntervalSince(reveal.revealedAt) - lockDuration) < 0.001
            && (reveal.revealId == nil || isCanonicalUUID(reveal.revealId!))
            && (!reveal.needsAppCommit || reveal.revealId == nil)
    }

    private static func isValidText(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && value.utf8.count <= 4096
    }

    private static func isCanonicalWisdomId(_ value: String) -> Bool {
        value.range(
            of: #"^east_wisdom_[0-9]{4}$"#,
            options: .regularExpression
        ) != nil
    }

    private static func isValidCandidateId(_ value: String) -> Bool {
        guard (1...160).contains(value.utf8.count) else { return false }
        return value.range(
            of: #"^[A-Za-z0-9:_-]+$"#,
            options: .regularExpression
        ) != nil
    }

    private static func isCanonicalUUID(_ value: String) -> Bool {
        guard value == value.lowercased(), let uuid = UUID(uuidString: value) else {
            return false
        }
        return uuid.uuidString.lowercased() == value
    }

    private static func isFinite(_ value: Date) -> Bool {
        value.timeIntervalSince1970.isFinite && value.timeIntervalSince1970 >= 0
    }

    private static func stateName(for content: EastKeeperRitualContent) -> String {
        switch content {
        case .keeperRequired: return "keeperRequired"
        case .waiting: return "waiting"
        case .pause: return "pause"
        case .feel: return "feel"
        case .heart: return "heart"
        case .revealed: return "revealed"
        }
    }

    private static func candidatePayload(_ candidate: EastKeeperRitualCandidate) -> [String: Any] {
        [
            "candidateId": candidate.candidateId,
            "canonicalText": candidate.canonicalText,
            "displayText": candidate.displayText,
            "wisdomId": candidate.wisdomId,
            "preparedAtMillis": candidate.preparedAt.millisecondsSince1970,
            "activationAtMillis": candidate.activationAt.millisecondsSince1970,
        ]
    }

    private static func revealPayload(_ reveal: EastKeeperRitualReveal) -> [String: Any] {
        var payload: [String: Any] = [
            "candidateId": reveal.candidateId,
            "canonicalText": reveal.canonicalText,
            "displayText": reveal.displayText,
            "wisdomId": reveal.wisdomId,
            "revealedAtMillis": reveal.revealedAt.millisecondsSince1970,
            "unlockAtMillis": reveal.unlockAt.millisecondsSince1970,
            "needsAppCommit": reveal.needsAppCommit,
        ]
        if let revealId = reveal.revealId { payload["revealId"] = revealId }
        return payload
    }
}

private extension Date {
    var millisecondsSince1970: Int64 {
        Int64((timeIntervalSince1970 * 1000.0).rounded())
    }
}
