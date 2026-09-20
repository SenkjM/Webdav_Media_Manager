import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_music_player/models/webdav_item.dart';
import 'package:webdav_music_player/widgets/track_status_chip.dart';
import 'package:flutter/material.dart';

void main() {
  testWidgets('remote state chip renders empty', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: TrackStatusChip(state: TrackUiState.remote),
        ),
      ),
    );
    expect(find.byType(Chip), findsNothing);
    expect(find.text('排队'), findsNothing);
  });

  test('TrackUiState has remote before queued', () {
    expect(TrackUiState.values.first, TrackUiState.remote);
    expect(TrackUiState.values.contains(TrackUiState.queued), isTrue);
  });
}
