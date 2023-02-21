import 'dart:io';
import 'dart:ui';

import 'package:drift/drift.dart';

import 'package:drift/isolate.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'database.g.dart';

class Records extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get title => text()();

  TextColumn get content => text()();
}

// this annotation tells drift to prepare a database class that uses both of the
// tables we just defined. We'll see how to use that database class in a moment.
@DriftDatabase(tables: [Records])
class Database extends _$Database {
  Database(super.e);

  // Used for running Drift on a background isolate.
  Database.connect(DatabaseConnection connection) : super.connect(connection);

  @override
  int get schemaVersion => 1;
}

Future<Database> connectToDatabase({
  bool fromMainIsolate = false,
}) async {
  const writePortName = 'write';
  const readPortName = 'read';

  final isolates = await Future.wait([
    _crateDatabaseConnection(
      writePortName,
      fromMainIsolate: fromMainIsolate,
    ),
    ...List.generate(
        4,
        (index) => _crateDatabaseConnection(
              '$readPortName$index',
              fromMainIsolate: fromMainIsolate,
            )),
  ]);

  final executor = isolates[0].withExecutor(MultiExecutor.withReadPool(
    reads: isolates.skip(1).toList(),
    write: isolates[0],
  ));

  return Database(executor);
}

Future<DatabaseConnection> _crateDatabaseConnection(
  String name, {
  bool fromMainIsolate = true,
}) async {
  if (fromMainIsolate) {
    // Remove port if it exists. to avoid port leak on hot reload.
    IsolateNameServer.removePortNameMapping(name);
  }

  final existedSendPort = IsolateNameServer.lookupPortByName(name);

  if (existedSendPort == null) {
    assert(fromMainIsolate, 'Isolate should be created from main isolate');

    final directory = (await getApplicationDocumentsDirectory()).path;
    String path = p.join(directory, 'db.sqlite');

    final dbFile = File(path);

    final driftIsolate = await DriftIsolate.spawn(
        () => LazyDatabase(() => NativeDatabase(dbFile, setup: (rawDb) {
              rawDb
                ..execute('PRAGMA journal_mode=WAL;')
                ..execute('PRAGMA foreign_keys=ON;')
                ..execute('PRAGMA synchronous=NORMAL;');
            })));

    IsolateNameServer.registerPortWithName(driftIsolate.connectPort, name);
    return driftIsolate.connect(isolateDebugLog: false);
  } else {
    return DriftIsolate.fromConnectPort(existedSendPort, serialize: false)
        .connect(isolateDebugLog: false);
  }
}
