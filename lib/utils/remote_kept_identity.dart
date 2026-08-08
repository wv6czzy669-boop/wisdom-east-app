import 'package:uuid/uuid.dart';

/// Build 26 Phase 4E-3b: the exact namespaced name
/// [deriveIncomingKeptLocalId] derives a remotely-adopted `KeptRecord`'s
/// local bookkeeping `id` from, given the occurrence's `revealId` alone.
///
/// Deliberately a **separate semantic namespace** from
/// `legacy_kept_identity.dart`'s `legacyMigrationRevealIdName` -- that
/// namespace derives a `revealId` from a legacy `FavoriteItem.id` (Build 25
/// migration); this namespace derives a local `id` from a `revealId` (Build
/// 26 CloudKit incoming adoption). The two must never collide or be
/// confused: a v5 UUID minted under one namespace can never equal a v5 UUID
/// minted under the other, since the namespaced *name* string itself
/// encodes which derivation produced it.
String incomingKeptLocalIdName(String revealId) =>
    'com.dogukan.dailywisdom/build26/sync/incoming-local-id/$revealId';

/// Deterministically derives the local bookkeeping `id`
/// ([lib/models/kept_record.dart]'s `KeptRecord.id`) to use when adopting a
/// remotely-fetched active `CKKeptWisdom` record into genuine local absence
/// -- i.e. no existing physical [KeptRecord] for this exact [revealId]
/// already exists to preserve the `id` of.
///
/// Pure function of [revealId] alone -- never wisdom text, a display date,
/// `DateTime.now()`, a random v4, or any CloudKit system-fields/identity
/// value. The same [revealId] always derives the same local `id`, on every
/// device, on every crash/retry -- this is exactly what makes a second,
/// interrupted retry of the same incoming-apply transaction safe: it must
/// never mint a *second*, different local id for the same already-adopted
/// occurrence merely because a prior attempt crashed after minting one but
/// before durably writing it.
///
/// [uuidV5Factory] exists solely for deterministic testing (mirroring
/// `deriveLegacyMigrationRevealId`'s identical pattern); production code
/// always uses the default, real UUID v5 algorithm over the standard URL
/// namespace.
String deriveIncomingKeptLocalId(
  String revealId, {
  String Function(String name)? uuidV5Factory,
}) {
  final factory =
      uuidV5Factory ?? (name) => const Uuid().v5(Namespace.url.value, name);
  return factory(incomingKeptLocalIdName(revealId));
}
