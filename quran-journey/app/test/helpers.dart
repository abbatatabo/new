import 'dart:io';

import 'package:quran_journey/data/quran_db.dart';
import 'package:quran_journey/data/user_db.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Opens the real bundled database (assets/db/quran.db) read-only via FFI.
Future<QuranDb> openRealQuranDb() async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(
    '${Directory.current.path}/assets/db/quran.db',
    options: OpenDatabaseOptions(readOnly: true),
  );
  return QuranDb.openWith(db);
}

Future<UserDb> openMemoryUserDb() async {
  sqfliteFfiInit();
  // A fresh file per call: sqflite shares ':memory:' between opens.
  final dir = Directory.systemTemp.createTempSync('qj_user_');
  return UserDb.open(path: '${dir.path}/user.db', factory: databaseFactoryFfiNoIsolate);
}
