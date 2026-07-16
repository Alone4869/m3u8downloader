# Changelog

All notable changes to this project are documented here. Versions follow Semantic Versioning; the `+N` suffix in `pubspec.yaml` is the monotonically increasing Android build number.

## 1.2.8 - 2026-07-16

- Simplify and center the top headers across the home, downloads, and settings pages.

## 1.2.7 - 2026-07-16

- Retry failed downloads in place so the original task changes back to queued and no duplicate task remains.

## 1.2.6 - 2026-07-16

- Add a retry action to the long-press menu for failed downloads.
- Preserve and display the original source page URL alongside the resolved download URL.
- Make task details more compact by removing the duplicated large file-name title.

## 1.2.5 - 2026-07-16

- Simplify X video quality rows so bitrate remains visible without repeating the quality level.
- Use smaller secondary text for resolution and container details.

## 1.2.4 - 2026-07-16

- Remove bitrate-based file-size estimates from X video quality choices.
- Probe the selected final download URL and show its actual file size in the confirmation dialog.

## 1.2.3 - 2026-07-16

- Align the download edit actions directly above navigation and use matching icon buttons for delete and upload.

## 1.2.2 - 2026-07-16

- Keep floating notifications above the liquid-glass bottom navigation.
- Keep download edit actions and the end of task lists clear of the bottom navigation.

## 1.2.1 - 2026-07-16

- Publish separate signed APKs for `arm64-v8a`, `armeabi-v7a`, and `x86_64`.
- Select the matching APK automatically during in-app update checks.
- Fall back to the GitHub Release page instead of downloading an incompatible APK when the device ABI cannot be matched.

## 1.2.0 - 2026-07-16

- Add GitHub Releases update checks and dynamic version information in Settings.
- Add in-app open-source license information.
- Establish the stable Android application ID `io.github.alone4869.m3u8downloader`.
- Add release signing support, CI, and signed APK publishing workflow.
- Document licensing, third-party projects, security, contributions, and releases.
