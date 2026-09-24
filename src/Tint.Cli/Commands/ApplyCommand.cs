using System.CommandLine;
using Tint.Core;
using Tint.Core.Reload;
using Tint.Core.Themes;
using Tint.Core.Wallpapers;

namespace Tint.Cli.Commands;

/// <summary><c>tint apply [image]</c> — theme everything from an image (default: the current wallpaper).</summary>
internal static class ApplyCommand
{
    public static Option<string> ModeOption()
    {
        var mode = new Option<string>("--mode", "-m")
        {
            Description = "dark, light, or auto (from the image's brightness).",
            DefaultValueFactory = _ => "dark",
        };
        mode.AcceptOnlyFromAmong("dark", "light", "auto");
        return mode;
    }

    public static ThemeMode? ParseMode(string value) => value switch
    {
        "light" => ThemeMode.Light,
        "auto" => null,
        _ => ThemeMode.Dark,
    };

    public static Command Create()
    {
        var image = new Argument<FileInfo?>("image")
        {
            Description = "Image to theme from. Defaults to the current wallpaper.",
            Arity = ArgumentArity.ZeroOrOne,
        };
        Option<string> mode = ModeOption();
        var noReload = new Option<bool>("--no-reload") { Description = "Only write the files; don't tell apps to reload." };

        var command = new Command("apply", "Generate a colour scheme from an image and apply it everywhere.") { image, mode, noReload };
        command.SetAction(parse =>
        {
            string? path = parse.GetValue(image)?.FullName;
            if (path is null)
            {
                using IWallpaperSource source = WallpaperSources.ForCurrentPlatform();
                path = source.Current();
                if (path is null)
                {
                    return Terminal.Error("no image given and couldn't find the current wallpaper.");
                }
            }

            var options = new ApplyOptions { Mode = ParseMode(parse.GetValue(mode)!), Reload = !parse.GetValue(noReload) };
            return Run(path, options, compact: false) ? 0 : 1;
        });

        return command;
    }

    /// <summary>Applies and prints the outcome. Shared with <c>tint watch</c>.</summary>
    internal static bool Run(string path, ApplyOptions options, bool compact)
    {
        if (!compact)
        {
            // Before applying, so any output from the user's hook comes after it.
            Console.WriteLine($"  {path}");
        }

        ApplyResult result;
        try
        {
            result = ThemeApplier.Apply(path, options);
        }
        catch (Exception ex) when (ex is IOException or NotSupportedException or InvalidOperationException
            or UnauthorizedAccessException or SixLabors.ImageSharp.ImageFormatException)
        {
            Terminal.Error(ex.Message);
            return false;
        }

        Scheme s = result.Scheme;
        string mode = s.Mode == ThemeMode.Dark ? "dark" : "light";
        if (compact)
        {
            Terminal.Log($"applied: {Terminal.Strip(s)}  {mode}, {result.Written.Count} files{ReloadSummary(result.Reloads)}");
        }
        else
        {
            Console.WriteLine($"  {Terminal.Block(s.Background, 2)} background {s.Background.Hex}   {Terminal.Block(s.Foreground, 2)} foreground {s.Foreground.Hex}   ({mode})");
            Console.WriteLine($"  {string.Concat(s.Colors.Take(8).Select(c => Terminal.Block(c, 4)))}");
            Console.WriteLine($"  {string.Concat(s.Colors.Skip(8).Select(c => Terminal.Block(c, 4)))}");
            Console.WriteLine($"  wrote {result.Written.Count} files to {options.CacheDirectory}");
            foreach (ReloadResult r in result.Reloads)
            {
                string mark = r.Skipped ? "·" : r.Ok ? "✓" : "✗";
                Console.WriteLine($"  {mark} {r.Name,-20} {r.Detail}");
            }
        }

        foreach (string warning in result.Warnings)
        {
            Console.Error.WriteLine($"  ! {warning}");
        }

        return result.Reloads.All(r => r.Ok);
    }

    private static string ReloadSummary(IReadOnlyList<ReloadResult> reloads)
    {
        string[] done = [.. reloads.Where(r => r.Ok && !r.Skipped).Select(r => r.Name)];
        string[] failed = [.. reloads.Where(r => !r.Ok).Select(r => $"{r.Name} ✗")];
        string[] all = [.. done, .. failed];
        return all.Length == 0 ? string.Empty : $" → {string.Join(", ", all)}";
    }
}
