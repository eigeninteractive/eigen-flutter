# P0

- [ ] Supabase Anonymous Auth
- [ ] Tests
- [x] Plan for backward compatibility — see
      [backward-compatibility.md](./backward-compatibility.md)
  - [ ] Game schema version: `schema` in `games.config` + `game_initial_state`
        stamping; `CASE`/`switch` in `game_apply_action` + `parseObservation`
  - [ ] Decode tolerance: retrofit `@Default` / `@JsonKey(unknownEnumValue:)`
        across shipped + persisted models; analyzer/test guard
  - [ ] Cache discipline: per-provider `destroyKey`, decode-failure = cache-miss
        fallback, `deleteUserData` also clears `PlayerInfoCache`
  - [ ] Version gate: `X-Client-Version` header +
        `min_supported_version`/`soft_min_version` in `app_config` +
        `get_client_requirements` RPC + startup enforcement (Android wired,
        iOS/web stubs)
- [ ] Implement Strategy
- [ ] Implement Bravado
- [ ] App Icon, favicon, OG Image, App Screenshots, Splash Screen

# P1

- [ ] Persisting game history, games, etc. using Drift
- [ ] Persisting ratings, showing ratings UI
- [ ] Replay a game
- [ ] Flag a game or player
- [ ] Quick Match
- [ ] Target web platform, Web App notifications
