namespace Tint.Core.Util;

/// <summary>Where tint reads and writes. The same paths pywal uses, so existing configs keep working.</summary>
public static class TintPaths
{
    private static string Home => Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);

    /// <summary>pywal-compatible output, <c>~/.cache/wal</c> — what SketchyBar, JankyBorders and Neovim read.</summary>
    public static string WalCache => Path.Combine(Home, ".cache", "wal");

    /// <summary>pywal user templates, <c>~/.config/wal/templates</c>.</summary>
    public static string WalTemplates => Path.Combine(Home, ".config", "wal", "templates");

    /// <summary>tint's own hooks, <c>~/.config/tint/hooks</c>.</summary>
    public static string Hooks => Path.Combine(Home, ".config", "tint", "hooks");

    /// <summary>True if <paramref name="command"/> is an executable on the PATH.</summary>
    public static bool OnPath(string command) =>
        (Environment.GetEnvironmentVariable("PATH") ?? string.Empty)
            .Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries)
            .Any(dir => File.Exists(Path.Combine(dir, command)));
}
