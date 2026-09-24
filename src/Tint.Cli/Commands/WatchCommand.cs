using System.CommandLine;
using Tint.Core.Palettes;
using Tint.Core.Wallpapers;

namespace Tint.Cli.Commands;

/// <summary>
/// <c>tint watch</c> — wait for wallpaper changes and extract each new palette.
/// Applying themes to apps comes in milestone 2; for now this proves the
/// watching works on each OS.
/// </summary>
internal static class WatchCommand
{
    public static Command Create()
    {
        var verbose = new Option<bool>("--verbose", "-v") { Description = "Show raw file events and fallbacks." };

        var command = new Command("watch", "Watch for wallpaper changes and extract each new palette.") { verbose };
        command.SetAction(async (parse, cancellationToken) =>
        {
            using IWallpaperSource source = WallpaperSources.ForCurrentPlatform();
            if (parse.GetValue(verbose))
            {
                source.Trace += message => Terminal.Log($"  · {message}");
            }

            source.Notice += message => Terminal.Log($"note: {message}");
            source.Changed += (_, e) => OnChanged(e.Path);
            source.Start();

            Terminal.Log($"watching for wallpaper changes ({source.Name}) — Ctrl+C to stop");
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

    private static void OnChanged(string path)
    {
        Terminal.Log($"wallpaper changed → {path}");
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
