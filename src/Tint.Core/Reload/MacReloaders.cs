using Tint.Core.Util;

namespace Tint.Core.Reload;

/// <summary>
/// SketchyBar re-runs its <c>sketchybarrc</c> on <c>--reload</c>, so a bar
/// config that reads <c>~/.cache/wal</c> picks up the new colours.
/// </summary>
public sealed class SketchyBarReloader : IReloader
{
    public string Name => "SketchyBar";

    public ReloadResult Reload(ReloadContext context)
    {
        if (!Processes.IsRunning("sketchybar"))
        {
            return new ReloadResult(Name, Ok: true, Skipped: true, "not running");
        }

        return new CommandReloader(Name, "sketchybar", ["--reload"]).Reload(context);
    }
}

/// <summary>
/// JankyBorders. Calling <c>borders</c> with options while it runs updates the
/// running instance, so there's no restart. If there's a
/// <c>~/.config/borders/bordersrc</c> it is run — it usually reads
/// <c>colors.sh</c> and passes the colours on, keeping your own style;
/// otherwise the active border gets blue (color4) and the inactive one color8.
/// </summary>
public sealed class BordersReloader(string? bordersrc = null) : IReloader
{
    private static readonly TimeSpan Timeout = TimeSpan.FromSeconds(10);

    public string Name => "JankyBorders";

    public static string DefaultBordersrc => Path.Combine(
        TintPaths.Home, ".config", "borders", "bordersrc");

    public ReloadResult Reload(ReloadContext context)
    {
        if (!Processes.IsRunning("borders"))
        {
            return new ReloadResult(Name, Ok: true, Skipped: true, "not running");
        }

        string rc = bordersrc ?? DefaultBordersrc;
        if (File.Exists(rc))
        {
            try
            {
                int? exit = Processes.RunDetached(rc, [], Timeout);
                return exit switch
                {
                    0 => new ReloadResult(Name, Ok: true, Skipped: false, "reloaded (ran bordersrc)"),
                    null => new ReloadResult(Name, Ok: false, Skipped: false, "bordersrc still running after 10 s; left it running"),
                    _ => new ReloadResult(Name, Ok: false, Skipped: false, $"bordersrc exited {exit}"),
                };
            }
            catch (Exception ex) when (ex is InvalidOperationException or System.ComponentModel.Win32Exception)
            {
                return new ReloadResult(Name, Ok: false, Skipped: false, $"couldn't run {rc}: {ex.Message} (is it executable?)");
            }
        }

        string active = $"active_color=0xff{context.Scheme[4].Hex[1..]}";
        string inactive = $"inactive_color=0xff{context.Scheme[8].Hex[1..]}";
        return new CommandReloader(Name, "borders", [active, inactive]).Reload(context);
    }
}

/// <summary>
/// Ghostty 1.2+ reloads its config on SIGUSR2. That only changes colours if
/// the config includes tint's theme file, so it checks for that first:
/// <c>config-file = ~/.cache/wal/colors-ghostty</c>.
/// </summary>
public sealed class GhosttyReloader(IReadOnlyList<string>? configFiles = null) : IReloader
{
    public const string ThemeFile = "colors-ghostty";

    public string Name => "Ghostty";

    public static IReadOnlyList<string> DefaultConfigFiles
    {
        get
        {
            string home = TintPaths.Home;
            string xdg = Environment.GetEnvironmentVariable("XDG_CONFIG_HOME") is { Length: > 0 } x ? x : Path.Combine(home, ".config");
            string appSupport = Path.Combine(home, "Library", "Application Support", "com.mitchellh.ghostty");
            return
            [
                Path.Combine(xdg, "ghostty", "config"),
                Path.Combine(xdg, "ghostty", "config.ghostty"),
                Path.Combine(appSupport, "config"),
                Path.Combine(appSupport, "config.ghostty"),
            ];
        }
    }

    /// <summary>True if some Ghostty config mentions tint's theme file.</summary>
    public bool UsesTintTheme() =>
        (configFiles ?? DefaultConfigFiles).Any(f => File.Exists(f) && File.ReadAllText(f).Contains(ThemeFile, StringComparison.Ordinal));

    public ReloadResult Reload(ReloadContext context)
    {
        if (!Processes.IsRunning("ghostty"))
        {
            return new ReloadResult(Name, Ok: true, Skipped: true, "not running");
        }

        if (!UsesTintTheme())
        {
            return new ReloadResult(Name, Ok: true, Skipped: true,
                $"add `config-file = ~/.cache/wal/{ThemeFile}` to your Ghostty config to theme it");
        }

        return new CommandReloader(Name, "pkill", ["-USR2", "-x", "ghostty"]).Reload(context);
    }
}
