import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class Reciter {
  final String id; // EveryAyah folder
  final String name;
  final String style;
  const Reciter(this.id, this.name, this.style);
}

/// Verse-by-verse recitation files published by EveryAyah.com. Streamed on
/// demand; a study's files can be downloaded for offline listening.
const reciters = [
  Reciter('Alafasy_128kbps', 'Mishary Rashid Alafasy', 'Murattal'),
  Reciter('Husary_128kbps', 'Mahmoud Khalil al-Husary', 'Murattal'),
  Reciter('Minshawy_Murattal_128kbps', 'Mohamed Siddiq al-Minshawi', 'Murattal'),
  Reciter('Abdul_Basit_Murattal_192kbps', 'Abdul Basit Abdus-Samad', 'Murattal'),
];

class AudioService {
  AudioPlayer? _player;
  final ValueNotifier<int?> currentVerse = ValueNotifier(null); // global id
  List<int> _queue = const [];
  List<(int surah, int ayah)> _keys = const [];
  String _reciter = reciters.first.id;
  StreamSubscription<int?>? _idxSub;

  /// Created on first use so screens can render without the audio engine.
  AudioPlayer get player => _player ??= _create();

  AudioPlayer _create() {
    final p = AudioPlayer();
    _idxSub = p.currentIndexStream.listen((i) {
      currentVerse.value = (i == null || i >= _queue.length) ? null : _queue[i];
    });
    p.playerStateStream.listen((s) {
      if (s.processingState == ProcessingState.completed) currentVerse.value = null;
    });
    return p;
  }

  Stream<bool> get playingStream => _player?.playingStream ?? Stream.value(false);

  static String url(String reciter, int surah, int ayah) =>
      'https://everyayah.com/data/$reciter/${surah.toString().padLeft(3, '0')}${ayah.toString().padLeft(3, '0')}.mp3';

  Future<File> _file(String reciter, int surah, int ayah) async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, 'audio', reciter,
        '${surah.toString().padLeft(3, '0')}${ayah.toString().padLeft(3, '0')}.mp3'));
  }

  Future<bool> isDownloaded(String reciter, int surah, int ayah) async =>
      (await _file(reciter, surah, ayah)).exists();

  /// Prepare a study's verses as a playlist (local files when downloaded).
  Future<void> load({
    required String reciter,
    required List<int> verseIds,
    required List<(int, int)> keys,
    int startIndex = 0,
  }) async {
    _reciter = reciter;
    _queue = verseIds;
    _keys = keys;
    final sources = <AudioSource>[];
    for (final (s, a) in keys) {
      final f = await _file(reciter, s, a);
      sources.add(await f.exists() ? AudioSource.file(f.path) : AudioSource.uri(Uri.parse(url(reciter, s, a))));
    }
    await player.setAudioSources(sources, initialIndex: startIndex);
  }

  bool isLoadedFor(List<int> ids, String reciter) => listEquals(ids, _queue) && reciter == _reciter;

  Future<void> playFrom(int index) async {
    await player.seek(Duration.zero, index: index);
    await player.play();
  }

  Future<void> toggle() async => player.playing ? player.pause() : player.play();
  Future<void> next() => player.seekToNext();
  Future<void> previous() => player.seekToPrevious();
  Future<void> replay() async {
    await player.seek(Duration.zero);
    await player.play();
  }

  Future<void> stop() async {
    await _player?.stop();
    currentVerse.value = null;
  }

  /// Download the current study's recitation for offline use.
  Future<int> download(String reciter, List<(int, int)> keys) async {
    var n = 0;
    for (final (s, a) in keys) {
      final f = await _file(reciter, s, a);
      if (await f.exists()) {
        n++;
        continue;
      }
      final r = await http.get(Uri.parse(url(reciter, s, a))).timeout(const Duration(seconds: 30));
      if (r.statusCode == 200 && r.bodyBytes.length > 1000) {
        await f.parent.create(recursive: true);
        await f.writeAsBytes(r.bodyBytes, flush: true);
        n++;
      }
    }
    return n;
  }

  Future<void> dispose() async {
    await _idxSub?.cancel();
    await _player?.dispose();
  }

  List<(int, int)> get keys => _keys;
}
