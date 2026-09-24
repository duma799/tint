namespace Tint.Core.Util;

/// <summary>Where tint reads and writes. The same paths pywal uses, so existing configs keep working.</summary>
public static class TintPaths
{
    /// <summary>
    /// The home folder. DoNotVerify: without it .NET returns "" for a missing
    /// folder, and every path below would quietly become relative.
    /// </summary>
    public static string Home => Environment.GetFolderPath(Environment.SpecialFolder.UserProfile, Environment.SpecialFolderOption.DoNotVerify);

    /// <summary>pywal-compatible output, <c>~/.cache/wal</c> — what SketchyBar, JankyBorders and Neovim read.</summary>
    public static string WalCache => Path.Combine(Home, ".cache", "wal");

    /// <summary>pywal user templates, <c>~/.config/wal/templates</c>.</summary>
    public static string WalTemplates => Path.Combine(Home, ".config", "wal", "templates");

    /// <summary>tint's own config folder, <c>~/.config/tint</c>.</summary>
    public static string Config => Path.Combine(Home, ".config", "tint");

    /// <summary>tint's own hooks, <c>~/.config/tint/hooks</c>.</summary>
    public static string Hooks => Path.Combine(Config, "hooks");

    /// <summary>Where the login service writes its output, <c>~/Library/Logs/tint.log</c>.</summary>
    public static string Log => Path.Combine(Home, "Library", "Logs", "tint.log");

    /// <summary>True if <paramref name="command"/> is an executable on the PATH.</summary>
    public static bool OnPath(string command) => FindOnPath(command) is not null;

    /// <summary>Full path of <paramref name="command"/> on the PATH, or null.</summary>
    public static string? FindOnPath(string command) =>
        (Environment.GetEnvironmentVariable("PATH") ?? string.Empty)
            .Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries)
            .Select(dir => Path.Combine(dir, command))
            .FirstOrDefault(File.Exists);
}
