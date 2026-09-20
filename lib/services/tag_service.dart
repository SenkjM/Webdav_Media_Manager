import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';

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

/// Reads ID3 / common tags from a local cached file (pure Dart, no native plugin).
class TagService {
  /// Best-effort read; never throws to callers — returns empty tags on failure.
  Future<ReadTags> readFromFile(String localPath) async {
    try {
      final file = File(localPath);
      if (!await file.exists()) return const ReadTags();

      final meta = readMetadata(file, getImage: true);
      Uint8List? cover;
      if (meta.pictures.isNotEmpty) {
        Picture? chosen;
        for (final pic in meta.pictures) {
          if (pic.pictureType == PictureType.coverFront) {
            chosen = pic;
            break;
          }
        }
        chosen ??= meta.pictures.first;
        cover = chosen.bytes;
      }

      final durationMs = meta.duration?.inMilliseconds;
      final artist = meta.artist ?? meta.albumArtist;
      return ReadTags(
        title: meta.title,
        artist: artist,
        album: meta.album,
        durationMs: durationMs,
        coverBytes: cover,
      );
    } catch (_) {
      return const ReadTags();
    }
  }
}
