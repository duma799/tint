namespace Tint.Core.Util;

/// <summary>Where tint reads and writes, following the XDG base directory conventions.</summary>
public static class TintPaths
{
    private static string Home => Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);

    private static string Xdg(string variable, params string[] fallback)
    {
        string? value = Environment.GetEnvironmentVariable(variable);
        return string.IsNullOrEmpty(value) ? Path.Combine([Home, .. fallback]) : value;
    }

    /// <summary>pywal-compatible output: <c>$XDG_CACHE_HOME/wal</c>, usually <c>~/.cache/wal</c>.</summary>
    public static string WalCache => Path.Combine(Xdg("XDG_CACHE_HOME", ".cache"), "wal");

    /// <summary>pywal user templates: <c>$XDG_CONFIG_HOME/wal/templates</c>.</summary>
    public static string WalTemplates => Path.Combine(Xdg("XDG_CONFIG_HOME", ".config"), "wal", "templates");

    /// <summary>tint's own hooks: <c>$XDG_CONFIG_HOME/tint/hooks</c>.</summary>
    public static string Hooks => Path.Combine(Xdg("XDG_CONFIG_HOME", ".config"), "tint", "hooks");

    /// <summary>True if <paramref name="command"/> is an executable on the PATH.</summary>
    public static bool OnPath(string command) =>
        (Environment.GetEnvironmentVariable("PATH") ?? string.Empty)
            .Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries)
            .Any(dir => File.Exists(Path.Combine(dir, command)));
}
