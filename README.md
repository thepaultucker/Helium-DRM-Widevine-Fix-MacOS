# Helium Widevine fix for macOS

Helium is built from ungoogled-chromium and doesn't come with Google's Widevine CDM, so Netflix, Spotify, Prime Video, Crunchyroll and similar sites won't play. Helium's code is still set up to load Widevine if it's already on disk. This script copies the CDM from a browser that has it (Chrome, Brave or Edge) into the place Helium checks.

## Quick start

```bash
# 1. Install Google Chrome, open it once, then quit it.
# 2. Open Helium once, then quit it completely (Cmd+Q).
# 3. Run:
curl -fsSLO https://raw.githubusercontent.com/thepaultucker/Helium-DRM-Widevine-Fix-MacOS/main/helium-widevine-macos.sh
chmod +x helium-widevine-macos.sh
./helium-widevine-macos.sh
```

Next, open Helium and go to `helium://components`. **Widevine Content Decryption Module** should list a real version number, not `0.0.0.0`. Test playback at <https://bitmovin.com/demos/drm>.

Other commands:

| Command | What it does |
| --- | --- |
| `./helium-widevine-macos.sh --check` | Shows what is installed and which sources it found. Changes nothing. |
| `./helium-widevine-macos.sh --source "/path/to/WidevineCdm"` | Uses a specific CDM folder as the source. |
| `./helium-widevine-macos.sh --uninstall` | Removes Widevine from Helium. |

No `sudo` is needed. The script never modifies or re-signs `Helium.app`.

## Why the popular gist doesn't work on macOS

The [manual fix gist](https://gist.github.com/DhananjayPorwal/3633d9f9728b5bdd9d2410272a8139cf) works on Linux and Windows. Its macOS steps fail for these reasons:

1. **Wrong folder.** It copies into `~/Library/Application Support/Helium`. Helium on macOS keeps its profile in `~/Library/Application Support/net.imput.helium` (set in helium-macos's `change-product-dir-name.patch`), so Helium never looks in the folder the gist uses.

2. **Missing version folder.** Chromium's component installer only scans `WidevineCdm/<version>/` (for example `WidevineCdm/4.10.2891.0/manifest.json`). Chrome's app bundle stores the CDM *without* a version folder, so `cp -r ".../Libraries/WidevineCdm/"* ...` drops `manifest.json` and `_platform_specific` straight into `WidevineCdm/`, and they get ignored. The script reads the version from `manifest.json` and builds the correct folder.

3. **Helium deletes copies it can't use.** On startup the component installer checks each version folder. It needs a readable manifest the browser accepts, plus `_platform_specific/mac_arm64/libwidevinecdm.dylib` (or `mac_x64` on Intel). Any folder that fails is **deleted**. This is likely the cause of [imputnet/helium#2643](https://github.com/imputnet/helium/issues/2643) ("WidevineCdm files keep getting deleted", macOS only). A typical case is copying an Intel-only CDM onto an Apple Silicon Mac. The script checks each source before copying and skips any that would be deleted.

4. **Copying while Helium is running.** Helium only registers components at launch, so the script won't run until Helium is fully quit.

## Why the script doesn't re-sign Helium.app

Some tools copy Widevine *into* `Helium.app` and then run `codesign --force --deep --sign -` on the whole app. That's unnecessary for two reasons. First, Helium is built without `bundle_widevine_cdm`, so it doesn't look for a CDM inside the app bundle. Second, an ad-hoc re-sign removes Helium's notarized signature and entitlements, which can break Keychain access, passkeys, and Gatekeeper trust. The profile folder is the supported location, and it doesn't touch the app at all.

## Things to know

- **Quality is capped.** Helium isn't a Google-licensed Widevine partner, so you get software-only Widevine L3 without a verified host. Expect lower resolution on Netflix and some services may still refuse to play. General-purpose sites (Spotify, YouTube Movies, most demo players) usually work.
- **No auto-updates.** On `helium://components`, Widevine may show "update error" or "Component updates are disabled". That's expected. When Chrome gets a newer CDM, run the script again.
- **Protected content setting.** If a site still won't play, check that `helium://settings/content/protectedContent` allows it.
- **Helium updates.** A new Helium version may require a newer CDM than the one you copied. If Widevine disappears after an update, open Chrome so it updates its CDM, then run the script again.

## Troubleshooting

Run `./helium-widevine-macos.sh --check` first. It shows:

- which Helium profile folder it found (`net.imput.helium`),
- whether the installed CDM is valid for your Mac's architecture,
- which source browsers have a usable CDM.

If no source is found, open Chrome and play something at <https://bitmovin.com/demos/drm>. That makes Chrome download its own CDM into `~/Library/Application Support/Google/Chrome/WidevineCdm/`. Then run the script again.
