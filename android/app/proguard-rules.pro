-keep class com.yausername.** { *; }
-keep class org.apache.commons.compress.archivers.zip.** { *; }
# VideoSurfaces reads these by name.
-keepclassmembers class com.alexmercerind.media_kit_video.MediaKitVideoPlugin {
  private com.alexmercerind.media_kit_video.VideoOutputManager videoOutputManager;
}
-keepclassmembers class com.alexmercerind.media_kit_video.VideoOutputManager {
  private final java.util.HashMap videoOutputs;
}
