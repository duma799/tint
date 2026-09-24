using System.CommandLine;
using Tint.Core.Wallpapers;

namespace Tint.Cli.Commands;

/// <summary><c>tint wallpaper</c> — print the current wallpaper's path.</summary>
internal static class WallpaperCommand
{
    public static Command Create()
    {
        var verbose = new Option<bool>("--verbose", "-v") { Description = "Show how the wallpaper was found." };

        var command = new Command("wallpaper", "Print the path of the current wallpaper.") { verbose };
        command.SetAction(parse =>
        {
            using IWallpaperSource source = WallpaperSources.ForCurrentPlatform();
            if (parse.GetValue(verbose))
            {
                source.Trace += message => Console.Error.WriteLine($"  · {message}");
            }

            string? notice = null;
            source.Notice += message => notice = message;

            string? path = source.Current();
            if (path is null)
            {
                return Terminal.Error(notice ?? $"couldn't find the current wallpaper ({source.Name}).");
            }

            Console.WriteLine(path);
            return 0;
        });

        return command;
    }
}
