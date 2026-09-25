# Protobuf Lite resolves generated message fields by their original names at
# runtime. R8 otherwise renames/removes those fields in minified release builds,
# which prevents MediaPipe from initializing (for example, SystemInfo.platform_).
-keep class * extends com.google.protobuf.GeneratedMessageLite { *; }

# MediaPipe's native runtime looks up framework classes, callbacks, and members
# by their Java names. Keep that JNI/reflection boundary intact in release builds.
-keep class com.google.mediapipe.** { *; }

# FluentLogger discovers its enclosing class from the runtime stack. Preserve
# only that entry point from R8 renaming/inlining; all other Flogger code can
# still be shrunk and optimized.
-keep,allowshrinking class com.google.common.flogger.FluentLogger {
    public static com.google.common.flogger.FluentLogger forEnclosingClass();
}
-keep,allowshrinking class com.google.common.flogger.backend.system.StackBasedCallerFinder { *; }

# These protobuf types are referenced by optional MediaPipe graph profiling and
# graph-template APIs, but are not packaged by the Tasks Vision Android artifact.
-dontwarn com.google.mediapipe.proto.CalculatorProfileProto$CalculatorProfile
-dontwarn com.google.mediapipe.proto.GraphTemplateProto$CalculatorGraphTemplate

# ONNX Runtime resolves these result types from native code through JNI. Keep
# only the JNI boundary instead of the entire Java package.
-keep class ai.onnxruntime.MapInfo { *; }
-keep class ai.onnxruntime.NodeInfo { *; }
-keep class ai.onnxruntime.OnnxMap { *; }
-keep class ai.onnxruntime.OnnxModelMetadata { *; }
-keep class ai.onnxruntime.OnnxSequence { *; }
-keep class ai.onnxruntime.OnnxSparseTensor { *; }
-keep class ai.onnxruntime.OnnxTensor { *; }
-keep class ai.onnxruntime.OnnxValue { *; }
-keep class ai.onnxruntime.OrtException { *; }
-keep class ai.onnxruntime.SequenceInfo { *; }
-keep class ai.onnxruntime.TensorInfo { *; }
-keep class ai.onnxruntime.ValueInfo { *; }
