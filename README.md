# CompClean

A macOS storage cleaner and complete app uninstaller that explains every file before it touches anything.

Built for macOS 26 (Tahoe) and later with SwiftUI and Liquid Glass.

## Download

**[Download the latest CompClean.dmg](https://github.com/glenlouis8/compclean/releases/latest)** (macOS 26+, Apple silicon)

1. Open the `.dmg` and drag **CompClean** into **Applications**.
2. Open CompClean. macOS will say it *"could not verify CompClean is free of malware"*. This happens because the app isn't signed with a paid Apple Developer account, not because anything was found.
3. Go to **System Settings → Privacy & Security**, scroll down, and click **Open Anyway** next to CompClean. You only have to do this once.
4. Give it **Full Disk Access** when it asks (System Settings → Privacy & Security → Full Disk Access) so it can see every cache and leftover.

Prefer not to run a downloaded app? [Build it yourself](#build-and-run) from the source in this repo instead.

## What it does

**Clean**
- **Cleaner**: app caches, browser caches, old logs and developer caches (Homebrew, npm, Yarn, pip, uv, Xcode DerivedData). It can run automatically, daily or weekly, from the menu bar.
- **Developer junk**: `node_modules`, Python virtual environments, Rust `target`, Swift `.build` and Terraform `.terraform` folders in projects you haven't touched in a while. Also old Xcode archives and device support files.

**Find**
- **Disk map**: a zoomable map of your home folder, sized by space used. It only looks; nothing is removed from here.
- **Leftovers**: files that apps you already deleted left behind in your Library.
- **Big files**: your own large files, sorted by when you last opened them.
- **Duplicates**: byte-for-byte identical files in Desktop, Documents and Downloads.

**Apps**
- **Uninstaller**: removes an app together with its settings, caches, containers, background tasks and helper files, including root-owned ones in `/Library` (after asking for your password).
- **Unused apps**: apps you haven't opened in months, with one click to uninstall.

**History**
- Every clean and uninstall is recorded. Anything still in the Trash can be **put back** to its original place.

## Safety

CompClean is built around a single safety gate, `SafetyPolicy`, which every removal must pass. It works as an **allowlist**: a location is refused unless it's explicitly known to be safe for that kind of removal.

- **Nothing is deleted.** Everything goes to the Trash, and you can put it back from History.
- **macOS and Apple are off-limits.** It never touches system folders, anything named `com.apple…`, Apple-signed apps, or macOS parts with older names (printing, Shortcuts…).
- **Logins and personal data are protected.** Cookies, saved passwords, browser history, bookmarks and site storage, keychains, Mail, Messages, Photos libraries and iCloud Drive are never touched by the cleaner.
- **Symlinks are refused**, and paths are resolved first, so a link can't trick it into a system folder.
- **You review first.** Only caches and logs can be cleaned automatically. Everything else is shown with a plain explanation and a safety label (*Rebuilds itself*, *Leftover*, *Review first*, *Your file*). Your own files are never pre-selected.
- **Some things can't be undone.** Developer tools that clean up after themselves (`xcrun simctl delete unavailable`, `docker system prune`) can't be put back, so the app says so and asks first.

The test suite covers the safety rules and full flows (clean, uninstall, leftovers, developer junk, duplicates, put back). It runs against a fake home folder with a fake Trash, and checks after every flow that protected files are byte-for-byte unchanged.

> **Use at your own risk.** CompClean has been tested carefully, but every Mac is different. Look over what's in the Trash before you empty it.

## Requirements

- macOS 26 or later, on Apple silicon
- Xcode 26 or later (the Command Line Tools alone aren't enough to build the app)

## Build and run

```bash
git clone https://github.com/glenlouis8/compclean.git
cd compclean
./scripts/bundle.sh
open CompClean.app
```

`scripts/bundle.sh` builds a release binary, wraps it into `CompClean.app`, compiles the Liquid Glass icon, and signs the app ad hoc for local use. `scripts/make-dmg.sh` does the same and packs the app into `build/CompClean-<version>.dmg` for a release.

Run the tests:

```bash
swift test
```

Preview what each finder would suggest on your Mac, without moving anything:

```bash
swift run -c release compclean-preview --orphans
```

The other options are `--dev`, `--big`, `--dupes` and `--map`. With no option, it previews the cleaner.

## Permissions

- **Full Disk Access** (System Settings → Privacy & Security → Full Disk Access) lets CompClean see every cache and leftover. Without it, some items stay hidden. Because the app is signed ad hoc, macOS forgets this permission each time you rebuild.
- **Administrator password**: asked only when uninstalling an app that left files in `/Library` or `/Applications` that your user can't move.

## Project layout

```
Sources/CleanerCore/      Safety gate, finders, Trash, history (no UI, fully tested)
Sources/CompClean/        SwiftUI app: screens, menu bar, settings
Sources/compclean-preview Read-only command-line preview
Tests/CleanerCoreTests/   Safety, finder and full-flow tests
Resources/AppIcon.icon    App icon (Icon Composer format)
scripts/                  Build script and icon geometry
```

The icon is drawn from plain geometry in `scripts/icon_glyphs.py` and turned into a Liquid Glass icon with [icon-composer-mcp](https://github.com/ethbak/icon-composer-mcp).

## License

[MIT](LICENSE)
