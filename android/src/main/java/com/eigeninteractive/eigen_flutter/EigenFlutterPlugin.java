package com.eigeninteractive.eigen_flutter;

import androidx.annotation.NonNull;
import io.flutter.embedding.engine.plugins.FlutterPlugin;

/**
 * Registers Eigen's Android build-time integration with Flutter.
 *
 * <p>The behavior lives in the library manifest and Gradle dependency graph;
 * no platform channel is required.
 */
public final class EigenFlutterPlugin implements FlutterPlugin {
  @Override
  public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {}

  @Override
  public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {}
}
