import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mawjtvh/core/bidi.dart';

void main() {
  test('detects the base direction of a string', () {
    expect(bidiDirectionOf('مرحبا بالعالم'), TextDirection.rtl);
    expect(bidiDirectionOf('Hello world'), TextDirection.ltr);
    expect(bidiDirectionOf('1234'), TextDirection.ltr);
    expect(bidiDirectionOf(''), TextDirection.ltr);
    expect(bidiDirectionOf('Hello مرحبا'), TextDirection.ltr);
    expect(bidiDirectionOf('مرحبا Hello'), TextDirection.rtl);
  });

  test('wraps text in a first-strong isolate', () {
    final isolated = bidiIsolate('مرحبا');
    expect(isolated.startsWith(kFirstStrongIsolate), isTrue);
    expect(isolated.endsWith(kPopDirectionalIsolate), isTrue);
    expect(isolated.contains('مرحبا'), isTrue);
  });
}
