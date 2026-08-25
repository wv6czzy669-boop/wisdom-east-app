import 'package:wisdom_app/persistence/journal_owner_store.dart';

final class InMemoryJournalOwnerStore implements JournalOwnerStore {
  InMemoryJournalOwnerStore({this.name});

  String? name;
  bool failReads = false;
  bool failWrites = false;
  int writeCount = 0;

  @override
  Future<String?> loadName() async {
    if (failReads) throw StateError('owner read failed');
    return name;
  }

  @override
  Future<void> writeName(String? name) async {
    if (failWrites) throw StateError('owner write failed');
    writeCount += 1;
    this.name = name;
  }
}
