import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_search_index_example/main.dart';

void main() {
  testWidgets(
    'unsupported devices show the notes without a broken loading state',
    (tester) async {
      await tester.pumpWidget(const NotesApp());
      await tester.pumpAndSettle();
      expect(find.text('Fieldnotes'), findsOneWidget);
      expect(
        find.text('Native search unavailable on this device.'),
        findsOneWidget,
      );
      expect(find.text('Lemon pasta'), findsOneWidget);
    },
    variant: TargetPlatformVariant({TargetPlatform.linux}),
  );
}
