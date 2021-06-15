import 'dart:async';

import 'package:flutter/services.dart';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

class VideoThumbnail {
  VideoThumbnail({required this.width, required this.height, this.data});

  final int width;
  final int height;
  final Uint8List? data;

  VideoThumbnail.fromMap(Map m)
      : this(
            width: m["width"],
            height: m["height"],
            data: m["data"] != null
                ? m["data"] is String
                    ? base64.decode(m["data"])
                    : m["data"]
                : null);

  @override
  String toString() {
    return "width:$width, height:$height, length=${data?.length}";
  }

  Map<String, dynamic> toMap() {
    return {
      'width': width,
      'height': height,
      'data': data != null ? base64.encode(data!) : null,
    };
  }
}

typedef OnLatestThumbnailAvailable = Function(VideoThumbnail image);

/// This is thrown when the plugin reports an error.
class VideoTrimException implements Exception {
  VideoTrimException(this.code, {this.description});

  String code;
  String? description;

  @override
  String toString() => '$runtimeType($code, $description)';
}

/// The state of a [FetchVideoThumbnailnailTaskValue].
class FetchVideoThumbnailnailTaskValue {
  const FetchVideoThumbnailnailTaskValue(
      {this.thumbnail, this.errorDescription, this.isRunning = false});

  const FetchVideoThumbnailnailTaskValue.uninitialized()
      : this(
          thumbnail: null,
          isRunning: false,
        );

  /// True when fetching thumbnails have isRunning.
  final VideoThumbnail? thumbnail;

  final String? errorDescription;

  final bool isRunning;

  bool get hasError => errorDescription != null;

  FetchVideoThumbnailnailTaskValue copyWith({
    VideoThumbnail? thumbnail,
    String? errorDescription,
    bool? isRunning,
  }) {
    return FetchVideoThumbnailnailTaskValue(
      errorDescription: errorDescription,
      thumbnail: thumbnail ?? this.thumbnail,
      isRunning: isRunning ?? this.isRunning,
    );
  }

  @override
  String toString() {
    return '$runtimeType('
        'thumbnail: $thumbnail, '
        'isRunning: $isRunning, '
        'errorDescription: $errorDescription, ';
  }
}

class FetchVideoThumbnailnailTask
    extends ValueNotifier<FetchVideoThumbnailnailTaskValue> {
  final String videoPath;
  final int handle;
  final EventChannel eventChannel;
  late StreamSubscription<dynamic> _thumbnailStreamSubscription;
  bool _isDisposed = false;
  FetchVideoThumbnailnailTask._internal(
      this.videoPath, this.handle, OnLatestThumbnailAvailable callback)
      : eventChannel = EventChannel(
            'github.com/peerwaya/gotok/video_trimmer/thumbnailStream/$handle'),
        super(const FetchVideoThumbnailnailTaskValue.uninitialized()) {
    _thumbnailStreamSubscription =
        eventChannel.receiveBroadcastStream().listen((dynamic imageData) {
      final thumbnail = VideoThumbnail.fromMap(imageData);
      callback(thumbnail);
      value = value.copyWith(thumbnail: thumbnail);
    });
  }

  start(
      int startMs, int endMs, int totalThumbsCount, Size thumbnailSize) async {
    try {
      if (_isDisposed) {
        throw VideoTrimException(
          'Request Disposed.',
          description: 'start was called on a disposed thumbnail fetch task',
        );
      }
      if (value.isRunning) {
        throw VideoTrimException(
          'A fetch request is already running.',
          description:
              'start was called while a fetch request is already running.',
        );
      }
      bool isRunning =
          await VideoTrimmer._channel.invokeMethod('startVideoThumbsRequest', {
        "handle": handle,
        "startMs": startMs,
        "endMs": endMs,
        "totalThumbsCount": totalThumbsCount,
        "width": thumbnailSize.width,
        "height": thumbnailSize.height
      });
      value = value.copyWith(
        isRunning: isRunning,
      );
    } on PlatformException catch (e) {
      value = value.copyWith(isRunning: false);
      throw VideoTrimException(e.code, description: e.message);
    }
  }

  stop() async {
    try {
      if (_isDisposed) {
        throw VideoTrimException(
          'Request Disposed.',
          description: 'start was called on a disposed thumbnail fetch task',
        );
      }
      if (!value.isRunning) {
        throw VideoTrimException(
          'A fetch request is not running.',
          description: 'stop was called while a fetch request is not running.',
        );
      }
      await VideoTrimmer._channel.invokeMethod('stopVideoThumbsRequest', {
        "handle": handle,
      });
      value = value.copyWith(
        isRunning: false,
      );
    } on PlatformException catch (e) {
      value = value.copyWith(isRunning: true);
      throw VideoTrimException(e.code, description: e.message);
    }
  }

  /// Releases the resources of this task.
  @override
  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }
    await VideoTrimmer._channel.invokeMethod(
      'removeVideoThumbsRequest',
      <String, dynamic>{'handle': handle},
    );
    await _thumbnailStreamSubscription.cancel();
    _isDisposed = true;
    super.dispose();
  }
}

class VideoTrimmer {
  static const MethodChannel _channel =
      MethodChannel('github.com/peerwaya/gotok/video_trimmer');

  static Future<String> trimVideo(
      String inputFile, String outputFile, int startMs, int endMs) async {
    try {
      int ret = await _channel.invokeMethod('trimVideo', {
        "inputFile": inputFile,
        "outputFile": outputFile,
        "startMs": startMs,
        "endMs": endMs
      });
      if (ret != 0) {
        throw VideoTrimException("failed", description: "error code $ret");
      }
      return outputFile;
    } on PlatformException catch (e) {
      throw VideoTrimException(e.code, description: e.message);
    }
  }

  static Future<void> saveToLibrary(String inputFile) async {
    try {
      await _channel.invokeMethod('saveToLibrary', {
        "inputFile": inputFile,
      });
    } on PlatformException catch (e) {
      throw VideoTrimException(e.code, description: e.message);
    }
  }

  static Future<VideoThumbnail> extractThumbnail(String inputFile, Size size,
      {int start = 0, int end = 0}) async {
    try {
      final result = await _channel.invokeMethod('extractThumbnail', {
        "inputFile": inputFile,
        "width": size.width,
        "height": size.height,
        "startMs": start,
        "endMs": end
      });
      return VideoThumbnail.fromMap(result);
    } on PlatformException catch (e) {
      throw VideoTrimException(e.code, description: e.message);
    }
  }

  static Future<List<VideoThumbnail>> extractThumbnails(
      String inputFile, Size size, int totalThumbsCount,
      {int start = 0, int end = 0}) async {
    try {
      final result = await _channel.invokeMethod('extractThumbnails', {
        "inputFile": inputFile,
        "width": size.width,
        "height": size.height,
        "startMs": start,
        "endMs": end,
        "totalThumbsCount": totalThumbsCount,
      });
      if (result != null) {
        return (result as List<dynamic>)
            .map<VideoThumbnail>(
              (e) => VideoThumbnail.fromMap(e),
            )
            .toList();
      }
      return [];
    } on PlatformException catch (e) {
      throw VideoTrimException(e.code, description: e.message);
    }
  }

  static Future<FetchVideoThumbnailnailTask> createFetchVideoThumbnailnailTask(
      String videoFile, OnLatestThumbnailAvailable callback) async {
    final int handle = await _channel.invokeMethod('initVideoThumbsRequest', {
      "videoFile": videoFile,
    });
    return FetchVideoThumbnailnailTask._internal(videoFile, handle, callback);
  }
}
