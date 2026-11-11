# flutter_tesseract_ocr (patched copy)

A copy of [flutter_tesseract_ocr 0.4.31](https://pub.dev/packages/flutter_tesseract_ocr)
(BSD-style licence, see LICENSE). Only `android/build.gradle` is changed: the
published script uses `jcenter()` and AGP 7, which fail under Gradle 9 / AGP 9.
Drop this copy and go back to the pub.dev package once upstream is fixed.
