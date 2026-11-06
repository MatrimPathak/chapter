# flutter_local_notifications stores scheduled notifications with Gson, which
# reads these classes by reflection. Without this, scheduled alerts can fail in
# release builds only.
-keep class com.dexterous.** { *; }
-keepattributes Signature
-keepattributes *Annotation*
-keep class com.google.gson.** { *; }
