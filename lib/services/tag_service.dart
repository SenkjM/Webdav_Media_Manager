import 'dart:typed_data';

import 'package:audiotags/audiotags.dart';

/// Tag fields read from a local audio file after download.
class ReadTags {
  const ReadTags({
    this.title,
    this.artist,
    this.album,
    this.durationMs,
    this.coverBytes,
  });

  final String? title;
  final String? artist;
  final String? album;
  final int? durationMs;
  final Uint8List? coverBytes;
}

/// Reads ID3 / common tags from a local cached file via audiotags.
class TagService {
  /// Best-effort read; never throws to callers — returns empty tags on failure.
  Future<ReadTags> readFromFile(String localPath) async {
    try {
      final tag = await AudioTags.read(localPath);
      if (tag == null) return const ReadTags();
      Uint8List? cover;
      if (tag.pictures.isNotEmpty) {
        // Prefer front cover; else first picture.
        Picture? chosen;
        for (final pic in tag.pictures) {
          if (pic.pictureType == PictureType.coverFront) {
            chosen = pic;
            break;
          }
        }
        chosen ??= tag.pictures.first;
        cover = Uint8List.fromList(chosen.bytes);
      }
      // audiotags duration is typically seconds.
      final dur = tag.duration;
      final durationMs = dur == null ? null : (dur > 10000 ? dur : dur * 1000);
      return ReadTags(
        title: tag.title,
        artist: tag.trackArtist ?? tag.albumArtist,
        album: tag.album,
        durationMs: durationMs,
        coverBytes: cover,
      );
    } catch (_) {
      return const ReadTags();
    }
  }
}
