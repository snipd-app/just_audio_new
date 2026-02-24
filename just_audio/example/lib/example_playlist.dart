// This example demonstrates how to play a playlist with a mix of URI and asset
// audio sources, and the ability to add/remove/reorder playlist items.
//
// To run:
//
// flutter run -t lib/example_playlist.dart

import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'media_kit_stub.dart' if (dart.library.io) 'media_kit_impl.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_example/common.dart';
import 'package:rxdart/rxdart.dart';

void main() {
  initMediaKit(); // Initialise just_audio_media_kit for Linux/Windows.
  // Enable gapless playback on Linux/Windows (experimental):
  // JustAudioMediaKit.prefetchPlaylist = true;
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  MyAppState createState() => MyAppState();
}

class MyAppState extends State<MyApp> with WidgetsBindingObserver {
  late AudioPlayer _player;
  double _preloadBufferSeconds = 30.0;
  double _preferredForwardBufferSeconds = 30.0;
  DateTime? _playPressedTime;
  final Map<int, int> _itemArrivalMs = {};
  final Map<int, Duration> _itemBuffered = {};
  final Map<int, Duration> _itemDuration = {};

  static final _playlist = [
    AudioSource.uri(
      Uri.parse(
          "https://storage.googleapis.com/ai_dj_audio/messages/users/D041uzAuqmeIRY5CvvE6nQUK3Vv2/msg_user_hey__7367922848854d57bc488cbd048ae324.mp3"),
      tag: AudioMetadata(
        album: "AI DJ - Hey",
        title: "AI DJ - Hey",
        artwork: "",
      ),
    ),
    SilenceStreamAudioSource(
        duration: const Duration(milliseconds: 200),
        tag:
            AudioMetadata(album: "Silence 1", title: "Silence 1", artwork: "")),
    AudioSource.uri(
      Uri.parse(
          "https://storage.googleapis.com/ai_dj_audio/episode_highlights/578427c8-c579-4402-8914-a33f4461bd9f/00__e0b0794e75a6494a89cc548d976f6682.mp3"),
      tag: AudioMetadata(
        album: "AI DJ - Intro",
        title: "AI DJ - Intro",
        artwork: "",
      ),
    ),
    SilenceStreamAudioSource(
        duration: const Duration(milliseconds: 1000),
        tag:
            AudioMetadata(album: "Silence 2", title: "Silence 2", artwork: "")),
    AudioSource.uri(
      Uri.parse(
          "https://storage.googleapis.com/ai_dj_audio/episode_highlights/578427c8-c579-4402-8914-a33f4461bd9f/01__11dabf89a28b435288bafe86080d1a95.mp3"),
      tag: AudioMetadata(
        album: "AI DJ - Highlight 1 - Intro",
        title: "AI DJ - Highlight 1 - Intro",
        artwork: "",
      ),
    ),
    SilenceStreamAudioSource(
        duration: const Duration(milliseconds: 1000),
        tag:
            AudioMetadata(album: "Silence 2", title: "Silence 2", artwork: "")),
    AudioSource.uri(
      Uri.parse(
          "https://storage.googleapis.com/ai_dj_audio/episode_highlights/578427c8-c579-4402-8914-a33f4461bd9f/02__56812fee7031416c906dd0f6623e0459.mp3"),
      tag: AudioMetadata(
        album: "AI DJ - Highlight 2 - Intro",
        title: "AI DJ - Highlight 2 - Intro",
        artwork: "",
      ),
    ),
  ];
  int _addedCount = 0;
  final _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

  @override
  void initState() {
    super.initState();
    ambiguate(WidgetsBinding.instance)!.addObserver(this);
    _player = _createPlayer();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.black,
    ));
    _init();
  }

  AudioPlayer _createPlayer() {
    return AudioPlayer(
      maxSkipsOnError: 3,
      audioLoadConfiguration: AudioLoadConfiguration(
        darwinLoadControl: DarwinLoadControl(
          preloadBufferDuration:
              Duration(milliseconds: (_preloadBufferSeconds * 1000).round()),
          preferredForwardBufferDuration: Duration(
              milliseconds: (_preferredForwardBufferSeconds * 1000).round()),
        ),
        androidLoadControl: AndroidLoadControl(
          bufferForPlaybackDuration: Duration(
              milliseconds: (_preferredForwardBufferSeconds * 1000).round()),
          bufferForPlaybackAfterRebufferDuration: Duration(
              milliseconds: (_preferredForwardBufferSeconds * 1000).round()),
        ),
      ),
      // useLazyPreparation: false,
    );
  }

  Future<void> _resetPlayer() async {
    await _player.dispose();
    setState(() {
      _player = _createPlayer();
      _playPressedTime = null;
      _itemArrivalMs.clear();
      _itemBuffered.clear();
      _itemDuration.clear();
    });
    await _init();
  }

  Future<void> _init() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.speech());
    // Listen to errors during playback.
    _player.errorStream.listen((e) {
      print('A stream error occurred: $e');
    });
    try {
      await _player.setAudioSources(_playlist);
    } on PlayerException catch (e) {
      // Catch load errors: 404, invalid url...
      print("Error loading playlist: $e");
    }
    // Record ms from Play press to each item becoming current.
    _player.currentIndexStream.listen((idx) {
      if (idx == null) return;
      final start = _playPressedTime;
      if (start == null) return;
      if (!_itemArrivalMs.containsKey(idx)) {
        setState(() {
          _itemArrivalMs[idx] = DateTime.now().difference(start).inMilliseconds;
        });
      }
    });

    // Show a snackbar whenever reaching the end of an item in the playlist.
    _player.positionDiscontinuityStream.listen((discontinuity) {
      if (discontinuity.reason == PositionDiscontinuityReason.autoAdvance) {
        _showItemFinished(discontinuity.previousEvent.currentIndex);
      }
    });
    _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        _showItemFinished(_player.currentIndex);
      }
    });
  }

  void _onPlayPressed() {
    setState(() {
      _playPressedTime = DateTime.now();
      _itemArrivalMs.clear();
    });
    _player.play();
  }

  void _resetTiming() {
    setState(() {
      _playPressedTime = null;
      _itemArrivalMs.clear();
      _itemBuffered.clear();
      _itemDuration.clear();
    });
  }

  String _fmtDuration(Duration d) {
    final s = d.inMilliseconds / 1000.0;
    return s >= 60
        ? '${d.inMinutes}m${(d.inSeconds % 60).toString().padLeft(2, '0')}s'
        : '${s.toStringAsFixed(1)}s';
  }

  Widget? _buildItemSubtitle(int i) {
    final buf = _itemBuffered[i];
    final dur = _itemDuration[i];
    final arrivalMs = _itemArrivalMs[i];

    if (buf == null && arrivalMs == null) return null;

    final double? fraction = (buf != null && dur != null && dur > Duration.zero)
        ? (buf.inMicroseconds / dur.inMicroseconds).clamp(0.0, 1.0)
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (fraction != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 2.0),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 3,
              backgroundColor: Colors.grey.shade300,
              valueColor: AlwaysStoppedAnimation<Color>(
                fraction >= 1.0 ? Colors.green.shade400 : Colors.blue.shade300,
              ),
            ),
          ),
        Row(
          children: [
            if (buf != null)
              Text(
                dur != null
                    ? '${_fmtDuration(buf)} / ${_fmtDuration(dur)} buffered'
                    : '${_fmtDuration(buf)} buffered',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            if (buf != null && arrivalMs != null)
              Text(
                '  ·  ',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
              ),
            if (arrivalMs != null)
              Text(
                '+${arrivalMs}ms',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
          ],
        ),
      ],
    );
  }

  void _showItemFinished(int? index) {
    if (index == null) return;
    final sequence = _player.sequence;
    if (index >= sequence.length) return;
    final source = sequence[index];
    final metadata = source.tag as AudioMetadata;
    // _scaffoldMessengerKey.currentState?.showSnackBar(SnackBar(
    //   content: Text('Finished playing ${metadata.title}'),
    //   duration: const Duration(seconds: 1),
    // ));
  }

  @override
  void dispose() {
    ambiguate(WidgetsBinding.instance)!.removeObserver(this);
    _player.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // Release the player's resources when not in use. We use "stop" so that
      // if the app resumes later, it will still remember what position to
      // resume from.
      _player.stop();
    }
  }

  Stream<PositionData> get _positionDataStream =>
      Rx.combineLatest3<Duration, Duration, Duration?, PositionData>(
          _player.positionStream,
          _player.bufferedPositionStream,
          _player.durationStream,
          (position, bufferedPosition, duration) => PositionData(
              position, bufferedPosition, duration ?? Duration.zero));

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: _scaffoldMessengerKey,
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Playlist Example'),
          actions: [
            TextButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('Reset Player'),
              onPressed: _resetPlayer,
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: StreamBuilder<SequenceState?>(
                  stream: _player.sequenceStateStream,
                  builder: (context, snapshot) {
                    final state = snapshot.data;
                    if (state?.sequence.isEmpty ?? true) {
                      return const SizedBox();
                    }
                    final metadata = state!.currentSource!.tag as AudioMetadata;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child:
                                Center(child: Image.network(metadata.artwork)),
                          ),
                        ),
                        Text(metadata.album,
                            style: Theme.of(context).textTheme.titleLarge),
                        Text(metadata.title),
                      ],
                    );
                  },
                ),
              ),
              ControlButtons(_player, onPlay: _onPlayPressed),
              StreamBuilder<PositionData>(
                stream: _positionDataStream,
                builder: (context, snapshot) {
                  final positionData = snapshot.data;
                  return SeekBar(
                    duration: positionData?.duration ?? Duration.zero,
                    position: positionData?.position ?? Duration.zero,
                    bufferedPosition:
                        positionData?.bufferedPosition ?? Duration.zero,
                    onChangeEnd: (newPosition) {
                      _player.seek(newPosition);
                    },
                  );
                },
              ),
              StreamBuilder<Duration>(
                stream: _player.bufferedPositionStream,
                builder: (context, snapshot) {
                  final buffered = snapshot.data ?? Duration.zero;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Text(
                      'Buffered: ${_fmtDuration(buffered)}',
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                  );
                },
              ),
              const SizedBox(height: 4.0),
              _BufferSlider(
                label: 'Preload buffer',
                value: _preloadBufferSeconds,
                onChanged: (v) => setState(() => _preloadBufferSeconds = v),
              ),
              _BufferSlider(
                label: 'Preferred forward buffer',
                value: _preferredForwardBufferSeconds,
                onChanged: (v) =>
                    setState(() => _preferredForwardBufferSeconds = v),
              ),
              const SizedBox(height: 4.0),
              Row(
                children: [
                  StreamBuilder<LoopMode>(
                    stream: _player.loopModeStream,
                    builder: (context, snapshot) {
                      final loopMode = snapshot.data ?? LoopMode.off;
                      const icons = [
                        Icon(Icons.repeat, color: Colors.grey),
                        Icon(Icons.repeat, color: Colors.orange),
                        Icon(Icons.repeat_one, color: Colors.orange),
                      ];
                      const cycleModes = [
                        LoopMode.off,
                        LoopMode.all,
                        LoopMode.one,
                      ];
                      final index = cycleModes.indexOf(loopMode);
                      return IconButton(
                        icon: icons[index],
                        onPressed: () {
                          _player.setLoopMode(cycleModes[
                              (cycleModes.indexOf(loopMode) + 1) %
                                  cycleModes.length]);
                        },
                      );
                    },
                  ),
                  Expanded(
                    child: Text(
                      "Playlist",
                      style: Theme.of(context).textTheme.titleLarge,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.timer_off),
                    tooltip: 'Reset timing',
                    onPressed: _resetTiming,
                  ),
                  StreamBuilder<bool>(
                    stream: _player.shuffleModeEnabledStream,
                    builder: (context, snapshot) {
                      final shuffleModeEnabled = snapshot.data ?? false;
                      return IconButton(
                        icon: shuffleModeEnabled
                            ? const Icon(Icons.shuffle, color: Colors.orange)
                            : const Icon(Icons.shuffle, color: Colors.grey),
                        onPressed: () async {
                          final enable = !shuffleModeEnabled;
                          if (enable) {
                            await _player.shuffle();
                          }
                          await _player.setShuffleModeEnabled(enable);
                        },
                      );
                    },
                  ),
                ],
              ),
              SizedBox(
                height: 240.0,
                child: StreamBuilder<(SequenceState?, PlaybackEvent)>(
                  stream: Rx.combineLatest2(
                    _player.sequenceStateStream,
                    _player.playbackEventStream,
                    (a, b) => (a, b),
                  ),
                  builder: (context, snapshot) {
                    final seqState = snapshot.data?.$1;
                    final event = snapshot.data?.$2;
                    final sequence = seqState?.sequence ?? [];

                    // Cache buffer state for the currently playing item.
                    final currentIdx = event?.currentIndex;
                    if (currentIdx != null && event != null) {
                      _itemBuffered[currentIdx] = event.bufferedPosition;
                      if (event.duration != null) {
                        _itemDuration[currentIdx] = event.duration!;
                      }
                    }

                    return ReorderableListView(
                      onReorder: (int oldIndex, int newIndex) {
                        if (oldIndex < newIndex) newIndex--;
                        _player.moveAudioSource(oldIndex, newIndex);
                      },
                      children: [
                        for (var i = 0; i < sequence.length; i++)
                          Dismissible(
                            key: ValueKey(sequence[i]),
                            background: Container(
                              color: Colors.redAccent,
                              alignment: Alignment.centerRight,
                              child: const Padding(
                                padding: EdgeInsets.only(right: 8.0),
                                child: Icon(Icons.delete, color: Colors.white),
                              ),
                            ),
                            onDismissed: (dismissDirection) =>
                                _player.removeAudioSourceAt(i),
                            child: Material(
                              color: i == seqState?.currentIndex
                                  ? Colors.grey.shade300
                                  : null,
                              child: ListTile(
                                title: Text(sequence[i].tag.title as String),
                                subtitle: _buildItemSubtitle(i),
                                onTap: () => _player
                                    .seek(Duration.zero, index: i)
                                    .catchError((e, st) {}),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton(
          child: const Icon(Icons.add),
          onPressed: () {
            _player.addAudioSource(AudioSource.uri(
              Uri.parse("asset:///audio/nature.mp3"),
              tag: AudioMetadata(
                album: "Public Domain",
                title: "Nature Sounds ${++_addedCount}",
                artwork:
                    "https://media.wnyc.org/i/1400/1400/l/80/1/ScienceFriday_WNYCStudios_1400.jpg",
              ),
            ));
          },
        ),
      ),
    );
  }
}

class ControlButtons extends StatelessWidget {
  final AudioPlayer player;
  final VoidCallback? onPlay;

  const ControlButtons(this.player, {Key? key, this.onPlay}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.volume_up),
          onPressed: () {
            showSliderDialog(
              context: context,
              title: "Adjust volume",
              divisions: 10,
              min: 0.0,
              max: 1.0,
              value: player.volume,
              stream: player.volumeStream,
              onChanged: player.setVolume,
            );
          },
        ),
        StreamBuilder<SequenceState?>(
          stream: player.sequenceStateStream,
          builder: (context, snapshot) => IconButton(
            icon: const Icon(Icons.skip_previous),
            onPressed: player.hasPrevious ? player.seekToPrevious : null,
          ),
        ),
        StreamBuilder<(bool, ProcessingState, int)>(
          stream: Rx.combineLatest2(
              player.playerEventStream,
              player.sequenceStream,
              (event, sequence) => (
                    event.playing,
                    event.playbackEvent.processingState,
                    sequence.length,
                  )),
          builder: (context, snapshot) {
            final (playing, processingState, sequenceLength) =
                snapshot.data ?? (false, null, 0);
            if (processingState == ProcessingState.loading ||
                processingState == ProcessingState.buffering) {
              return Container(
                margin: const EdgeInsets.all(8.0),
                width: 64.0,
                height: 64.0,
                child: const CircularProgressIndicator(),
              );
            } else if (!playing) {
              return IconButton(
                icon: const Icon(Icons.play_arrow),
                iconSize: 64.0,
                onPressed: sequenceLength > 0 ? (onPlay ?? player.play) : null,
              );
            } else if (processingState != ProcessingState.completed) {
              return IconButton(
                icon: const Icon(Icons.pause),
                iconSize: 64.0,
                onPressed: player.pause,
              );
            } else {
              return IconButton(
                icon: const Icon(Icons.replay),
                iconSize: 64.0,
                onPressed: sequenceLength > 0
                    ? () => player.seek(Duration.zero,
                        index: player.effectiveIndices.first)
                    : null,
              );
            }
          },
        ),
        StreamBuilder<SequenceState?>(
          stream: player.sequenceStateStream,
          builder: (context, snapshot) => IconButton(
            icon: const Icon(Icons.skip_next),
            onPressed: player.hasNext ? player.seekToNext : null,
          ),
        ),
        StreamBuilder<double>(
          stream: player.speedStream,
          builder: (context, snapshot) => IconButton(
            icon: Text("${snapshot.data?.toStringAsFixed(1)}x",
                style: const TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () {
              showSliderDialog(
                context: context,
                title: "Adjust speed",
                divisions: 10,
                min: 0.5,
                max: 1.5,
                value: player.speed,
                stream: player.speedStream,
                onChanged: player.setSpeed,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _BufferSlider extends StatelessWidget {
  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  const _BufferSlider({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  String _fmt(double seconds) {
    if (seconds >= 60) {
      final m = (seconds / 60).floor();
      final s = (seconds % 60).round();
      return '${m}m${s.toString().padLeft(2, '0')}s';
    }
    return '${seconds.round()}s';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Row(
        children: [
          SizedBox(
            width: 148,
            child: Text(
              '$label: ${_fmt(value)}',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
            ),
          ),
          Expanded(
            child: Slider(
              value: value,
              min: 0,
              max: 600,
              divisions: 60,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class AudioMetadata {
  final String album;
  final String title;
  final String artwork;

  AudioMetadata({
    required this.album,
    required this.title,
    required this.artwork,
  });
}

/// Generates silent WAV audio of a given duration.
///
/// WAV construction runs on a background isolate at creation time so the
/// UI thread is never blocked. Identical durations share the same buffer
/// via an LRU cache (max [_maxCacheEntries]) to avoid redundant allocations
/// without unbounded memory growth.
///
class SilenceStreamAudioSource extends StreamAudioSource {
  SilenceStreamAudioSource({required Duration duration, dynamic tag})
      : _bytesFuture = _getOrBuildWav(duration),
        super(tag: tag);

  static const _sampleRate = 44100;
  static const _channels = 2;
  static const _bitsPerSample = 16;
  static const _bytesPerSample = _channels * (_bitsPerSample ~/ 8);
  static const _headerSize = 44;
  static const _maxCacheEntries = 8;

  /// LRU cache of WAV buffers keyed by duration in microseconds.
  /// [LinkedHashMap] maintains insertion order, so [keys.first] is the
  /// least-recently-used entry.
  static final LinkedHashMap<int, Future<Uint8List>> _cache =
      LinkedHashMap<int, Future<Uint8List>>();

  final Future<Uint8List> _bytesFuture;

  static Future<Uint8List> _getOrBuildWav(Duration duration) {
    final key = duration.inMicroseconds;

    final existing = _cache.remove(key);
    if (existing != null) {
      _cache[key] = existing;
      return existing;
    }

    final future = compute(_buildWav, duration);
    _cache[key] = future;

    if (_cache.length > _maxCacheEntries) {
      _cache.remove(_cache.keys.first);
    }

    return future;
  }

  /// Releases all cached WAV buffers.
  ///
  /// Call when playback is torn down to reclaim memory.
  static void clearCache() => _cache.clear();

  static Uint8List _buildWav(Duration duration) {
    final samples = (duration.inMicroseconds * _sampleRate + 500000) ~/ 1000000;
    final dataLength = samples * _bytesPerSample;

    // Uint8List is zero-initialized, so the PCM data region is already silence.
    final wav = Uint8List(_headerSize + dataLength);
    final writer = ByteData.sublistView(wav);

    // RIFF header
    writer.setUint32(0, 0x52494646, Endian.big); // "RIFF"
    writer.setUint32(4, 36 + dataLength, Endian.little);
    writer.setUint32(8, 0x57415645, Endian.big); // "WAVE"

    // Subchunk1 (format)
    writer.setUint32(12, 0x666D7420, Endian.big); // "fmt "
    writer.setUint32(16, 16, Endian.little); // Subchunk1 size
    writer.setUint16(20, 1, Endian.little); // PCM format
    writer.setUint16(22, _channels, Endian.little);
    writer.setUint32(24, _sampleRate, Endian.little);
    writer.setUint32(
      28,
      _sampleRate * _bytesPerSample,
      Endian.little,
    ); // byte rate
    writer.setUint16(32, _bytesPerSample, Endian.little); // block align
    writer.setUint16(34, _bitsPerSample, Endian.little);

    // Subchunk2 (data)
    writer.setUint32(36, 0x64617461, Endian.big); // "data"
    writer.setUint32(40, dataLength, Endian.little);

    return wav;
  }

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final bytes = await _bytesFuture;

    start ??= 0;
    end ??= bytes.length;

    print('>> SilenceStreamAudioSource request: $start, $end');

    return StreamAudioResponse(
      sourceLength: bytes.length,
      contentLength: end - start,
      offset: start,
      stream: Stream.value(Uint8List.sublistView(bytes, start, end)),
      contentType: 'audio/wav',
    );
  }
}
