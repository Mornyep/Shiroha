<p align="center"><img src="app/Artwork/AppIcon.png" width="128" alt="Shiroha icon"></p>

# 白羽 Shiroha

Your backlog has enough routes. Finding the EXE shouldn't be another one.

[中文](README.md) · English · [日本語](README.ja.md) · [한국어](README.ko.md)

[Download v0.14.0 preview](https://github.com/Mornyep/Shiroha/releases/tag/v0.14.0) · [Report an issue](https://github.com/Mornyep/Shiroha/issues) · [Changelog](CHANGELOG.md)

Shiroha is a native macOS visual novel library and CrossOver launcher. Keep your games, cover art, metadata, launch settings, and manual bookmarks on one shelf. You sat down to read a VN, not spend the evening unlocking the correct folder.

Windows games currently run through your existing CrossOver installation. Work on GalBridge, a possible independent compatibility environment, is still exploratory.

The name comes from Naruse Shiroha, my favorite heroine in *Summer Pockets*. The naming process may have been a little biased.

## What's on the shelf

- **Library:** large covers, search, favorites, and custom collections. Organizing the backlog counts as progress. Sort of.
- **Import and launch:** add an EXE or a game folder, discover Steam games, and save a bottle, executable, and launch arguments for each game.
- **Game details:** look up Steam, Bangumi, and VNDB entries, choose the right match, or edit the details and artwork yourself.
- **Reading notes:** named bookmarks, manually recorded progress, and guide steps with prerequisites. “Save before this choice” finally has somewhere to live outside your memory.
- **Local diagnostics:** inspect EXE and DLL dependencies and read launch logs. Optional AI assistance can explain a summary; you can preview it before sending.
- **Save backups:** select a save folder, back up and verify its files, and restore into a new folder.

Your library stays on your Mac. There are no ads, telemetry, or default cloud sync. The library, launcher, and local diagnostics work without an AI account. Online metadata lookups contact the selected services; optional AI requests send the previewed summary to your configured service.

## Install and start reading

1. Open the [v0.14.0 release](https://github.com/Mornyep/Shiroha/releases/tag/v0.14.0) and download `Shiroha-0.14.0-arm64.zip`. Source code and a SHA-256 checksum file are available on the same page.
2. Extract the ZIP and move `白羽 Shiroha.app` into Applications.
3. Install CrossOver separately and prepare your legally obtained game and its bottle. Shiroha doesn't include games, CrossOver, or Windows components.
4. Open Shiroha, import a game, select its bottle and launch executable, then launch it.

The app requires an Apple Silicon Mac and macOS 14 or later. Only an arm64 package is available; Intel is not currently supported. The documented validation environment is macOS 27.2; macOS 14 and 15 have not been tested on hardware. A game's behavior still depends on its compatibility with CrossOver.

**App language:** these are English instructions. The current app interface is primarily Chinese; this document does not mean that an English UI is available.

The preview uses an ad-hoc signature and is not Apple-notarized. If macOS cannot verify the developer, first confirm that you downloaded it from this repository. After attempting to open it, use System Settings → Privacy & Security → Open Anyway if appropriate. You do not need to disable system protections. If macOS reports malware or a damaged file, stop and verify the download. See [Apple's instructions](https://support.apple.com/en-us/102445).

### Updating or uninstalling

Shiroha was previously called VNLauncher and uses the same local data directory. Quit the old version and keep a backup before updating. Don't run two versions against the same library at once.

To uninstall, quit the app and move it to Trash. This does not delete games, CrossOver bottles, or saves, and does not stop a game that is already running. Library data remains in `~/Library/Application Support/VNLauncher`; back it up before removing it manually. Saved API keys remain in Keychain under the service `local.VNLauncher.advisor`.

## Known limits: no true ending unlocked yet

- Bookmarks and guides are manual. There is no automatic chapter recognition or save/load synchronization.
- Audio, video, input, and saving/loading have not been comprehensively tested across real games. Compatibility is not guaranteed.
- Component installation and rollback, and the complete external Steam library workflow, still need real-world testing.
- Stop the game from writing saves before backing up. Live atomic snapshots are not supported.

## Next up

Work toward 0.15 includes easier CrossOver settings, better Bangumi/VNDB matching, linked favorites, Steam playtime import from JSON, and local timing. Poster color settings are also being simplified: unused wallpaper and disc-art options are being removed, while existing images and shared color extraction remain. These are unreleased candidate features; UI workflows and timing in real games still need verification. The download above remains **v0.14.0**.

Route and save recognition is experimental work with restricted Ren'Py scripts, original sample saves, and limited path analysis. It does not yet provide commercial-game ending recognition, general save support, or live story tracking. GalBridge has no verified standalone commercial-game compatibility list. Missing-component help and per-game compatibility records remain roadmap items; GPTK is being evaluated, and Godot-based native reconstruction is a longer-term exploration. No release date is promised.

## Build from source

The app uses Swift 6, SwiftUI/AppKit, and Swift Package Manager, with no third-party Swift Package dependencies. A full Xcode installation is required. The repository documents Xcode 27.0 / Swift 6.4 as the validated toolchain.

```sh
git clone https://github.com/Mornyep/Shiroha.git
cd Shiroha
# Replace this with your Xcode installation path.
export DEVELOPER_DIR="/path/to/Xcode.app/Contents/Developer"
bash app/scripts/build.sh
bash app/scripts/test.sh
```

The output is `app/build/Shiroha.zip`. The build script generates the icon and applies an ad-hoc signature; it does not provide Developer ID signing or notarization.

## Something went wrong?

Please open an [issue](https://github.com/Mornyep/Shiroha/issues). Include the Shiroha, macOS, and CrossOver versions; your Mac's chip; the game edition; what you tried; what you expected; and what happened. For launch problems, mention whether the same game launches directly in the same CrossOver bottle.

Before sharing logs or screenshots, remove personal paths, account details, keys, and spoilers. Please don't upload game files or entire save folders. A short error message and reproducible steps are a good start. Pull requests are welcome too.

## Thanks and licensing

Thanks to [Bangumi](https://bangumi.tv/), [VNDB](https://vndb.org/), and [Steam](https://store.steampowered.com/) for game information, and [CrossOver](https://www.codeweavers.com/crossover) for the Windows compatibility environment.

Original source code, documentation, and compiled software are available under the [MIT License](LICENSE). See [LICENSE-SCOPE.md](LICENSE-SCOPE.md) and [DEPENDENCIES.md](DEPENDENCIES.md) for scope and third-party attribution.

The unofficial Naruse Shiroha fan-art icon is **excluded from the MIT license**. Character rights belong to their respective holders, and this project has no official affiliation or endorsement. See the [artwork notice](app/Artwork/NOTICE.md). Games, artwork, third-party data, services, and trademarks retain their own rights and terms.
