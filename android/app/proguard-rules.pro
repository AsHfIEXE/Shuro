# Shuro release keep rules.
#
# shared_preferences_android reaches its Kotlin through package:jni
# reflective method lookups (descriptors like
# getAll(String, List, Continuation)). R8 cannot see those call sites,
# so minified builds must keep the entire plugin package or the calls
# fail at runtime with NoSuchMethodError.
-keep class io.flutter.plugins.sharedpreferences.** { *; }
# package:jni's own lookup machinery.
-keep class com.github.dart_lang.jni.** { *; }
