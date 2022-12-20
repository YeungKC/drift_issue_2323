import 'dart:io';

import 'package:drift/drift.dart';

import 'dart:isolate';

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
  Database() : super(_openConnection());

  // Used for running Drift on a background isolate.
  Database.connect(DatabaseConnection connection) : super.connect(connection);

  @override
  int get schemaVersion => 1;
}

LazyDatabase _openConnection() {
  // the LazyDatabase util lets us find the right location for the file async.
  return LazyDatabase(() async {
    // put the database file, called db.sqlite here, into the documents folder
    // for your app.
    final directory = (await getApplicationDocumentsDirectory()).path;
    final file = File(p.join(directory, 'db.sqlite'));
    return NativeDatabase(file);
  });
}

Future<DriftIsolate> _createDriftIsolate() async {
  // this method is called from the main isolate. Since we can't use
  // getApplicationDocumentsDirectory on a background isolate, we calculate
  // the database path in the foreground isolate and then inform the
  // background isolate about the path.
  final directory = (await getApplicationDocumentsDirectory()).path;
  String path = p.join(directory, 'db.sqlite');
  final receivePort = ReceivePort();

  await Isolate.spawn(
    _startBackground,
    _IsolateStartRequest(receivePort.sendPort, path),
    debugName: 'DBIsolate',
  );

  // _startBackground will send the DriftIsolate to this ReceivePort
  return await receivePort.first as DriftIsolate;
}

void _startBackground(_IsolateStartRequest request) {
  // this is the entry point from the background isolate! Let's create
  // the database from the path we received
  final executor = NativeDatabase(File(request.targetPath));
  // we're using DriftIsolate.inCurrent here as this method already runs on a
  // background isolate. If we used DriftIsolate.spawn, a third isolate would be
  // started which is not what we want!
  final driftIsolate = DriftIsolate.inCurrent(
      () => DatabaseConnection(executor),
      serialize: false);
  // inform the starting isolate about this, so that it can call .connect()
  request.sendDriftIsolate.send(driftIsolate);
}

// used to bundle the SendPort and the target path, since isolate entry point
// functions can only take one parameter.
class _IsolateStartRequest {
  final SendPort sendDriftIsolate;
  final String targetPath;

  _IsolateStartRequest(this.sendDriftIsolate, this.targetPath);
}

Database? _database;
DriftIsolate? _isolate;

SendPort? dbIsolateConnectPort;

/// Get the cached database instance. If no db isolate has been created, this
/// will create one and connect to it.
///
/// Use [existingDbIsolatePort] to connect a new isolate to the db isolate.
Database getDB({SendPort? existingDbIsolatePort}) {
  _database ??=
      Database.connect(DatabaseConnection.delayed(Future.sync(() async {
    if (existingDbIsolatePort != null) {
      // A bg drift isolate already exists, connect to it.
      _isolate =
          DriftIsolate.fromConnectPort(existingDbIsolatePort, serialize: false);
    } else {
      print("Creating db isolate");

      // create a drift executor in a new background isolate.
      _isolate = await _createDriftIsolate();
      dbIsolateConnectPort = _isolate!.connectPort;
    }

    // we can now create a database connection that will use the isolate
    // internally. This is NOT what's returned from _backgroundConnection, drift
    // uses an internal proxy class for isolate communication.
    print("Connecting to db isolate");
    return await _isolate!.connect();
  })));

  return _database!;
}
