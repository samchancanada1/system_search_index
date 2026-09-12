import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_search_index/system_search_index.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('system_search_index/methods');
  const events = EventChannel('system_search_index/activations');
  final calls = <MethodCall>[];
  late SystemSearchIndex index;

  setUp(() {
    calls.clear();
    index = SystemSearchIndex.withChannels(channel, events);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'search') {
            return {'items': [], 'suggestions': []};
          }
          if (call.method == 'getCapabilities') {
            return {
              'indexing': true,
              'semanticSearch': true,
              'suggestions': true,
              'activationEvents': true,
              'systemSurface': 'spotlight',
            };
          }
          return null;
        });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('production connection is shared', () {
    expect(identical(SystemSearchIndex(), SystemSearchIndex()), isTrue);
  });

  test('metadata round-trips without losing URLs, unicode, or UTC expiry', () {
    final keywords = ['travel'];
    final item = SearchItem(
      id: 'id:/ 1',
      domain: 'account/a',
      title: 'Montréal',
      description: 'A note',
      textContent: 'Full text',
      keywords: keywords,
      deepLink: Uri.parse('notes://entry/1'),
      thumbnailUri: Uri.file('/tmp/image.png'),
      expiresAt: DateTime.utc(2030, 1, 2),
    );
    keywords.add('mutation');
    final restored = SearchItem.fromMap(item.toMap());
    expect(restored.id, item.id);
    expect(restored.title, item.title);
    expect(restored.domain, item.domain);
    expect(restored.expiresAt, item.expiresAt);
    expect(restored.deepLink, item.deepLink);
    expect(restored.thumbnailUri, item.thumbnailUri);
    expect(restored.keywords, ['travel']);
    expect(() => item.keywords.add('x'), throwsUnsupportedError);
  });

  test('invalid identities and URIs fail in release builds too', () {
    expect(() => SearchItem(id: '', title: 'Title'), throwsArgumentError);
    expect(() => SearchItem(id: 'a', title: ' '), throwsArgumentError);
    expect(
      () => SearchItem(id: 'a', title: 'Title', domain: ''),
      throwsArgumentError,
    );
    expect(
      () =>
          SearchItem(id: 'a', title: 'Title', deepLink: Uri.parse('/relative')),
      throwsArgumentError,
    );
    expect(
      () => SearchItem(
        id: 'a',
        title: 'Title',
        thumbnailUri: Uri.parse('https://example.com/a'),
      ),
      throwsArgumentError,
    );
  });

  test(
    'groups domains before batching and allows the same ID in two domains',
    () async {
      await index.indexAll([
        for (var i = 0; i < 201; i++)
          SearchItem(id: '$i', title: 'Note $i', domain: 'a'),
        SearchItem(id: '0', title: 'Other account', domain: 'b'),
      ]);
      expect(calls.map((c) => (c.arguments['items'] as List).length), [
        100,
        100,
        1,
        1,
      ]);
      expect(calls.map((c) => c.arguments['domain']), ['a', 'a', 'a', 'b']);
    },
  );

  test(
    'duplicate identities reject the whole input before any mutation',
    () async {
      final item = SearchItem(id: 'a', title: 'Title');
      await expectLater(index.indexAll([item, item]), throwsArgumentError);
      expect(calls, isEmpty);
    },
  );

  test('empty mutations do not touch native storage', () async {
    await index.indexAll([]);
    await index.remove([]);
    expect(calls, isEmpty);
  });

  test('remove deduplicates and batches within the specified domain', () async {
    await index.remove([
      '0',
      for (var i = 0; i < 101; i++) '$i',
    ], domain: 'account');
    expect(calls.length, 2);
    expect((calls.first.arguments['ids'] as List).length, 100);
    expect(calls.last.arguments, {
      'domain': 'account',
      'ids': ['100'],
    });
  });

  test('domain clear never becomes a global clear', () async {
    await index.removeDomain('account');
    expect(calls.single.method, 'removeDomain');
    expect(calls.single.arguments, {'domain': 'account'});
  });

  test('blank search is local, bounds fail before native dispatch', () async {
    expect((await index.search('  ')).items, isEmpty);
    await expectLater(index.search('query', limit: 0), throwsRangeError);
    await expectLater(
      index.search('query', suggestionLimit: 11),
      throwsRangeError,
    );
    expect(calls, isEmpty);
  });

  test('search passes all options and parses returned content', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return {
            'items': [
              SearchItem(id: '1', domain: 'notes', title: 'Lemon').toMap(),
            ],
            'suggestions': ['lemon pasta'],
          };
        });
    final response = await index.search(
      'lem',
      domain: 'notes',
      limit: 8,
      suggestionLimit: 2,
      semantic: false,
    );
    expect(calls.single.arguments, {
      'query': 'lem',
      'domain': 'notes',
      'limit': 8,
      'suggestionLimit': 2,
      'semantic': false,
    });
    expect(response.items.single.id, '1');
    expect(response.suggestions, ['lemon pasta']);
  });

  test(
    'native batch failure preserves details and stops subsequent batches',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            throw PlatformException(
              code: 'batch_failed',
              details: {
                'succeededIds': ['0'],
              },
            );
          });
      await expectLater(
        index.indexAll([
          for (var i = 0; i < 101; i++) SearchItem(id: '$i', title: 'Note'),
        ]),
        throwsA(
          isA<PlatformException>()
              .having((e) => e.code, 'code', 'batch_failed')
              .having((e) => e.details, 'details', {
                'succeededIds': ['0'],
              }),
        ),
      );
      expect(calls.length, 1);
    },
  );

  test(
    'unsupported desktop capability probe never uses a native channel',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      expect((await index.getCapabilities()).indexing, isFalse);
      expect(calls, isEmpty);
    },
  );

  test('mobile capability probe maps the system surface', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(
      (await index.getCapabilities()).systemSurface,
      SearchSystemSurface.spotlight,
    );
  });

  test('activation model keeps account identity', () {
    final event = SearchActivation.fromMap({'id': '1', 'domain': 'account'});
    expect(event.id, '1');
    expect(event.domain, 'account');
  });
}
