import 'package:flutter_test/flutter_test.dart';
import 'package:mawjtvh/core/ui_zoom.dart';

void main() {
  test('zoom steps move one notch and stop at the ends', () {
    expect(stepUiScale(1.2, 1), 1.3);
    expect(stepUiScale(1.2, -1), 1.1);
    expect(stepUiScale(1.0, -1), 1.0);
    expect(stepUiScale(1.8, 1), 1.8);
  });

  test('a chosen scale wins over the automatic one', () {
    expect(effectiveUiScale(1.45), 1.45);
    expect(effectiveUiScale(9), 2.2);
  });
}
