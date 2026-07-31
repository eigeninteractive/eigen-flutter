@JS()
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

const _assetRoot = 'assets/packages/eigen_flutter/assets/vendor/cropperjs';

Future<void>? _loading;

@JS('Cropper')
external JSFunction? get _cropper;

Future<void> loadImageCropperAssets() async {
  if (_cropper != null) return;

  final existing = _loading;
  if (existing != null) return existing;

  final loading = _loadAssets();
  _loading = loading;

  try {
    await loading;
  } catch (_) {
    _loading = null;
    rethrow;
  }
}

Future<void> _loadAssets() async {
  final head = web.document.head;
  if (head == null) {
    throw StateError('Cannot load Cropper.js before the document head exists.');
  }

  final stylesheet = web.HTMLLinkElement()
    ..rel = 'stylesheet'
    ..href = _assetUrl('cropper.min.css');
  final script = web.HTMLScriptElement()..src = _assetUrl('cropper.min.js');

  await Future.wait([
    _appendAndWait(head, stylesheet, 'Cropper.js stylesheet'),
    _appendAndWait(head, script, 'Cropper.js script'),
  ]);

  if (_cropper == null) {
    throw StateError('Cropper.js loaded without defining Cropper.');
  }
}

String _assetUrl(String fileName) =>
    Uri.parse(web.document.baseURI).resolve('$_assetRoot/$fileName').toString();

Future<void> _appendAndWait(
  web.HTMLHeadElement head,
  web.HTMLElement element,
  String description,
) {
  final completer = Completer<void>();

  element.addEventListener(
    'load',
    (JSAny? _) {
      if (!completer.isCompleted) completer.complete();
    }.toJS,
  );
  element.addEventListener(
    'error',
    (JSAny? _) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('Failed to load $description.'));
      }
    }.toJS,
  );
  head.appendChild(element);

  return completer.future;
}
