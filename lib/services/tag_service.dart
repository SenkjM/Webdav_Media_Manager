import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';

import '../l10n/generated/app_localizations.dart';

/// Tag fields read from a local audio file after download.
class ReadTags {
  const ReadTags({
    this.title,
    this.artist,
    this.albumArtist,
    this.album,
    this.durationMs,
    this.trackNumber,
    this.trackTotal,
    this.discNumber,
    this.discTotal,
    this.year,
    this.genre,
    this.bitrate,
    this.sampleRate,
    this.language,
    this.lyrics,
    this.coverBytes,
  });

  final String? title;
  final String? artist;
  final String? albumArtist;
  final String? album;
  final int? durationMs;
  final int? trackNumber;
  final int? trackTotal;
  final int? discNumber;
  final int? discTotal;
  final int? year;
  final String? genre;
  final int? bitrate;
  final int? sampleRate;
  final String? language;
  final String? lyrics;
  final Uint8List? coverBytes;

  /// Flat map of non-null display fields for “More” / details UI.
  Map<String, String> toDisplayMap(AppLocalizations l10n) {
    final m = <String, String>{};
    void put(String k, String? v) {
      final t = v?.trim();
      if (t != null && t.isNotEmpty) m[k] = t;
    }

    put(l10n.tagTitle, title);
    put(l10n.tagArtist, artist);
    put(l10n.tagAlbumArtist, albumArtist);
    put(l10n.tagAlbum, album);
    if (trackNumber != null) {
      put(
        l10n.tagTrack,
        trackTotal != null ? '$trackNumber / $trackTotal' : '$trackNumber',
      );
    }
    if (discNumber != null) {
      put(
        l10n.tagDisc,
        discTotal != null ? '$discNumber / $discTotal' : '$discNumber',
      );
    }
    if (year != null && year! > 0) put(l10n.tagYear, '$year');
    put(l10n.tagGenre, genre);
    if (durationMs != null && durationMs! > 0) {
      final d = Duration(milliseconds: durationMs!);
      final mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
      final ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
      put(l10n.tagDuration, d.inHours > 0 ? '${d.inHours}:$mm:$ss' : '$mm:$ss');
    }
    if (bitrate != null && bitrate! > 0) {
      put(l10n.tagBitrate, '${(bitrate! / 1000).round()} kbps');
    }
    if (sampleRate != null && sampleRate! > 0) {
      put(l10n.tagSampleRate, '$sampleRate Hz');
    }
    put(l10n.tagLanguage, language);
    put(l10n.tagLyrics, lyrics);
    return m;
  }
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
      final genre = meta.genres.isNotEmpty
          ? meta.genres.where((g) => g.trim().isNotEmpty).join(', ')
          : null;
      final year = meta.year?.year;
      return ReadTags(
        title: meta.title,
        artist: artist,
        albumArtist: meta.albumArtist,
        album: meta.album,
        durationMs: durationMs,
        trackNumber: meta.trackNumber,
        trackTotal: meta.trackTotal,
        discNumber: meta.discNumber,
        discTotal: meta.totalDisc,
        year: (year != null && year > 0) ? year : null,
        genre: (genre != null && genre.isNotEmpty) ? genre : null,
        bitrate: meta.bitrate,
        sampleRate: meta.sampleRate,
        language: meta.language,
        lyrics: meta.lyrics,
        coverBytes: cover,
      );
    } catch (_) {
      return const ReadTags();
    }
  }
}
