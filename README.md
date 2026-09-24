# tint

Colour themes from your wallpaper, for **macOS and Linux**. Written in C#.

Change the wallpaper and tint extracts its palette, then themes your terminal,
editor, bar and window borders to match — the job pywal does, rebuilt with
readable-contrast checks, a built-in wallpaper watcher, and the same behaviour
on both systems.

> **Status: milestone 2 on Linux.** `tint apply` and `tint watch` theme
> kitty, Neovim, Hyprland, Waybar, GTK and anything else that reads pywal's
> files. macOS targets (SketchyBar, JankyBorders, Ghostty) are next — see the
> [roadmap](#roadmap).

## Install

Needs the [.NET 10 SDK](https://dotnet.microsoft.com/download) (`brew install --cask dotnet-sdk` on macOS).

```sh
git clone https://github.com/duma799/tint && cd tint
dotnet pack src/Tint.Cli -c Release -o ./artifacts
dotnet tool install --global --add-source ./artifacts tint     # `update` instead of `install` next time
```

The command lands in `~/.dotnet/tools`; add that to your `PATH`.

## Use

```sh
tint apply                      # theme everything from the current wallpaper
tint apply ~/Pictures/city.jpg  # …or from any image
tint apply --mode light         # light scheme (also: dark, auto)
tint watch                      # re-theme on every wallpaper change
tint palette ~/Pictures/city.jpg
tint wallpaper                  # print the current wallpaper
```

`tint apply` builds a 16-colour scheme from the image — each accent matched to
its terminal role by hue, and every colour checked for readable contrast
against the background (WCAG 4.5:1 for text, 7:1 for the foreground) — then:

1. writes pywal's files to `~/.cache/wal`: `colors.json`, `colors`, `colors.sh`,
   `colors.css`, `colors-waybar.css`, `colors-kitty.conf`, `colors-wal.vim`;
2. renders your pywal templates from `~/.config/wal/templates` (same syntax:
   `{color4}`, `{color4.strip}`, `{{ }}`…);
3. reloads what's running: Hyprland (`hyprctl reload`), kitty (`SIGUSR1`),
   GTK dark/light (`gsettings`), Firefox (`pywalfox update`);
4. runs `~/.config/tint/hooks/post-apply` if it exists, with `TINT_WALLPAPER`,
   `TINT_MODE` and `TINT_CACHE` set — for anything specific to your setup.

## Replacing pywal

Everything that reads `~/.cache/wal` keeps working. For Hyprland + Caelestia
(as in [hyprduma-config](https://github.com/duma799/hyprduma-config)):

```sh
# 1. The setup-specific half of pywal.sh: Caelestia scheme + restart, wal-gtk
mkdir -p ~/.config/tint/hooks
cp examples/hooks/hyprland-caelestia-post-apply ~/.config/tint/hooks/post-apply
chmod +x ~/.config/tint/hooks/post-apply

# 2. Try it next to pywal first
tint apply

# 3. Happy? Stop waypaper calling pywal, start tint with Hyprland instead:
#    ~/.config/waypaper/config.ini   → remove the post_command line
#    ~/.config/hypr/hyprland.conf    → exec-once = tint watch
```

```
  ██████  #402d23   27.5%
  ██████  #281f19   21.6%
  ██████  #12110d   16.3%
  …
  16 colours · dark image (lightness 25)
```

## How the watching works

| System | Signal | Current wallpaper from |
| --- | --- | --- |
| macOS | files under `~/Library/Application Support/com.apple.wallpaper` change | System Events, via `osascript` |
| Linux (Omarchy) | Omarchy re-points `~/.local/state/omarchy/current/background` | where that link points |
| Linux (waypaper) | waypaper rewrites `~/.config/waypaper/config.ini` | that same file |

On Linux, tint uses Omarchy when `~/.local/state/omarchy/current` exists and
waypaper otherwise.

A wallpaper change writes several files in a burst, so events are debounced:
tint waits until things are quiet for 400 ms, then checks the wallpaper once and
reacts only if it actually changed. If the directory to watch doesn't exist,
it falls back to checking every 2 seconds.

On macOS, tint finds the image in this order:

1. **System Events** — works for most photos and pictures.
2. **`Store/Index.plist`** — the picture's file URL, stored inside a nested
   `Configuration` plist.
3. **macOS's rendered snapshot** — for wallpapers with no image file at all,
   like the macOS 26 extension wallpapers (Neptune…). The wallpaper service
   keeps full-size renders in
   `~/Library/Containers/com.apple.wallpaper.agent/…/extension-<provider>/`, and
   tint uses the newest one. No screen recording needed.

The first run may ask for permission for your terminal to control **System
Events** and to **access data from other apps** (the snapshot cache belongs to
the wallpaper service). HEIC images are converted with the system's `sips`.

## Layout

```
src/
  Tint.Core/         no UI: colour maths, palette extraction, wallpaper sources
    Colors/          Rgb, Lab (CIELAB) and conversions
    Palettes/        k-means clustering, PaletteExtractor
    Imaging/         image loading (+ HEIC via sips on macOS)
    Wallpapers/      IWallpaperSource, macOS + waypaper implementations
  Tint.Cli/          the `tint` command
tests/
  Tint.Core.Tests/   xUnit
```

### Palette extraction

The image is shrunk so its long side is at most 256 px, every pixel is
converted to CIELAB — a colour space where distance matches how different
colours *look* — and k-means groups them into 16 clusters. Each cluster's
average is a palette colour, and its size is how much of the image it covers.
Seeding is fixed, so the same image always yields the same palette.

## Development

```sh
dotnet build
dotnet test
dotnet format          # fix formatting; CI runs it with --verify-no-changes
```

CI builds and tests on macOS and Linux for every pull request.

## Roadmap

1. ~~**Core** — palette extraction, wallpaper watching on macOS and Linux~~
2. **Themes** — ~~scheme with contrast checks, pywal-compatible output and
   templates, Linux reloads, `tint apply`~~; macOS: Ghostty, SketchyBar,
   JankyBorders
3. **Service** — `tint service install` (LaunchAgent / systemd user unit), `tint doctor`
4. **Desktop app** — Avalonia: pick a wallpaper, preview, tweak, apply
5. **More** — WezTerm, Zed/VS Code; more Linux wallpaper tools (hyprpaper,
   swww); snapshot built-in macOS wallpapers; `tint back`
6. **Releases** — native binaries, Homebrew tap, `dotnet tool install -g tint` from NuGet

## License

[GPL-3.0-or-later](LICENSE). You can use, study, change and share tint; if you
distribute a modified version, its source must be available under the same
license.

Images are decoded with [ImageSharp](https://github.com/SixLabors/ImageSharp)
(Six Labors Split License — Apache-2.0 for open-source projects like this one).
