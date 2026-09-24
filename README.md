# tint

Colour themes from your wallpaper, for **macOS**. Native Swift.

Change the wallpaper and tint extracts its palette, builds a readable terminal
colour scheme from it, writes it where your setup looks for it, and tells your
apps to reload — the job pywal does, rebuilt for the Mac: it understands how
macOS stores wallpapers (built-in ones too), checks every colour for contrast,
and runs quietly at login.

- **Watches the wallpaper**, including the built-in ones that have no image
  file (Neptune…), and themes from each new one.
- **Builds a readable 16-colour scheme**: accents matched to their terminal
  role by hue, every colour checked for contrast (WCAG).
- **Writes pywal's files** to `~/.cache/wal`, so existing configs keep working,
  plus Ghostty, WezTerm and **ApolloShell** themes, and **Zed, VS Code,
  Antigravity and Gemini CLI** themes.
- **Follows macOS dark/light mode** if you like (`--mode system`), re-theming
  the moment macOS switches.
- **Reloads SketchyBar, JankyBorders and Ghostty** itself, then runs your hook.
- **Runs at login** (`tint service install`); `tint doctor` checks the setup.
- **A Mac app**: a window to preview and tweak a scheme, and a menu bar item
  with the current colours and one-click re-theming.

## Install

```sh
brew tap duma799/tint https://github.com/duma799/tint
brew install duma799/tint/tint             # the command (full name: Homebrew has another "tint")
brew install --cask duma799/tint/tint-app  # the app (optional)
tint service install                       # theme on every wallpaper change, from login
tint doctor                                # check everything is wired up
```

One universal build: Apple silicon and Intel, macOS 15 or later.

From source (needs Xcode or its command-line tools):

```sh
git clone https://github.com/duma799/tint && cd tint
swift build -c release
.build/release/tint doctor
swift run TintApp          # the app
```

## Use

```sh
tint apply                      # theme from the current wallpaper
tint apply ~/Pictures/city.jpg  # …or from any image
tint apply city.jpg -w          # …and make it the wallpaper too
tint apply -m light -s 1.2      # light scheme, a bit more colourful
tint apply -m system            # dark or light, following macOS
tint watch                      # re-theme on every wallpaper change (in this terminal)
tint service install            # …the same, in the background from login
tint doctor                     # what's set up, what isn't, what to fix
tint app                        # open the app
tint palette ~/Pictures/city.jpg
tint wallpaper -v               # print the current wallpaper, and how it was found
```

`tint apply` builds a 16-colour scheme from the image, then:

1. writes pywal's files to `~/.cache/wal`: `colors.json`, `colors`, `colors.sh`,
   `colors.css`, `colors-kitty.conf`, `colors-wal.vim` — SketchyBar configs
   reading `colors.json`, JankyBorders reading `colors.sh`, Neovim with
   pywal.nvim all keep working — plus `colors-ghostty` and `colors-wezterm.toml`;
2. renders your pywal templates from `~/.config/wal/templates` (same syntax:
   `{color4}`, `{color4.strip}`, `{{ }}`…);
3. writes an ApolloShell theme and editor themes, for whichever are installed;
4. reloads the apps below, if they're running;
5. runs `~/.config/tint/hooks/post-apply` if it exists, with `TINT_WALLPAPER`,
   `TINT_MODE` and `TINT_CACHE` set — for anything else (editor themes…).

### Apps it themes

| App | How |
|---|---|
| **SketchyBar** | `sketchybar --reload`, which re-runs your `sketchybarrc` |
| **JankyBorders** | runs `~/.config/borders/bordersrc` (it should read `colors.sh`); without one, sets the active border to color4 and the inactive one to color8. Calling `borders` with options updates the running instance — no restart |
| **Ghostty** 1.2+ | sends it `SIGUSR2` (reload config). Add to its config: `config-file = ~/.cache/wal/colors-ghostty` |
| **ApolloShell** | writes `~/Library/Application Support/ApolloShell/themes/tint.css`. Choose **tint** in Nexus → Themes once; ApolloShell re-reads the file on every change |
| **Zed** | writes `~/.config/zed/themes/tint.json` and points your settings' `theme.dark` (or `light`) at **Tint** |
| **VS Code**, **Antigravity** | installs a **Tint** colour theme (a tiny local extension in `~/.vscode/extensions`) and selects it, and puts the same colours in `workbench.colorCustomizations` so they change instantly, no reload. Every other setting is kept; a `settings.json` with comments is left alone, with a note |
| **Gemini CLI** | adds and selects a **Tint** custom theme in `~/.gemini/settings.json` |
| **WezTerm** | nothing to send — it reloads when a watched file changes. In `wezterm.lua`: |

```lua
local tint = wezterm.home_dir .. '/.cache/wal/colors-wezterm.toml'
wezterm.add_to_config_reload_watch_list(tint)
local ok, colors = pcall(wezterm.color.load_scheme, tint)
if ok then config.colors = colors end
```

### Settings

`--mode` (dark, light, auto from the image, or system to follow macOS) and
`--saturation` (0.5–1.5) default to
`~/.config/tint/settings.json`, else dark and 1. The app saves them when you
press Apply, so the login service uses them too.

### The login service

`tint service install` writes `~/Library/LaunchAgents/io.github.duma799.tint.plist`
and starts it: launchd runs `tint watch` now and at every login, and restarts
it if it crashes. It gets your shell's `PATH` (launchd's own has no Homebrew)
and logs to `~/Library/Logs/tint.log`. Also: `tint service status`, `restart`
(after updating tint), `uninstall`.

In **system** mode the watcher also listens for macOS switching between dark
and light (by hand, or by itself at sunset) and re-themes the same wallpaper.

If something else themes from an image first — `tint apply -w`, the app —
the watcher sees the wallpaper is already themed and leaves it.

### The app

The **window** opens on the current wallpaper (or drop in / open any image)
and shows its palette, the 16-colour scheme and a terminal preview — the whole
window takes the scheme's colours. Switch dark/light/auto, turn the saturation
up or down, optionally make the image the wallpaper, and Apply (⌘↩). Click a
colour to copy it. It also shows whether the login service is on, and turns it
on.

The **menu bar item** (a drop) shows the current colours, switches the mode,
and re-themes from the wallpaper in one click.

**Open at login** (in the window or the menu bar) starts tint with your Mac,
as a menu bar item only; open the window from there.

![The tint app](assets/app.png)

## How the wallpaper is found

Changing the wallpaper rewrites
`~/Library/Application Support/com.apple.wallpaper/Store/Index.plist`. tint
watches that folder with FSEvents, waits until the burst of writes has been
quiet for 400 ms, then checks the wallpaper once and reacts only if it
actually changed. It finds the image in this order:

1. **What macOS reports for the screen** (`NSWorkspace`) — photos and pictures,
   per display and per space.
2. **`Store/Index.plist`** — the picture's file URL, stored inside a nested
   `Configuration` plist.
3. **macOS's rendered snapshot** — for wallpapers with no image file at all,
   like the macOS 26 extension wallpapers (Neptune…). The wallpaper service
   keeps full-size renders in
   `~/Library/Containers/com.apple.wallpaper.agent/…/extension-<provider>/`, and
   tint uses the newest one.

No AppleScript and no screen recording. Reading the snapshot cache may make
macOS ask once to let tint **access data from other apps**.

## Layout

```
Sources/
  TintCore/          no UI; builds and is tested on Linux too
    Colors/          Rgb, Lab (CIELAB), WCAG contrast
    Palettes/        k-means clustering, palette extraction
    Imaging/         ImageIO decoding (HEIC included)
    Themes/          SchemeBuilder: palette → readable 16-colour scheme
    Output/          pywal files, templates, Ghostty/WezTerm/ApolloShell themes
    Reload/          SketchyBar, JankyBorders, Ghostty, the hook
    Wallpapers/      FSEvents watcher, wallpaper lookup and setting
    Service/         the launchd agent
    Diagnostics/     tint doctor
  tint/              the command (swift-argument-parser)
  TintApp/           the SwiftUI app: window + menu bar item
Tests/TintCoreTests/ Swift Testing
scripts/
  package.sh         universal release files
  homebrew.sh        the formula and cask for a release
```

### Palette extraction

The image is decoded straight to a thumbnail whose long side is at most
256 px, every pixel is converted to CIELAB — a colour space where distance
matches how different colours *look* — and k-means groups them into 16
clusters. Each cluster's average is a palette colour, and its size is how much
of the image it covers. Seeding is fixed, so the same image always yields the
same palette.

## Development

```sh
swift build
swift test
```

CI builds (warnings as errors) and tests on macOS, and runs the core tests on
Linux, for every pull request. The Release workflow builds the universal Mac
files too (attached to the run). Merging a new version
(`Sources/TintCore/Version.swift`) into main publishes release `vX.Y.Z` and
updates the Homebrew formula and cask.

tint was first written in C# (0.1–0.4); that version is on the
[`csharp`](https://github.com/duma799/tint/tree/csharp) branch, and the last
Linux-supporting one on [`linux-0.2.0`](https://github.com/duma799/tint/tree/linux-0.2.0).

## License

[GPL-3.0-or-later](LICENSE). You can use, study, change and share tint; if you
distribute a modified version, its source must be available under the same
license.
