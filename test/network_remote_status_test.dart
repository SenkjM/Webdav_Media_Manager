import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_media_manager/l10n/generated/app_localizations.dart';
import 'package:webdav_media_manager/models/webdav_item.dart';
import 'package:webdav_media_manager/widgets/track_status_chip.dart';

void main() {
  testWidgets('remote state chip renders empty', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: TrackStatusChip(state: TrackUiState.remote)),
      ),
    );
    expect(find.byType(Chip), findsNothing);
    expect(find.text('排队'), findsNothing);
  });

  testWidgets('streamable has no text chip (dots only)', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: const Scaffold(
          body: TrackStatusChip(state: TrackUiState.streamable),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Chip), findsNothing);
    expect(find.text('可串流'), findsNothing);
  });

  testWidgets('ready has no text chip', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: const Scaffold(
          body: TrackStatusChip(state: TrackUiState.ready),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Chip), findsNothing);
  });

  testWidgets('playing chip is icon-only (no text label)', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: const Scaffold(
          body: TrackStatusChip(state: TrackUiState.playing),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Chip), findsOneWidget);
    expect(find.byIcon(Icons.equalizer), findsOneWidget);
    expect(find.text('播放中'), findsNothing);
  });

  test('TrackUiState order keeps remote first; streamable present', () {
    expect(TrackUiState.values.first, TrackUiState.remote);
    expect(TrackUiState.values.contains(TrackUiState.streamable), isTrue);
    expect(TrackUiState.values.contains(TrackUiState.queued), isTrue);
  });
}
