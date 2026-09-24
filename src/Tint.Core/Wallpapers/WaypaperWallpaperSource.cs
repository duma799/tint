namespace Tint.Core.Wallpapers;

/// <summary>
/// Linux with waypaper (the picker in hyprduma-config). waypaper records the
/// wallpaper it sets in <c>~/.config/waypaper/config.ini</c>, so watching that
/// file replaces the old waypaper-hook.sh.
/// </summary>
public sealed class WaypaperWallpaperSource(string? configPath = null, TimeProvider? timeProvider = null)
    : WatchedWallpaperSource(timeProvider)
{
    private static readonly string Home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);

    private readonly string _configPath = configPath ?? Path.Combine(Home, ".config", "waypaper", "config.ini");

    public override string Name => "waypaper";

    /// <summary>waypaper's config folder — present when waypaper is installed and has run.</summary>
    public static string DefaultConfigDirectory =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".config", "waypaper");

    protected override string? StampPath => _configPath;

    protected override string WatchDirectory => Path.GetDirectoryName(_configPath)!;

    // Editors and waypaper itself often write a temp file then rename it over
    // config.ini, so watch the whole folder rather than the one file.
    protected override string WatchFilter => "*";

    public override string? Current() =>
        File.Exists(_configPath) ? ParseWallpaper(File.ReadAllText(_configPath), Home) : null;

    /// <summary>
    /// Pulls the <c>wallpaper = …</c> value out of waypaper's config. With several
    /// monitors it is a comma-separated list; the first one wins.
    /// </summary>
    internal static string? ParseWallpaper(string ini, string home)
    {
        foreach (string rawLine in ini.Split('\n'))
        {
            string line = rawLine.Trim();
            int equals = line.IndexOf('=');
            if (equals < 0 || !line[..equals].Trim().Equals("wallpaper", StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            string value = line[(equals + 1)..].Split(',')[0].Trim();
            if (value.Length == 0)
            {
                return null;
            }

            return value.StartsWith('~') ? home + value[1..] : value;
        }

        return null;
    }
}
