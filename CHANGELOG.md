# Changelog

All notable changes to Drinkup will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Breaking Changes

- Existing behaviour moved to `Drinkup.Firehose` namespace, to make way for
  alternate sync systems.

### Changed

- Refactor core connection logic for websockets into `Drinkup.Socket` to make it
  easy to use across multiple different services.

## [0.1.0] - 2025-05-26

Initial release.

[unreleased]: https://github.com/cometsh/drinkup/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/cometsh/drinkup/releases/tag/v0.1.0
