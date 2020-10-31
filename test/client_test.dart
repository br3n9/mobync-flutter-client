import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobync/constants/constants.dart';
import 'package:mobync/models/models.dart';
import 'package:uuid/uuid.dart';

import 'client_implementation.dart';

void main() {
  test('test logical clock get and set', () async {
    final client = MyMobyncClient.instance;

    int logicalClock = await client.getLogicalClock();
    expect(logicalClock, 0);

    await client.setLogicalClock(10);
    int logicalClock2 = await client.getLogicalClock();
    expect(logicalClock2, 10);
  });

  test('test diffs for sequence of local operations', () async {
    final client = MyMobyncClient.instance;

    /// CREATE Operation
    final obj1 = {'id': 'uuid1', 'campo1': 'abc'};
    MobyncResponse res1 = await client.create('model1', obj1);
    expect(res1.success, true);

    /// Invalid CREATE Operation
    final obj2 = {'id': 'uuid1', 'campo1': 'cde'};
    MobyncResponse res2 = await client.create('model1', obj2);
    expect(res2.success, false);

    /// CREATE Operation
    final obj3 = {'id': 'uuid2', 'campo1': 'fgh'};
    MobyncResponse res3 = await client.create('model1', obj3);
    expect(res3.success, true);

    /// UPDATE Operation
    final obj4 = {'id': 'uuid1', 'campo1': 'xxx'};
    MobyncResponse res4 = await client.update('model1', obj4);
    expect(res4.success, true);

    /// READ Operation
    MobyncResponse res5 = await client.read('model1');
    expect(res5.success, true);
    expect(res5.data, [obj4, obj3]);

    /// DELETE Operation
    MobyncResponse res6 = await client.delete('model1', 'uuid2');
    expect(res6.success, true);

    /// READ Operation
    MobyncResponse res7 = await client.read('model1');
    expect(res7.success, true);
    expect(res7.data, [obj4]);

    /// SYNC DIFFS List
    List<SyncDiff> res8 = await client.getSyncDiffs();
    expect(res8.length, 4);
    expect(
        res8.map((e) => [e.logicalClock, e.type, e.model, e.metadata]).toList(),
        [
          [
            10,
            'CREATE',
            'model1',
            {'id': 'uuid1', 'campo1': 'abc'}
          ],
          [
            10,
            'CREATE',
            'model1',
            {'id': 'uuid2', 'campo1': 'fgh'}
          ],
          [
            10,
            'UPDATE',
            'model1',
            {'id': 'uuid1', 'campo1': 'xxx'}
          ],
          [
            10,
            'DELETE',
            'model1',
            {'id': 'uuid2'}
          ]
        ]);
  });

  test('test upstream diffs fetch', () async {
    final client = MyMobyncClient.instance;
    ServerMockup server = ServerMockup.instance;
    List<SyncDiff> localDiffs, upstreamDiffs;
    ServerSyncResponse upstreamResponse;
    int logicalClock;

    localDiffs = await client.getSyncDiffs();

    logicalClock = await client.getLogicalClock();
    upstreamResponse = await server.syncEndpoint(logicalClock, localDiffs);
    expect(upstreamResponse.diffs.length, 0);

    List<SyncDiff> otherClientDiffsMockup = [
      SyncDiff(
          id: Uuid().v1(),
          logicalClock: 50,
          utcTimestamp: DateTime.now().toUtc().millisecondsSinceEpoch,
          type: CREATE_OPERATION,
          model: 'model1',
          metadata: {'id': 'uuid3', 'campo1': 'a'}),
      SyncDiff(
          id: Uuid().v1(),
          logicalClock: 50,
          utcTimestamp: DateTime.now().toUtc().millisecondsSinceEpoch,
          type: UPDATE_OPERATION,
          model: 'model1',
          metadata: {'id': 'uuid3', 'campo1': 'b'}),
      SyncDiff(
          id: Uuid().v1(),
          logicalClock: 50,
          utcTimestamp: DateTime.now().toUtc().millisecondsSinceEpoch,
          type: CREATE_OPERATION,
          model: 'model1',
          metadata: {'id': 'uuid4', 'campo1': 'c'}),
      SyncDiff(
          id: Uuid().v1(),
          logicalClock: 50,
          utcTimestamp: DateTime.now().toUtc().millisecondsSinceEpoch,
          type: DELETE_OPERATION,
          model: 'model1',
          metadata: {'id': 'uuid3'})
    ];
    server.mergeDiffs(50, otherClientDiffsMockup);
    expect(server.serverDiffs.length, 8);

    await client.synchronize();

    localDiffs = await client.getSyncDiffs();
    expect(localDiffs.length, 0);

    final obj1 = {'id': 'uuid5', 'campo1': 'abc'};
    MobyncResponse res1 = await client.create('model1', obj1);
    expect(res1.success, true);

    localDiffs = await client.getSyncDiffs();
    expect(localDiffs.length, 1);

    await client.synchronize();

    localDiffs = await client.getSyncDiffs();
    expect(localDiffs.length, 0);

    final model1 = await client.read('model1');
    expect(model1.success, true);
    expect(model1.data, [
      {'id': 'uuid1', 'campo1': 'xxx'},
      {'id': 'uuid4', 'campo1': 'c'},
      {'id': 'uuid5', 'campo1': 'abc'},
    ]);

    logicalClock = await client.getLogicalClock();
    expect(logicalClock, 53);
  });
}
