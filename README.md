# Make Spotify and other protected video work in Helium (Mac)

Helium doesn't come with **Widevine**, the piece of Google software that streaming sites use to protect their videos. Without it, sites like Spotify, Prime Video, Disney+ and Crunchyroll show an error instead of playing.

> **Netflix won't work, even with this fix.** Netflix only plays in browsers that can prove they're an unmodified, Google-approved build, and Helium can't. Use **Safari** for Netflix. It also gives the best picture quality on a Mac. [More details below.](#why-netflix-doesnt-work)

This guide copies Widevine from Google Chrome into Helium. It takes about 5 minutes. You don't need to know anything about Terminal; you'll copy and paste one line.

---

## Before you start

You need these two things on your Mac:

1. **Helium**, in your **Applications** folder.
   To check: open **Finder**, click **Applications** in the left sidebar, and look for **Helium**. If it's not there, download it from [helium.computer](https://helium.computer), open the downloaded file, and drag Helium into the Applications folder.

2. **Google Chrome**, in your **Applications** folder.
   You won't have to use Chrome. Helium just borrows Widevine from it. If you don't have Chrome, that's fine: the script will open the Chrome download page for you and wait while you install it.

Brave or Microsoft Edge also work instead of Chrome.

---

## Steps

### Step 1. Open Terminal

1. Press **Command (⌘) + Space** on your keyboard. A search bar appears in the middle of the screen.
2. Type **Terminal**.
3. Press **Return**.

A window with plain text opens. That's Terminal.

### Step 2. Copy and paste the command

1. Copy this whole line. On GitHub you can click the copy button at the right side of the box.

   ```
   curl -fsSL https://raw.githubusercontent.com/thepaultucker/Helium-DRM-Widevine-Fix-MacOS/main/helium-widevine-macos.sh -o ~/Downloads/helium-widevine-macos.sh && bash ~/Downloads/helium-widevine-macos.sh --resign
   ```

2. Click inside the Terminal window.
3. Press **Command (⌘) + V** to paste.
4. Press **Return**.

You don't need to close Helium first. The script closes and reopens it for you, and your tabs come back.

### Step 3. Read the message and continue

The script explains what it's about to do, including one trade-off (see [What re-signing means](#what-re-signing-means) below). It then asks:

```
Continue? [Y/n]
```

Press **Return** to continue. (Typing **n** and pressing Return cancels without changing anything.)

### Step 4. Type your Mac password, if asked

The script may say:

```
macOS needs your permission to change Helium.
Type the password you use to log in to this Mac, then press Return.
```

Type the password you use to unlock your Mac, then press **Return**.

**Nothing will appear on screen while you type, not even dots.** That's normal. Just type it and press Return.

### Step 5. Open Helium

When you see **All done!**, press **Return**. Helium opens to a test video page.

If macOS shows a box asking to let Helium use your **Keychain**:

1. Type your Mac password.
2. Click **Always Allow** (not "Allow"). This keeps your saved passwords working in Helium.

### Step 6. Check that it worked

On the test page, a video should start playing. If it does, you're done. Spotify and most other streaming sites should now work in Helium. (Netflix won't; use Safari for it.)

You can close Terminal.

---

## After Helium updates

When Helium updates itself, the fix is undone. To put it back, do **Step 1** and **Step 2** again (same command), then press Return through the prompts.

How you'll know: protected videos stop playing in Helium again.

---

## What re-signing means

Every Mac app carries a digital signature from the company that made it. macOS only lets Helium load add-ons that carry Helium's own signature. Widevine carries Google's, so macOS blocks it.

To get past that, the script replaces Helium's signature with one created on your Mac (this is what the `--resign` part of the command does). That has a few side effects:

- **Keychain prompt.** The first time Helium opens afterwards, macOS asks to let it use your Keychain. Click **Always Allow** so your saved passwords keep working.
- **Passkeys.** Passkeys stored in your Mac's keychain may stop working in Helium.
- **Updates.** Each Helium update removes the fix. Run the command again after updating.
- **Less protection.** Helium loses some of macOS's protection against other programs tampering with it. This only matters if something harmful is already on your Mac.

**Video quality:** Helium gets the most basic version of Widevine, and it can't prove to streaming services that it's a genuine, unmodified browser. Some services respond by lowering the quality, and some refuse to play at all. Safari plays most services in up to 4K on a Mac, so it's the better choice when picture quality matters.

---

## Why Netflix doesn't work

When you start a show, Netflix shows this, even though you're signed in:

```
Pardon the interruption
Your Netflix session has expired. Please sign out and sign in again.
Error Code M7111-1957-205064
```

Signing out and back in, turning off the ad blocker and clearing Netflix's data won't help. The message is misleading: your session is fine. Netflix is refusing to play in Helium.

Chrome includes signature files from Google that let Widevine confirm Chrome hasn't been modified. This check is called **Verified Media Path**. Netflix requires it. Helium can't have those files, because only Google can create them, so Netflix turns it away. Nothing this script does can change that.

**Use Safari for Netflix.** It plays in up to 4K and needs no setup. Chrome works too.

If you'd like Helium to support DRM properly, add a 👍 to [Helium's request for it](https://github.com/imputnet/helium/issues/116). Only Helium's developers can set up the agreements that would make Netflix accept it.

---

## How to undo everything

1. Do **Step 1** above to open Terminal.
2. Paste this line and press **Return**:

   ```
   bash ~/Downloads/helium-widevine-macos.sh --uninstall
   ```

3. Download Helium again from [helium.computer](https://helium.computer), open the downloaded file, and drag Helium into **Applications**. When asked, click **Replace**. This restores Helium's original signature.

Your bookmarks, history and saved passwords aren't affected.

---

## If something goes wrong

| What you see | What to do |
| --- | --- |
| `Helium isn't in your Applications folder` | Install Helium from [helium.computer](https://helium.computer) and drag it into Applications. Then run Step 2 again. |
| `No browser with Widevine was found` | The script opens the Chrome download page. Install Chrome (drag it into Applications), go back to Terminal and press Return. |
| `Helium is still open` | Click on any Helium window, press **Command (⌘) + Q**, go back to Terminal and press Return. |
| `Sorry, try again.` | The password was mistyped. Type it again carefully and press Return. |
| `zsh: command not found` or `no such file` | The line wasn't copied completely. Copy the whole line from Step 2 again, including the start (`curl`) and the end (`--resign`). |
| Netflix says **"Your Netflix session has expired"** (error M7111-1957-205064) when you start a show | Netflix doesn't work in Helium. Use Safari for Netflix. See [Why Netflix doesn't work](#why-netflix-doesnt-work). |
| The test video still shows an error | Quit Helium (**Command (⌘) + Q**) and open it again. If it still fails, run the check below and share the result. |

**Run a check.** Paste this line in Terminal and press **Return**. It changes nothing; it just shows what's installed:

```
bash ~/Downloads/helium-widevine-macos.sh --check
```

Please [open an issue](https://github.com/thepaultucker/Helium-DRM-Widevine-Fix-MacOS/issues) and paste what it shows.

---

## Technical details

For anyone curious why the commonly shared [manual fix](https://gist.github.com/DhananjayPorwal/3633d9f9728b5bdd9d2410272a8139cf) doesn't work on a Mac:

1. **Wrong profile folder.** It copies into `~/Library/Application Support/Helium`. Helium on macOS uses `~/Library/Application Support/net.imput.helium`.
2. **Missing version folder.** Chromium's component installer only scans `WidevineCdm/<version>/`. Copying Chrome's bundled `WidevineCdm/*` drops `manifest.json` and `_platform_specific/` straight into `WidevineCdm/`, where they're ignored.
3. **Invalid copies get deleted.** At startup, any version folder without a valid manifest and a `libwidevinecdm.dylib` for the current chip (`mac_arm64` or `mac_x64`) is deleted. This likely explains [imputnet/helium#2643](https://github.com/imputnet/helium/issues/2643).
4. **Library Validation (the real blocker).** Helium is notarized with hardened runtime under Imput's Team ID (`S4Q33XPHB4`), and the CDM loads in `Helium Helper`. macOS rejects the Google-signed dylib (Team ID `EQHXZ8M8AV`):

   ```
   Library Validation failed: Rejecting '.../libwidevinecdm.dylib' (Team ID: EQHXZ8M8AV)
   for process 'Helium Helper' (Team ID: S4Q33XPHB4), reason: mapping process and
   mapped file (non-platform) have different Team IDs
   ```

   The JavaScript side shows this as `NotSupportedError: CreateCdmFunc not available.` Chrome doesn't hit it because Google signs both Chrome and Widevine. An ad-hoc signature (`codesign --force --deep --sign -`) drops hardened runtime, so library validation no longer applies.

What the script does:

- Finds Helium's profile (`net.imput.helium`) and your Mac's chip type.
- Finds a usable CDM in Chrome's, Brave's or Edge's component folder, or inside `Google Chrome.app`, and skips any that Helium would delete.
- Copies it to `~/Library/Application Support/net.imput.helium/WidevineCdm/<version>/`. With `--resign`, it also copies it to `Helium.app/Contents/Frameworks/Helium Framework.framework/Versions/<version>/Libraries/WidevineCdm/`, which Helium also checks.
- With `--resign`, clears extended attributes and ad-hoc re-signs `Helium.app`.
- Closes Helium before changing anything and reopens it on [Bitmovin's DRM demo](https://bitmovin.com/demos/drm) afterwards.

All options:

| Option | What it does |
| --- | --- |
| `--resign` | Copy Widevine and re-sign Helium. This is what makes video play. |
| *(none)* | Copy Widevine only. Won't play on most Macs because of library validation. |
| `--check` | Show what's installed and what was found. Changes nothing. |
| `--uninstall` | Remove Widevine from Helium's profile and app bundle. |
| `--source DIR` | Use a specific `WidevineCdm` folder as the source. |

Environment overrides: `HELIUM_APP` (default `/Applications/Helium.app`) and `HELIUM_DATA_DIR` (default: auto-detected).
