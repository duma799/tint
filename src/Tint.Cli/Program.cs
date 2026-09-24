using System.CommandLine;
using Tint.Cli.Commands;

var root = new RootCommand("tint — colour themes from your wallpaper, for macOS and Linux.");
root.Subcommands.Add(PaletteCommand.Create());
root.Subcommands.Add(WallpaperCommand.Create());
root.Subcommands.Add(WatchCommand.Create());

return await root.Parse(args).InvokeAsync();
