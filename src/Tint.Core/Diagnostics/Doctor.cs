using Tint.Core.Reload;
using Tint.Core.Service;
using Tint.Core.Util;
using Tint.Core.Wallpapers;

namespace Tint.Core.Diagnostics;

public enum CheckStatus
{
    Ok,
    Info,
    Warning,
    Problem,
}

public sealed record Check(string Name, CheckStatus Status, string Detail);

/// <summary>
/// <c>tint doctor</c>: checks everything tint depends on and says what to fix.
/// </summary>
public static class Doctor
{
    public static IReadOnlyList<Check> Run()
    {
        var checks = new List<Check>
        {
            new("macOS", OperatingSystem.IsMacOS() ? CheckStatus.Ok : CheckStatus.Problem,
                OperatingSystem.IsMacOS() ? Environment.OSVersion.VersionString : "tint runs on macOS only"),
        };

        if (OperatingSystem.IsMacOS())
        {
            checks.Add(Wallpaper());
        }

        checks.Add(ThemeFiles());
        checks.Add(new Check("settings", CheckStatus.Info,
            $"{TintSettings.Load()}{(File.Exists(TintSettings.DefaultPath) ? string.Empty : " (defaults)")}"));
        checks.Add(SketchyBar());
        checks.Add(Borders());
        checks.Add(Ghostty());
        checks.Add(WezTerm());
        checks.Add(Templates());
        checks.Add(Hook());
        if (OperatingSystem.IsMacOS())
        {
            checks.Add(Service());
        }

        if (TintPaths.OnPath("wal"))
        {
            checks.Add(new Check("pywal", CheckStatus.Warning,
                "`wal` is still installed — anything that runs it will overwrite tint's colours. pip3 uninstall pywal once you've switched"));
        }

        return checks;
    }

    private static Check Wallpaper()
    {
        if (!OperatingSystem.IsMacOS())
        {
            return new Check("wallpaper", CheckStatus.Problem, "macOS only");
        }

        using var source = new MacWallpaperSource();
        string? notice = null;
        source.Notice += message => notice = message;
        string? path = source.Current();
        return path is null
            ? new Check("wallpaper", CheckStatus.Problem, notice ?? "couldn't find the current wallpaper")
            : new Check("wallpaper", CheckStatus.Ok, path);
    }

    private static Check ThemeFiles()
    {
        string json = Path.Combine(TintPaths.WalCache, "colors.json");
        if (!File.Exists(json))
        {
            return new Check("theme", CheckStatus.Warning, "no theme yet — run `tint apply`");
        }

        DateTime when = File.GetLastWriteTime(json);
        return new Check("theme", CheckStatus.Ok, $"from {ThemeApplier.LastApplied() ?? "?"}, {when:yyyy-MM-dd HH:mm}");
    }

    private static Check SketchyBar()
    {
        if (!TintPaths.OnPath("sketchybar"))
        {
            return new Check("SketchyBar", CheckStatus.Info, "not installed");
        }

        return Processes.IsRunning("sketchybar")
            ? new Check("SketchyBar", CheckStatus.Ok, "running — reloaded on every apply")
            : new Check("SketchyBar", CheckStatus.Warning, "installed but not running (brew services start sketchybar)");
    }

    private static Check Borders()
    {
        if (!TintPaths.OnPath("borders"))
        {
            return new Check("JankyBorders", CheckStatus.Info, "not installed");
        }

        string how = File.Exists(BordersReloader.DefaultBordersrc)
            ? "re-runs ~/.config/borders/bordersrc"
            : "sets active/inactive colours (no bordersrc)";
        return Processes.IsRunning("borders")
            ? new Check("JankyBorders", CheckStatus.Ok, $"running — {how} on every apply")
            : new Check("JankyBorders", CheckStatus.Warning, "installed but not running (brew services start borders)");
    }

    private static Check Ghostty()
    {
        bool installed = Directory.Exists("/Applications/Ghostty.app") || TintPaths.OnPath("ghostty");
        if (!installed)
        {
            return new Check("Ghostty", CheckStatus.Info, "not installed");
        }

        return new GhosttyReloader().UsesTintTheme()
            ? new Check("Ghostty", CheckStatus.Ok, "uses tint's theme — reloaded on every apply (Ghostty 1.2+)")
            : new Check("Ghostty", CheckStatus.Warning, $"add `config-file = ~/.cache/wal/{GhosttyReloader.ThemeFile}` to its config");
    }

    private static Check WezTerm()
    {
        bool installed = Directory.Exists("/Applications/WezTerm.app") || TintPaths.OnPath("wezterm");
        if (!installed)
        {
            return new Check("WezTerm", CheckStatus.Info, "not installed");
        }

        string home = TintPaths.Home;
        string[] configs = [Path.Combine(home, ".wezterm.lua"), Path.Combine(home, ".config", "wezterm", "wezterm.lua")];
        bool uses = configs.Any(f => File.Exists(f) && File.ReadAllText(f).Contains("colors-wezterm.toml", StringComparison.Ordinal));
        return uses
            ? new Check("WezTerm", CheckStatus.Ok, "uses tint's scheme — reloads itself when it changes")
            : new Check("WezTerm", CheckStatus.Warning, "load ~/.cache/wal/colors-wezterm.toml in wezterm.lua (see the README)");
    }

    private static Check Templates()
    {
        string dir = TintPaths.WalTemplates;
        int count = Directory.Exists(dir) ? Directory.EnumerateFiles(dir).Count() : 0;
        return new Check("templates", CheckStatus.Info, count == 0 ? $"none in {dir}" : $"{count} in {dir}");
    }

    private static Check Hook()
    {
        string hook = Path.Combine(TintPaths.Hooks, "post-apply");
        if (!File.Exists(hook))
        {
            return new Check("hook", CheckStatus.Info, $"none ({hook})");
        }

        bool executable = OperatingSystem.IsWindows() || (File.GetUnixFileMode(hook) & UnixFileMode.UserExecute) != 0;
        return executable
            ? new Check("hook", CheckStatus.Ok, hook)
            : new Check("hook", CheckStatus.Problem, $"{hook} is not executable — chmod +x it");
    }

    private static Check Service()
    {
        ServiceStatus status;
        try
        {
            status = LaunchAgent.Status();
        }
        catch (Exception ex) when (ex is InvalidOperationException or TimeoutException or System.ComponentModel.Win32Exception)
        {
            return new Check("service", CheckStatus.Warning, ex.Message);
        }

        if (!status.Installed)
        {
            return new Check("service", CheckStatus.Info, "not installed — `tint service install` themes on every wallpaper change, from login");
        }

        if (status.ProgramArguments is [string program, ..] && !File.Exists(program))
        {
            return new Check("service", CheckStatus.Problem, $"points at {program}, which is gone — run `tint service install` again");
        }

        return status.Running
            ? new Check("service", CheckStatus.Ok, $"running (pid {status.Pid}), log: {TintPaths.Log}")
            : new Check("service", CheckStatus.Problem, $"installed but not running — see {TintPaths.Log}, then `tint service restart`");
    }
}
