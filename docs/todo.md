# P0

- [ ] Monetization Flows
- [ ] Replay Support
- [ ] Spectating Support
- [ ] Persisting game history, games, etc. using Drift
- [ ] Persisting ratings, showing ratings UI
- [ ] Add thorough docs and tests

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

- On new pending, compare against old pending (should we?) and send
  notifications and bot wakes
- Given we have moved to EF, do we prefer HMAC or public-private key?
- Lets say I'm playing Poker, and I'm a guest user too stale or I manually
  delete my account, a forfeight signal is fired. The game is still active
  right? After deleting all my details, will the game continue to work for other
  players? Also, how would it look like when someone else replays the game from
  history?
- If I'm playing a game with an anonymous user - what will be shown for add
  friend, etc.? I shouldn't be able to add friend right?
- Replace /internal webook secret with the supabase secret key
- Why do we have a LIMIT 200 in cron_expire_turns? Does it cause any issues?
- How isolated it the contract with supabase as the backend in the engine
  flutter side? If required, can we cleanly swap out to another backend or a DB
  by just touching the repository layer?
