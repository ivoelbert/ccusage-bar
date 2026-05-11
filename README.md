# CCUsage Bar

A tiny macOS menu bar app that shows your Claude Code token spending for today, with a popover detailing the last 7 days and your month-to-date total.

Data comes from [`ccusage`](https://github.com/ryoppippi/ccusage) (`bunx ccusage daily --json`).

## Features

- Today's spend live in the menu bar
- Popover with the last 7 days (missing days filled with $0)
- Current-month total
- Right-click for Refresh / Quit, ⌘Q while popover is open
- A passive-aggressive note from "your manager" every time you open it

## Requirements

- macOS 14 (Sonoma) or newer
- [Bun](https://bun.sh) installed (the app looks in `~/.bun/bin`, `/opt/homebrew/bin`, `/usr/local/bin`)
- Xcode (full install, not just Command Line Tools — CLT 6.1 has a SwiftBridging module bug)

## Build

```sh
bash build.sh
```

Output: `build/CCUsage Bar.app`

## Install

```sh
cp -r "build/CCUsage Bar.app" /Applications/
open "/Applications/CCUsage Bar.app"
```

Add to login items via **System Settings → General → Login Items**, or:

```sh
osascript -e 'tell application "System Events" to make login item at end with properties {path:"/Applications/CCUsage Bar.app", hidden:false}'
```

## Uninstall

```sh
pkill -f CCUsageBar
rm -rf "/Applications/CCUsage Bar.app"
```

Then remove from Login Items in System Settings.
