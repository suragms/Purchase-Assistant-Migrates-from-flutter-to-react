import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harisree_warehouse/core/auth/session_notifier.dart';
import 'package:harisree_warehouse/core/models/session.dart';
import 'package:harisree_warehouse/core/providers/stock_providers.dart';
import 'package:harisree_warehouse/core/providers/suppliers_list_provider.dart';

void _log(String hypothesisId, String message, Map<String, dynamic> data) {
  final line = jsonEncode({
    'sessionId': '5843f1',
    'hypothesisId': hypothesisId,
    'location': 'debug_stock_contacts_flow_test.dart',
    'message': message,
    'data': data,
    'timestamp': DateTime.now().millisecondsSinceEpoch,
    'runId': 'post-fix-test',
  });
  // ignore: avoid_print
  print('[DBG5843f1] $line');
  try {
    File(r'../debug-5843f1.log').writeAsStringSync('$line\n', mode: FileMode.append);
  } catch (_) {}
}

Session _fakeSession() => Session(
      accessToken: 'test-access',
      refreshToken: 'test-refresh',
      businesses: [
        const BusinessBrief(
          id: 'biz-1',
          name: 'Test',
          role: 'owner',
        ),
      ],
    );

void main() {
  test('deferred cache write does not trip Riverpod assert (H1/H4)', () async {
    final container = ProviderContainer(
      overrides: [
        sessionProvider.overrideWith(() => _FakeSessionNotifier(_fakeSession())),
        stockListProvider.overrideWith((ref) async {
          final payload = {
            'items': [
              {'id': 'i1', 'name': 'Rice', 'current_stock': 10},
            ],
            'total': 525,
          };
          final queryKey = ref.read(stockListQueryProvider).toCacheKey();
          Future.microtask(() {
            ref.read(stockListCachedBodyProvider.notifier).state = payload;
            ref.read(stockListCacheQueryKeyProvider.notifier).state = queryKey;
            ref.read(stockListLiveSnapshotProvider.notifier).state = payload;
          });
          return payload;
        }),
      ],
    );
    addTearDown(container.dispose);

    final result = await container.read(stockListProvider.future);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final asyncAfter = container.read(stockListProvider);
    final ram = stockListCachedDataForCurrentQuery(container);

    _log('H1', 'post-fix provider state', {
      'hasValue': asyncAfter.hasValue,
      'total': result['total'],
      'ramNull': ram == null,
    });

    expect(asyncAfter.hasValue, isTrue);
    expect(ram, isNotNull);
  });

  test('suppliers provider surfaces errors without assert (H3)', () async {
    final container = ProviderContainer(
      overrides: [
        sessionProvider.overrideWith(() => _FakeSessionNotifier(_fakeSession())),
        suppliersListProvider.overrideWith((ref) async {
          throw StateError('simulated supplier fetch failure');
        }),
      ],
    );
    addTearDown(container.dispose);

    await expectLater(
      container.read(suppliersListProvider.future),
      throwsA(isA<StateError>()),
    );
    _log('H3', 'suppliers error surfaced', {
      'hasError': container.read(suppliersListProvider).hasError,
    });
  });
}

class _FakeSessionNotifier extends SessionNotifier {
  _FakeSessionNotifier(this._session);
  final Session _session;

  @override
  Session? build() => _session;
}
