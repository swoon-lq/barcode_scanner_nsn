import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:barcode_scan_nsn/barcode_scan_nsn.dart';

void main() {
  const MethodChannel channel = MethodChannel('nsn.barcode_scan');

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
    expect(await BarcodeScanNsn.platformVersion, '42');
  });
}
