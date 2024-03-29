import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_trimmer/video_trimmer.dart';

void main() {
  const MethodChannel channel = MethodChannel('video_trimmer');

  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    channel.setMockMethodCallHandler((MethodCall methodCall) async {
      return '42';
    });
  });

  tearDown(() {
    channel.setMockMethodCallHandler(null);
  });

  test('getPlatformVersion', () async {
    expect(await VideoTrimmer.platformVersion, '42');
  });
}
