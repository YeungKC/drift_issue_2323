import 'dart:isolate';

import 'package:drift_issue_2180/database.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  runApp(const ProviderScope(
    child: MyApp(),
  ));

  startBackgroundSync();
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // Try running your application with "flutter run". You'll see the
        // application has a blue toolbar. Then, without quitting the app, try
        // changing the primarySwatch below to Colors.green and then invoke
        // "hot reload" (press "r" in the console where you ran "flutter run",
        // or simply save your changes to "hot reload" in a Flutter IDE).
        // Notice that the counter didn't reset back to zero; the application
        // is not restarted.
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class MyHomePage extends ConsumerStatefulWidget {
  const MyHomePage({super.key, required this.title});

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  ConsumerState<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends ConsumerState<MyHomePage> {
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(providerApplicationState);

    // This method is rerun every time setState is called, for instance as done
    // by the _incrementCounter method above.
    //
    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
    return Scaffold(
      appBar: AppBar(
        // Here we take the value from the MyHomePage object that was created by
        // the App.build method, and use it to set our appbar title.
        title: Text(widget.title),
      ),
      body: Center(
        // Center is a layout widget. It takes a single child and positions it
        // in the middle of the parent.
        child: Column(
          // Column is also a layout widget. It takes a list of children and
          // arranges them vertically. By default, it sizes itself to fit its
          // children horizontally, and tries to be as tall as its parent.
          //
          // Invoke "debug painting" (press "p" in the console, choose the
          // "Toggle Debug Paint" action from the Flutter Inspector in Android
          // Studio, or the "Toggle Debug Paint" command in Visual Studio Code)
          // to see the wireframe for each widget.
          //
          // Column has various properties to control how it sizes itself and
          // how it positions its children. Here we use mainAxisAlignment to
          // center the children vertically; the main axis here is the vertical
          // axis because Columns are vertical (the cross axis would be
          // horizontal).
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Text(
              'This many records have been loaded:',
            ),
            Text(
              '${state.numRecords}',
              style: Theme.of(context).textTheme.headline4,
            ),
          ],
        ),
      ),
    );
  }
}

final providerApplicationState =
    ChangeNotifierProvider<ApplicationState>((ref) => ApplicationState());

class ApplicationState with ChangeNotifier {
  int numRecords = 0;

  ApplicationState() {
    _observeRecords();
  }

  void _observeRecords() {
    final db = getDB();
    final query = db.select(db.records);
    query.watch().listen((records) {
      numRecords = records.length;
      notifyListeners();
    });
  }
}

Future<void> startBackgroundSync() async {
  getDB();
  final db = getDB();
  // Query the DB to make sure dbIsolateConnectPort is initialized
  await db.select(db.records).get();
  StartBackgroundSyncArgs args =
      StartBackgroundSyncArgs(toDbIsolatePort: dbIsolateConnectPort!);
  Isolate.spawn(
    spawnIsolateAndSync,
    args,
    debugName: 'Background Sync',
  );
}

class StartBackgroundSyncArgs {
  /// Port to connect to the existing db isolate
  final SendPort toDbIsolatePort;

  StartBackgroundSyncArgs({required this.toDbIsolatePort});
}

Future<void> spawnIsolateAndSync(StartBackgroundSyncArgs syncArgs) async {
  print("Spawned background sync isolate");

  // connect to the db using existing db isolate port
  final db = getDB(existingDbIsolatePort: syncArgs.toDbIsolatePort);

  int id = 1;
  while (true) {
    await db.batch((batch) {
      batch.insertAll(db.records, [
        Record(id: id, title: 'Title', content: 'Content'),
      ]);
    });

    id += 1;
  }

  // completed background sync, dispose and cleanup all the things
  // Isolate.current.kill();
}
