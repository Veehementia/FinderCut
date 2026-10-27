# FinderCut

A tiny menu bar app for Apple Silicon Macs that adds **cut & paste for files in Finder**.

- Select files in Finder and press **⌘X**
- Open the destination folder and press **⌘V**: the files are moved, not copied

The menu bar scissors icon fills in while a cut is waiting. Pressing **⌘C** or **Esc** in Finder, or copying anything else, cancels the cut. Renaming files and typing in Finder's search field still use normal text cut and paste.

## How it works

FinderCut watches key presses with a `CGEventTap` (that is why it needs Accessibility access) and only acts while Finder is the frontmost app:

| You press | FinderCut sends | Finder does |
|---|---|---|
| ⌘X | ⌘C, and remembers a cut is pending | copies the file references |
| ⌘V (cut pending) | ⌥⌘V | *Move Item Here* |

Nothing leaves your machine, and the app does nothing outside Finder.

## Install

Requires macOS 13 or later and the Xcode Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/Veehementia/FinderCut.git
cd FinderCut
./scripts/install.sh
```

The script builds the app, copies it to `/Applications`, and opens it. When macOS asks, grant **Accessibility** access in System Settings → Privacy & Security → Accessibility. FinderCut picks up the permission on its own, so you don't need to relaunch it.

Use **Launch at Login** in the menu bar menu to start it automatically.

To build without installing, run `./scripts/build.sh`. The app goes to `build/FinderCut.app`.

### About rebuilding

The app is ad-hoc signed, so every rebuild gets a new signature and macOS drops the Accessibility permission. `install.sh` clears the old entry for you, so you only need to grant access again. If you have an Apple Development certificate, sign with it so the permission survives rebuilds:

```bash
SIGN_IDENTITY="Apple Development: Your Name (TEAMID)" ./scripts/install.sh
```

## Uninstall

Quit FinderCut from its menu, then:

```bash
rm -rf /Applications/FinderCut.app && tccutil reset Accessibility com.matteonardone.FinderCut
```

## License

[MIT](LICENSE)
