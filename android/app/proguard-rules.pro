# Keep ML Kit text recognizer options
-keep class com.google.mlkit.vision.text.** { *; }
-keep class com.google.mlkit.vision.common.** { *; }
# Keep TFLite GPU delegate classes used by mlkit plugin
-keep class org.tensorflow.lite.gpu.** { *; }
