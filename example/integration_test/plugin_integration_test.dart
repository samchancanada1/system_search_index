import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:system_search_index/system_search_index.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final index = SystemSearchIndex();
  final domain = 'integration-${DateTime.now().microsecondsSinceEpoch}';

  Future<SearchResponse> eventually(String query, String scope) async {
    for (var attempt = 0; attempt < 30; attempt++) {
      final response = await index.search(
        query,
        domain: scope,
        semantic: false,
        suggestionLimit: 0,
      );
      if (response.items.isNotEmpty) return response;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    return const SearchResponse.empty();
  }

  testWidgets('native upsert, domain isolation, search, expiry, and deletion', (
    tester,
  ) async {
    final capabilities = await index.getCapabilities();
    expect(
      capabilities.indexing,
      isTrue,
      reason: 'Run on iOS 18+ or Android 12+.',
    );
    await index.configure(androidSystemVisibility: false);
    addTearDown(() async {
      await index.removeDomain(domain);
      await index.removeDomain('$domain-other');
    });
    await index.indexAll([
      SearchItem(
        id: '1',
        domain: domain,
        title: 'Zephyrlemon pasta',
        textContent: 'A quick dinner',
        keywords: ['recipe'],
        deepLink: Uri.parse('fieldnotes://notes/1'),
      ),
      SearchItem(
        id: '1',
        domain: '$domain-other',
        title: 'Zephyrlemon private',
      ),
    ]);
    final first = await eventually('Zephyrlemon', domain);
    expect(first.items.map((i) => i.id), ['1']);
    expect(first.items.single.domain, domain);
    expect(first.items.single.deepLink, Uri.parse('fieldnotes://notes/1'));
    await index.index(
      SearchItem(id: '1', domain: domain, title: 'Zephyrbasil updated'),
    );
    final updated = await eventually('Zephyrbasil', domain);
    expect(updated.items.single.title, 'Zephyrbasil updated');
    await index.remove(['1', 'missing'], domain: domain);
    // Spotlight mutations are eventually reflected by its query service.
    for (var attempt = 0; attempt < 30; attempt++) {
      final response = await index.search(
        'Zephyrbasil',
        domain: domain,
        semantic: false,
        suggestionLimit: 0,
      );
      if (response.items.isEmpty) break;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    expect(
      (await index.search(
        'Zephyrbasil',
        domain: domain,
        semantic: false,
        suggestionLimit: 0,
      )).items,
      isEmpty,
    );
    expect(
      (await eventually('Zephyrlemon', '$domain-other')).items,
      hasLength(1),
    );
    await index.index(
      SearchItem(
        id: 'expired',
        domain: domain,
        title: 'Zephyrexpired',
        expiresAt: DateTime.utc(2000),
      ),
    );
    expect(
      (await index.search(
        'Zephyrexpired',
        domain: domain,
        semantic: false,
        suggestionLimit: 0,
      )).items,
      isEmpty,
    );
  });
}
