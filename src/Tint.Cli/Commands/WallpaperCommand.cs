using System.CommandLine;
using Tint.Core.Wallpapers;

namespace Tint.Cli.Commands;

/// <summary><c>tint wallpaper</c> — print the current wallpaper's path.</summary>
internal static class WallpaperCommand
{
    public static Command Create()
    {
        var command = new Command("wallpaper", "Print the path of the current wallpaper.");
        command.SetAction(_ =>
        {
            using IWallpaperSource source = WallpaperSources.ForCurrentPlatform();
            source.Trace += message => Console.Error.WriteLine($"  ({message})");

            string? path = source.Current();
            if (path is null)
            {
                return Terminal.Error($"couldn't find the current wallpaper ({source.Name}).");
            }

            Console.WriteLine(path);
            return 0;
        });

        return command;
    }
}
