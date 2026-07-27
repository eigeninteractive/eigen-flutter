import 'package:web/web.dart' as web;

/// Reloads the current browser document from its existing URL.
void reloadBrowser() => web.window.location.reload();
