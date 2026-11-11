# Tesseract (text from images) is called from native code by name, so the
# shrinker must leave its classes and fields alone.
-keep class com.googlecode.tesseract.android.** { *; }
-keep class com.googlecode.leptonica.android.** { *; }
