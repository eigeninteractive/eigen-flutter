# P0

- [ ] Add thorough docs
- [ ] Monetization Flows
- [ ] Replay Support
- [ ] Spectating Support
- [ ] Persisting game history, games, etc. using Drift
- [ ] Persisting ratings, showing ratings UI

# App Implementations

- [ ] Implement Strategy
- [ ] Implement Bravado
- [ ] App Icon, favicon, OG Image, App Screenshots, Splash Screen

# P1

- [ ] Offline App Support with Bot Play
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
- [ ] How to show bots distinctly in the UI?
- [ ] Instead of pre warming all in app startup splash screen which can make the
      app feel slow, can we prewarm some in home screen or new screen after the
      app launches?
- [ ] What about bot support or availability based on the game config?
- [ ] Reduce the bot.md doc, its references, etc. into engine_architecture.md
