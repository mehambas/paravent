# How Paravent works

## The divider

Paravent adds two items to the menu bar: its own icon and, to its left, the divider. macOS lines up status items from right to left, so every icon left of the divider is the one Paravent tucks away. While the icons are shown, the divider is 16 pt wide and shows a single screen leaf. To tuck the icons away, Paravent clears its image and makes it 10,000 pt wide, which pushes everything left of it off the screen. There is no other API for hiding another app's status item, and Paravent never touches the other apps themselves.

One second after launch Paravent reads the menu bar and collapses the divider if any icon is set to **In Panel** or **Hidden**. On the first launch it places its two items next to the system icons, where a crowded menu bar is least likely to drop them.

## Reading the menu bar

Status items are windows at the status window level. Paravent lists them with `CGWindowListCopyWindowInfo`, keeps those at most 50 pt tall on the menu bar of the display under the pointer, and matches each one with the app's accessibility elements (`AXExtrasMenuBar`) by position. An icon is known by its app's bundle identifier plus its position among that app's icons, or by its window title where macOS names it (Control Center's Wi-Fi, Battery, Focus and so on). The clock and Control Center itself cannot be moved or hidden.

The pictures in the panel and in Settings are screenshots of the icons' windows taken with ScreenCaptureKit, trimmed to their visible pixels. Icons that are off the screen come back blank, so Paravent keeps the last good picture of each icon in `~/Library/Application Support/Paravent/icons`.

## Apply

**Apply** shows the divider, waits until macOS has laid out the bar again, and then repeats one step at a time, at most 80 times:

1. Read the menu bar again.
2. Find the place for the divider that leaves the fewest icons on the wrong side. If it is better than the current one, ⌘-drag the divider there (at most three times).
3. Otherwise ⌘-drag the first icon that is on the wrong side across the divider. An icon that is still on the wrong side after two tries is listed under **Apply** as one that couldn't be moved.

Moving status items is something only the user can do, by dragging them with ⌘ held, so Paravent posts exactly those mouse events and puts the pointer back afterwards. When nothing is left to move, it collapses the divider.

## The panel

Pointing at Paravent's icon opens the panel with the icons set to **In Panel**; it closes 0.35 s after the pointer has left both the icon and the panel. Clicking the icon keeps the panel open until the next click outside it.

Clicking an icon in the panel has to open that app's own menu, and macOS opens it where the icon is. So Paravent shows the divider, waits until the icon is back in the bar, and presses it through accessibility (apps without accessibility elements get a click instead). As long as that app has a menu open, the icons stay out; once it closes, Paravent tucks them away again.

## Settings and files

- `~/Library/Application Support/Paravent/config.json`: the mode of each icon.
- `~/Library/Application Support/Paravent/icons`: the cached icon pictures.
- `~/Library/Application Support/Paravent/log.txt`: a short diagnostic log of scans and moves, with the names of the icons involved. It never leaves the Mac and is cut back at 200 KB.
- `~/Library/Preferences/com.hamzabasaran.paravent.plist`: the positions of Paravent's two items and the update check.

Paravent was called Drawer while it was being written. On its first launch it copies Drawer's folder and settings if it finds them, and leaves Drawer's own files alone.

## Permissions

- **Accessibility** to read the menu bar items, press them and post the ⌘-drags.
- **Screen Recording** to take the pictures of the icons and to read the names of their windows.

Paravent asks for both on the first launch. macOS ties these permissions to the app's signature, which is why every release is signed with the same certificate (see [Development](#development)).

## Updates

Paravent asks GitHub for its latest release 10 seconds after launch and then whenever an hourly tick finds that 24 hours have passed since the last check. The time of the last check is stored, so restarts don't check again, and **Check for updates automatically** in Settings › General turns the check off. The request is `GET https://api.github.com/repos/mehambas/paravent/releases/latest` on an ephemeral URL session without cookies, cache or credentials, with a 15-second timeout. Besides the address it sends only `User-Agent: Paravent/<version>`, `Accept-Language: en` and the standard Accept headers: no identifiers, system details or usage data. Any failure (no published release, offline, timeout, rate limit) counts as no news. Automatic checks stay silent about it; **Check for Updates…** in the menu and **Check Now** in Settings › General always say what they found.

The release's tag (`v0.2.0`) is compared with `CFBundleShortVersionString` number by number, so 0.10.0 is newer than 0.9.0. A newer release puts **Update to 0.2.0…** at the top of the menu that opens when you right-click Paravent's icon, a button at the bottom of the panel, and a row with **Release Notes** and **Download and Install** in Settings › General; the offer is stored until a later check replaces it. **Download and Install** downloads the asset `Paravent.dmg` to the temporary folder and compares its SHA-256 with the asset `Paravent.dmg.sha256`. If the checksum is missing or does not match, the download is deleted and the release page opens in the browser instead. A verified disk image opens in Finder and Paravent quits: it is not notarized, so it cannot replace itself, and Finder won't replace a running app. The user drags the new version to Applications. Progress and errors show in the menu item and the Settings row.

To try the whole flow, serve a release from a local server and start a build with the testing variables:

```sh
PARAVENT_FAKE_VERSION=0.0.1 PARAVENT_UPDATE_BASE=http://127.0.0.1:8000 dist/Paravent.app/Contents/MacOS/Paravent
```

`PARAVENT_FAKE_VERSION` pretends to be another version. `PARAVENT_UPDATE_BASE` replaces `https://api.github.com/repos/mehambas/paravent`, so the server answers `/releases/latest` with GitHub's JSON (`tag_name`, `html_url`, and `assets` whose `browser_download_url`s point back to the server). With either variable set, Paravent checks 10 seconds after launch whatever the last check was, and stores neither the check time nor the offer. Quit the installed Paravent first: two copies would fight over the same divider.

## Development

### Building

```sh
swift test --disable-sandbox
bash scripts/build.sh
open dist/Paravent.app
```

`scripts/build.sh` builds a universal app (Apple silicon and Intel) into `dist/Paravent.app`. An ad hoc signature changes with every build, and macOS then asks for Accessibility and Screen Recording again. `scripts/make-certificate.sh <backup folder>` creates a self-signed “Paravent Self-Signed” certificate in the login keychain, which `build.sh` then uses; `PARAVENT_SIGN_IDENTITY` picks another identity, and `-` forces ad hoc signing. Releases must always be signed with the same certificate. Keep the backup the script writes: builds signed with a new certificate lose the permissions users granted.

### Languages

The app's text is English in the code; `Resources/tr.lproj/Localizable.strings` holds the Turkish translation, and macOS picks the language from the user's preferred languages. After changing any text, `scripts/check-strings.sh` lists the strings the compiler marks as localizable that have no Turkish translation, and translations that are no longer used.

### Visual check and demo

```sh
dist/Paravent.app/Contents/MacOS/Paravent --capture-previews /tmp/paravent-previews -AppleLanguages '(tr)'
scripts/make-demo.sh
```

`--capture-previews` renders the panel and both Settings tabs, with and without an update on offer, in dark and light. `--capture-demo`, which `make-demo.sh` runs, plays a short session on a stand-in menu bar and saves each step as a frame; `make-demo.sh` turns the frames into `docs/images/demo-dark.gif` and `demo-light.gif` with ffmpeg. Both use sample icons only: they don't read, move or capture the real menu bar and read and write no settings.

### Icon

`Resources/Icon` holds the icon sources: the 1024 px artwork, simplified artwork for 16 and 32 px, the layers, the menu bar icon and the divider, and the GitHub social preview. `Resources/AppIcon.icon` is the Icon Composer version, built from the screen and highlight layers with a light and a dark fill; macOS 26 and later derive the tinted and clear styles from it. After changing either, run `scripts/make-icon.sh`: it writes `AppIcon.icns` for macOS 15 and compiles the `.icon` into `Assets.car` (this needs Xcode 26 or later). Both results are committed, so building the app needs neither Xcode nor the script. To check every style without changing System Settings:

```sh
"/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool" Resources/AppIcon.icon \
    --export-image --output-file dark.png --platform macOS --rendition Dark --width 512 --height 512 --scale 1
```

The renditions are `Default`, `Dark`, `TintedLight`, `TintedDark`, `ClearLight` and `ClearDark`. The menu bar icon and the divider are template images, so macOS draws them in the menu bar's own color.

### Releases

```sh
scripts/release.sh 0.2.0
```

The script sets the version and build number in `Resources/Info.plist`, builds and signs with “Paravent Self-Signed”, and writes `dist/Paravent.dmg` and `dist/Paravent.dmg.sha256`. Attach both to a GitHub release tagged `v0.2.0`. The names never change, so `releases/latest/download/Paravent.dmg` always links the newest version, and the update check finds both files.
