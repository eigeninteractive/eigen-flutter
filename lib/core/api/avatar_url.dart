/// Resolves a stored `avatarUrl` into something an image widget can load.
///
/// The server stores either an absolute URL (when the avatars bucket has a
/// public base - a custom domain or r2.dev, so reads never touch the worker) or
/// a relative `/avatars/{uid}?v={ts}` path pointing at the worker's own serving
/// route. Which one it is depends on deployment configuration the client is not
/// told about, so every avatar URL must be run through here before use - not
/// only after an upload. The same stored value comes back on every `Player`.
///
/// [Uri.resolve] does the work: it is RFC 3986 reference resolution, so an
/// already-absolute URL passes through untouched, a leading slash is optional,
/// and the query survives. Hand-rolled string joining gets at least one of
/// those wrong. (`package:path` is for filesystem paths and would be incorrect
/// here - it even says so.)
///
/// The `?v=` component is a cache-buster the server bumps on each upload: the
/// R2 key is the uid alone and is overwritten in place, so without the changing
/// query both the device's image cache and any CDN would keep serving the old
/// picture.
///
/// Returns null for a user with no avatar, which callers render as their
/// placeholder or initials.
String? resolveAvatarUrl(String? avatarUrl, String apiBaseUrl) {
  if (avatarUrl == null || avatarUrl.isEmpty) return null;
  return Uri.parse(apiBaseUrl).resolve(avatarUrl).toString();
}
