# tint

Colour themes from your wallpaper, for **macOS**. Written in C#.

Change the wallpaper and tint extracts its palette, builds a readable terminal
colour scheme from it, and writes it where your setup looks for it — the job
pywal does, rebuilt with readable-contrast checks and a watcher that
understands how macOS stores wallpapers, including the built-in ones.

> **Status:** palette extraction, wallpaper watching and `tint apply`
> (pywal-compatible output + templates + a post-apply hook) work. Built-in
> reloads for SketchyBar, JankyBorders and Ghostty are next — see the
> [roadmap](#roadmap).

## Install

Needs the [.NET 10 SDK](https://dotnet.microsoft.com/download): `brew install --cask dotnet-sdk`.

```sh
git clone https://github.com/duma799/tint && cd tint
dotnet pack src/Tint.Cli -c Release -o ./artifacts
dotnet tool install --global --add-source ./artifacts tint     # `update` instead of `install` next time
```

The command lands in `~/.dotnet/tools`; add that to your `PATH`.

## Use

```sh
tint apply                      # theme from the current wallpaper
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
   `colors.css`, `colors-kitty.conf`, `colors-wal.vim`. Anything that already
   reads them keeps working — e.g. SketchyBar configs reading `colors.json`,
   JankyBorders reading `colors.sh`, Neovim with pywal.nvim;
2. renders your pywal templates from `~/.config/wal/templates` (same syntax:
   `{color4}`, `{color4.strip}`, `{{ }}`…);
3. runs `~/.config/tint/hooks/post-apply` if it exists, with `TINT_WALLPAPER`,
   `TINT_MODE` and `TINT_CACHE` set — e.g. `sketchybar --reload` until the
   built-in reloads land.

## How the watching works

Changing the wallpaper rewrites
`~/Library/Application Support/com.apple.wallpaper/Store/Index.plist`. tint
watches that folder, waits until the burst of writes has been quiet for 400 ms,
then checks the wallpaper once and reacts only if it actually changed.

It finds the image in this order:

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
  Tint.Core/         no UI
    Colors/          Rgb, Lab (CIELAB), WCAG contrast
    Palettes/        k-means clustering, PaletteExtractor
    Themes/          SchemeBuilder: palette → 16-colour scheme
    Output/          pywal-compatible files, template renderer
    Reload/          post-apply hook (app reloads to come)
    Imaging/         image loading (+ HEIC via sips)
    Wallpapers/      macOS wallpaper watching and lookup
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

CI builds and tests on macOS for every pull request.

## Roadmap

1. ~~**Core** — palette extraction, macOS wallpaper watching (photos, plist, built-in snapshots)~~
2. **Themes** — ~~scheme with contrast checks, pywal-compatible output,
   templates, `tint apply`, hooks~~; built-in reloads for SketchyBar,
   JankyBorders, Ghostty
3. **Service** — `tint service install` (LaunchAgent), `tint doctor`
4. **Desktop app** — pick a wallpaper, preview, tweak, apply
5. **More** — WezTerm, Zed, VS Code; `tint back`
6. **Releases** — native binary, Homebrew tap, `dotnet tool install -g tint` from NuGet

## License

[GPL-3.0-or-later](LICENSE). You can use, study, change and share tint; if you
distribute a modified version, its source must be available under the same
license.

Images are decoded with [ImageSharp](https://github.com/SixLabors/ImageSharp)
(Six Labors Split License — Apache-2.0 for open-source projects like this one).
