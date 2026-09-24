using System.CommandLine;
using Tint.Cli.Commands;

var root = new RootCommand("tint — colour themes from your wallpaper, for macOS.");
root.Subcommands.Add(ApplyCommand.Create());
root.Subcommands.Add(WatchCommand.Create());
root.Subcommands.Add(ServiceCommand.Create());
root.Subcommands.Add(DoctorCommand.Create());
root.Subcommands.Add(AppCommand.Create());
root.Subcommands.Add(PaletteCommand.Create());
root.Subcommands.Add(WallpaperCommand.Create());

return await root.Parse(args).InvokeAsync();
