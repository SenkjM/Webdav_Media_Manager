import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_media_manager/models/webdav_stream.dart';
import 'package:webdav_media_manager/services/stream_cover_reader.dart';

void main() {
    late HttpServer server;
    late Uint8List mp3;
    late Uint8List flac;
    late Uint8List ogg;
    late Uint8List m4a;

    setUpAll(() async {
      mp3 = _minimalMp3();
      flac = _minimalFlac();
      ogg = _minimalOgg();
      m4a = _minimalM4a();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        final name = req.uri.pathSegments.isEmpty
            ? ''
            : req.uri.pathSegments.last;
        final body = switch (name) {
          'a.mp3' => mp3,
          'a.flac' => flac,
          'a.ogg' => ogg,
          'a.m4a' => m4a,
          _ => Uint8List(0),
        };
        final range = req.headers.value(HttpHeaders.rangeHeader);
        if (range == null || !range.startsWith('bytes=')) {
          req.response.statusCode = HttpStatus.ok;
          req.response.add(body);
          await req.response.close();
          return;
        }
        final spec = range.substring(6);
        final parts = spec.split('-');
        final start = int.parse(parts[0]);
        final end = parts[1].isEmpty
            ? body.length - 1
            : int.parse(parts[1]).clamp(0, body.length - 1);
        if (start >= body.length) {
          req.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
          await req.response.close();
          return;
        }
        final slice = body.sublist(start, end + 1);
        req.response.statusCode = HttpStatus.partialContent;
        req.response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes $start-$end/${body.length}',
        );
        req.response.headers.contentLength = slice.length;
        req.response.add(slice);
        await req.response.close();
      });
    });

    tearDownAll(() async {
      await server.close(force: true);
    });

    WebDavStreamSource src(String name) => WebDavStreamSource(
          uri: 'http://127.0.0.1:${server.port}/$name',
          headers: const {},
          name: name,
          remotePath: '/$name',
          accountId: 't',
          kind: StreamKind.music,
        );

    test('mp3 title artist album lyrics cover', () async {
      final tags = await StreamCoverReader().extractTags(src('a.mp3'));
      expect(tags, isNotNull);
      expect(tags!.title, 'Hello');
      expect(tags.artist, 'Artist');
      expect(tags.album, 'Album');
      expect(tags.lyrics, contains('line one'));
      expect(tags.coverBytes, isNotNull);
      expect(tags.coverBytes!.isNotEmpty, isTrue);
    });

    test('flac vorbis comment and lyrics', () async {
      final tags = await StreamCoverReader().extractTags(src('a.flac'));
      expect(tags, isNotNull);
      expect(tags!.title, 'FlacTitle');
      expect(tags.artist, 'FlacArtist');
      expect(tags.lyrics, contains('flac lyric'));
    });

    test('ogg vorbis comment without scanning past EOS', () async {
      final tags = await StreamCoverReader().extractTags(src('a.ogg'));
      expect(tags, isNotNull);
      expect(tags!.title, 'OggTitle');
      expect(tags.artist, 'OggArtist');
      expect(tags.lyrics, contains('ogg lyric'));
      // Synthetic EOS leaves duration empty.
      expect(tags.durationMs, isNull);
    });

    test('m4a ilst text and lyrics', () async {
      final tags = await StreamCoverReader().extractTags(src('a.m4a'));
      expect(tags, isNotNull);
      expect(tags!.title, 'M4aTitle');
      expect(tags.artist, 'M4aArtist');
      expect(tags.lyrics, contains('m4a lyric'));
    });
  });
}

Uint8List _minimalMp3() {
  // ID3v2.3 with TIT2, TPE1, TALB, USLT, APIC (1x1 JPEG).
  final frames = BytesBuilder();
  void textFrame(String id, String value) {
    final encoded = <int>[0x03, ...utf8.encode(value)]; // UTF-8
    final body = Uint8List.fromList(encoded);
    final frame = BytesBuilder();
    frame.add(id.codeUnits);
    frame.add([
      (body.length >> 24) & 0xff,
      (body.length >> 16) & 0xff,
      (body.length >> 8) & 0xff,
      body.length & 0xff,
    ]);
    frame.add([0, 0]); // flags
    frame.add(body);
    frames.add(frame.toBytes());
  }

  textFrame('TIT2', 'Hello');
  textFrame('TPE1', 'Artist');
  textFrame('TALB', 'Album');

  // USLT: encoding, lang, content descriptor \0, lyrics
  final usltBody = BytesBuilder()
    ..add([0x03]) // UTF-8
    ..add('eng'.codeUnits)
    ..add([0x00]) // empty descriptor
    ..add(utf8.encode('line one\nline two'));
  final uslt = usltBody.toBytes();
  frames.add('USLT'.codeUnits);
  frames.add([
    (uslt.length >> 24) & 0xff,
    (uslt.length >> 16) & 0xff,
    (uslt.length >> 8) & 0xff,
    uslt.length & 0xff,
  ]);
  frames.add([0, 0]);
  frames.add(uslt);

  // Tiny JPEG (1x1)
  final jpeg = base64.decode(
    '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRof'
    'Hh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgNDRgyIRwh'
    'MjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjL/wAAR'
    'CAABAAEDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAn/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/8QAFQEBAQAAAAAAAAAAAAAAAAAAAAX/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIQAxAAAAGfAP/EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAQUCf//EABQRAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQMBAT8Bf//EABQRAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQIBAT8Bf//EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEABj8Cf//EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAT8hf//Z',
  );
  final apicBody = BytesBuilder()
    ..add([0x03])
    ..add(utf8.encode('image/jpeg'))
    ..add([0x00])
    ..add([0x03]) // cover front
    ..add([0x00]) // empty desc
    ..add(jpeg);
  final apic = apicBody.toBytes();
  frames.add('APIC'.codeUnits);
  frames.add([
    (apic.length >> 24) & 0xff,
    (apic.length >> 16) & 0xff,
    (apic.length >> 8) & 0xff,
    apic.length & 0xff,
  ]);
  frames.add([0, 0]);
  frames.add(apic);

  final payload = frames.toBytes();
  final size = payload.length;
  // synchsafe size
  final ss = [
    (size >> 21) & 0x7f,
    (size >> 14) & 0x7f,
    (size >> 7) & 0x7f,
    size & 0x7f,
  ];
  final out = BytesBuilder()
    ..add('ID3'.codeUnits)
    ..add([3, 0, 0])
    ..add(ss)
    ..add(payload)
    // pad a fake MPEG frame sync so sniff still works if needed
    ..add([0xff, 0xfb, 0x90, 0x00]);
  return out.toBytes();
}

Uint8List _minimalFlac() {
  // fLaC + STREAMINFO(last=0) + VORBIS_COMMENT(last=1)
  final out = BytesBuilder()..add('fLaC'.codeUnits);

  // STREAMINFO type0 length 34
  final streamInfo = Uint8List(34);
  // min/max block size 16
  streamInfo[0] = 0;
  streamInfo[1] = 16;
  streamInfo[2] = 0;
  streamInfo[3] = 16;
  // 64-bit field at offset 10: rate=44100, ch=2, bps=16, samples=44100
  final packed = (44100 << 44) | (1 << 41) | (15 << 36) | 44100;
  for (var i = 0; i < 8; i++) {
    streamInfo[10 + i] = (packed >> (56 - 8 * i)) & 0xff;
  }
  out.add([0x00, 0x00, 0x00, 34]); // not last, type 0, len 34
  out.add(streamInfo);

  final comments = _vorbisCommentPacket(
    vendor: 'test',
    comments: {
      'TITLE': 'FlacTitle',
      'ARTIST': 'FlacArtist',
      'ALBUM': 'FlacAlbum',
      'LYRICS': 'flac lyric line',
    },
  );
  final len = comments.length;
  out.add([0x84, (len >> 16) & 0xff, (len >> 8) & 0xff, len & 0xff]); // last + type4
  out.add(comments);
  return out.toBytes();
}

Uint8List _vorbisCommentPacket({
  required String vendor,
  required Map<String, String> comments,
}) {
  final b = BytesBuilder();
  final vendorBytes = utf8.encode(vendor);
  b.add(_u32le(vendorBytes.length));
  b.add(vendorBytes);
  b.add(_u32le(comments.length));
  for (final e in comments.entries) {
    final c = utf8.encode('${e.key}=${e.value}');
    b.add(_u32le(c.length));
    b.add(c);
  }
  return b.toBytes();
}

List<int> _u32le(int v) => [v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >> 24) & 0xff];

Uint8List _minimalOgg() {
  // Two Ogg pages: OpusHead + OpusTags (with LYRICS).
  final headPacket = BytesBuilder()
    ..add('OpusHead'.codeUnits)
    ..add([
      1, // version
      2, // channels
      0, 0, // pre-skip
      0x80, 0xbb, 0x00, 0x00, // 48000 sample rate LE
      0, 0, // gain
      0, // mapping family
    ]);
  final tagsBody = _vorbisCommentPacket(
    vendor: 'test',
    comments: {
      'TITLE': 'OggTitle',
      'ARTIST': 'OggArtist',
      'LYRICS': 'ogg lyric line',
      'UNSYNCEDLYRICS': 'should not override LYRICS',
    },
  );
  final tagsPacket = BytesBuilder()
    ..add('OpusTags'.codeUnits)
    ..add(tagsBody);

  final page1 = _oggPage(
    headerType: 0x02, // BOS
    granule: 0,
    serial: 0x12345678,
    sequence: 0,
    packet: headPacket.toBytes(),
  );
  final page2 = _oggPage(
    headerType: 0x00,
    granule: 0,
    serial: 0x12345678,
    sequence: 1,
    packet: tagsPacket.toBytes(),
  );
  return Uint8List.fromList([...page1, ...page2]);
}

Uint8List _oggPage({
  required int headerType,
  required int granule,
  required int serial,
  required int sequence,
  required Uint8List packet,
}) {
  final segments = <int>[];
  var remaining = packet.length;
  var offset = 0;
  final body = BytesBuilder();
  while (true) {
    final n = remaining > 255 ? 255 : remaining;
    segments.add(n);
    body.add(packet.sublist(offset, offset + n));
    offset += n;
    remaining -= n;
    if (n < 255) break;
  }
  final header = BytesBuilder()
    ..add('OggS'.codeUnits)
    ..add([0]) // version
    ..add([headerType])
    ..add(_u32le(granule & 0xffffffff))
    ..add(_u32le((granule >> 32) & 0xffffffff))
    ..add(_u32le(serial))
    ..add(_u32le(sequence))
    ..add([0, 0, 0, 0]) // crc
    ..add([segments.length])
    ..add(segments);
  return Uint8List.fromList([...header.toBytes(), ...body.toBytes()]);
}

Uint8List _minimalM4a() {
  // ftyp + moov/udta/meta/ilst with ©nam ©ART ©lyr
  Uint8List box(String type, List<int> payload) {
    final size = 8 + payload.length;
    return Uint8List.fromList([
      (size >> 24) & 0xff,
      (size >> 16) & 0xff,
      (size >> 8) & 0xff,
      size & 0xff,
      ...type.codeUnits,
      ...payload,
    ]);
  }

  Uint8List dataString(String value) {
    final bytes = utf8.encode(value);
    // 'data' box: size, 'data', type(1=UTF8), locale, payload
    final inner = [
      0, 0, 0, 1, // type indicator UTF-8
      0, 0, 0, 0, // locale
      ...bytes,
    ];
    return box('data', inner);
  }

  Uint8List textAtom(String fourcc, String value) =>
      box(fourcc, dataString(value));

  final ilst = box('ilst', [
    ...textAtom('©nam', 'M4aTitle'),
    ...textAtom('©ART', 'M4aArtist'),
    ...textAtom('©alb', 'M4aAlbum'),
    ...textAtom('©lyr', 'm4a lyric line'),
  ]);
  // meta: 4-byte version/flags then ilst
  final meta = box('meta', [0, 0, 0, 0, ...ilst]);
  final udta = box('udta', meta);
  // mvhd: version byte + 99 bytes (timescale / duration).
  final mvhdBody = Uint8List(100);
  // timescale at offset 12..15 of the 99-byte chunk = bytes[11..14] after version in full payload
  // bytes = buffer.read(99) after version; timeScale at bytes.sublist(11,15)
  mvhdBody[0] = 0; // version
  // set timescale=1000, duration=5000 in the 99-byte region
  // indices in mvhdBody: 1+11=12 for timescale start
  mvhdBody[12] = 0;
  mvhdBody[13] = 0;
  mvhdBody[14] = 0x03;
  mvhdBody[15] = 0xe8; // 1000
  mvhdBody[16] = 0;
  mvhdBody[17] = 0;
  mvhdBody[18] = 0x13;
  mvhdBody[19] = 0x88; // 5000
  final mvhd = box('mvhd', mvhdBody);
  final moov = box('moov', [...mvhd, ...udta]);
  final ftyp = box('ftyp', [...'M4A '.codeUnits, 0, 0, 0, 0, ...'M4A '.codeUnits]);
  return Uint8List.fromList([...ftyp, ...moov]);
}
