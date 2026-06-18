# P0

- [ ] Add thorough docs
- [ ] Implement Strategy
- [ ] Implement Bravado
- [ ] Bot Support
- [ ] Offline App Support with Bot Play
- [ ] Replay Support
- [ ] Spectating Support
- [ ] Persisting game history, games, etc. using Drift
- [ ] Persisting ratings, showing ratings UI
- [ ] App Icon, favicon, OG Image, App Screenshots, Splash Screen

# P1

- [ ] Flag a game or player
- [ ] Quick Match
- [ ] Target web platform, Web App notifications

# Bugs

- [ ] Anonymous users have too long at trial period (90d) - so data loss becomes
      surprising
- [ ] For timed games, if the client submits an action on time, but the latency
      to reach the server causes the server to reject the action, what will
      happen? Can we add some buffer to server check in terms of few ms, will
      that solve this issue?
