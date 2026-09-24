using System.CommandLine;
using Tint.Core;
using Tint.Core.Palettes;
using Tint.Core.Wallpapers;

namespace Tint.Cli.Commands;

/// <summary>
/// <c>tint watch</c> — wait for wallpaper changes and theme everything from
/// each new one. Replaces pywal hooks: no lock files, no sleeps.
/// </summary>
internal static class WatchCommand
{
    // Changes arrive on background threads; applying two at once would let
    // their files and reloads interleave, so they take turns.
    private static readonly Lock ApplyGate = new();

    public static Command Create()
    {
        var verbose = new Option<bool>("--verbose", "-v") { Description = "Show raw file events and fallbacks." };
        var noApply = new Option<bool>("--no-apply") { Description = "Only show each new palette; don't change any themes." };
        Option<string?> mode = ApplyCommand.ModeOption();
        Option<double?> saturation = ApplyCommand.SaturationOption();

        var command = new Command("watch", "Watch for wallpaper changes and apply a theme from each one.") { verbose, noApply, mode, saturation };
        command.SetAction(async (parse, cancellationToken) =>
        {
            bool apply = !parse.GetValue(noApply);

            // Read the saved settings on every change, not once: a mode picked
            // in the desktop app then applies without restarting the service.
            Func<ApplyOptions> options = () => ApplyCommand.Options(parse.GetValue(mode), parse.GetValue(saturation));

            using IWallpaperSource source = WallpaperSources.ForCurrentPlatform();
            if (parse.GetValue(verbose))
            {
                source.Trace += message => Terminal.Log($"  · {message}");
            }

            source.Notice += message => Terminal.Log($"note: {message}");
            source.Changed += (_, e) => OnChanged(e.Path, apply, options);
            source.Start();

            string what = apply ? "applying a theme on each change" : "preview only (--no-apply)";
            Terminal.Log($"watching for wallpaper changes ({source.Name}), {what} — Ctrl+C to stop");
            Terminal.Log($"current: {source.Current() ?? "unknown"}");

            try
            {
                await Task.Delay(Timeout.Infinite, cancellationToken);
            }
            catch (OperationCanceledException)
            {
                Terminal.Log("stopped");
            }

            return 0;
        });

        return command;
    }

    private static void OnChanged(string path, bool apply, Func<ApplyOptions> options)
    {
        Terminal.Log($"wallpaper changed → {path}");
        if (apply)
        {
            lock (ApplyGate)
            {
                // Something else (`tint apply -w`, the desktop app) already
                // themed from this image, maybe with other options: keep that.
                if (ThemeApplier.LastApplied() == Path.GetFullPath(path))
                {
                    Terminal.Log("already themed from it");
                    return;
                }

                ApplyCommand.Run(path, options(), compact: true);
            }

            return;
        }

        try
        {
            Palette palette = PaletteExtractor.FromFile(path);
            string mood = palette.IsDark ? "dark" : "light";
            Terminal.Log($"palette: {Terminal.Strip(palette)}  {palette.Swatches.Count} colours, {mood}");
        }
        catch (Exception ex) when (ex is IOException or NotSupportedException or InvalidOperationException
            or SixLabors.ImageSharp.ImageFormatException)
        {
            Terminal.Log($"couldn't read it: {ex.Message}");
        }
    }
}
