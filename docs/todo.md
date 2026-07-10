# P0

- [ ] Monetization Flows
- [ ] Replay Support
- [ ] Spectating Support
- [ ] Persisting game history, games, etc. using Drift
- [ ] Persisting ratings, showing ratings UI
- [ ] Add thorough docs and tests
- [ ] Twin-drift tests: shared JSON fixtures per version unit (obs, pending,
      action, playerIndex, config → expected) consumed by both the TS and Dart
      rules tests, so Dart/TS twin drift fails CI instead of degrading UX

# App Implementations

- [ ] Implement Strategy
- [ ] Implement Bravado
- [ ] App Icon, favicon, OG Image, App Screenshots, Splash Screen

# P1

- [ ] Offline App Support with Bot Play
- [ ] Flag a game or player
- [ ] Quick Match
- [ ] Target web platform, Web App notifications

# Migration Tasks

- Per game object needed in Dart or Typescript?
- If I'm playing a game with an anonymous user - what will be shown for add
  friend, etc.? I shouldn't be able to add friend right?
- How isolated it the contract with supabase as the backend in the engine
  flutter side? If required, can we cleanly swap out to another backend or a DB
  by just touching the repository layer?
