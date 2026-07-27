/// Reloads the current browser document.
///
/// The production gateway calls this only when compiled for the web.
void reloadBrowser() {
  throw UnsupportedError('Browser reload is unavailable on this platform.');
}
