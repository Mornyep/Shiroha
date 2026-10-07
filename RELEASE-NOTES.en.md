# 白羽 Shiroha 0.14.0

[中文](RELEASE-NOTES.md) · [English](RELEASE-NOTES.en.md) · [日本語](RELEASE-NOTES.ja.md) · [한국어](RELEASE-NOTES.ko.md)

[Readme & installation](README.en.md) · [Release notes](RELEASE-NOTES.en.md) · [Next update](UPDATE-PREVIEW.en.md) · [Changelog](CHANGELOG.en.md) · [Help & contributing](README.en.md#help)

The first public preview. Put your VNs on a shelf and launch them through your existing CrossOver installation. The backlog is now organized. Reading it is still up to you.

## What's in this release

- Multiple named bookmarks, manual guide steps, prerequisites, and completion status.
- External Steam library discovery, launch log management, and VNDB Steam App ID lookup.
- Better detail views, long-title handling, and layouts at different window sizes.
- Fixes for backup verification, bookmark migration, stale scan results, and editing conflicts.
- The new “白羽 Shiroha” name and icon, with the existing VNLauncher data directory retained.

## Download

Open the [v0.14.0 release page](https://github.com/Mornyep/Shiroha/releases/tag/v0.14.0).

- `Shiroha-0.14.0-arm64.zip`: the Apple Silicon app.
- `Shiroha-0.14.0-source.zip`: the source snapshot for this release.
- `Shiroha-SHA256SUMS.txt`: SHA-256 checksums for both ZIPs.

Requires macOS 14 or later, plus your own CrossOver installation, games, and bottles. Only an arm64 package is provided. The validation environment was macOS 27.2; Intel and macOS 14/15 were not tested on hardware.

The app uses an ad-hoc signature, without Developer ID signing or Apple notarization. See the [English installation guide](README.en.md#install-and-start-reading). The app UI remains primarily Chinese.

## Known limits

Bookmarks and guides are manual; automatic chapter recognition and save/load synchronization are not supported. Real-game audio, video, input, and saving/loading have not been comprehensively tested. Component installation and rollback, and the full external Steam library workflow, still need real-world testing. Stop save writes before making a backup.

This release passed 88 unit tests, build checks, and signature verification. That does not establish compatibility with every game.

## License

Original source code, documentation, and compiled software use the [MIT License](LICENSE). The unofficial Naruse Shiroha fan-art icon is excluded from MIT; character rights belong to their respective holders, and the project has no official affiliation. See the [license scope](LICENSE-SCOPE.md) and [artwork notice](app/Artwork/NOTICE.md).

Release assets and the v0.14.0 tag retain this version's snapshot. Documentation on main continues to evolve. `RELEASE-FILES.json` records the source attachment's files and hashes, not the current contents of main.

