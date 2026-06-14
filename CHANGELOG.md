# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Extracted Eigen Engine into its own repository from the original monorepo
  (history preserved). Consumed by game apps via a relative path dependency.
- `Branding.madeByCredit` so the settings footer credit is configurable.

### Changed

- **BREAKING**: `EngineConfig.supabaseAnonKey` renamed to
  `supabasePublishableKey`; `Supabase.initialize` now uses `publishableKey:`
  (supabase_flutter 2.14 deprecated `anonKey`).
