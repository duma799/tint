using Tint.Core.Colors;
using Tint.Core.Palettes;
using Tint.Core.Themes;

namespace Tint.Cli;

/// <summary>Terminal output helpers: colour swatches, timestamps, errors.</summary>
internal static class Terminal
{
    /// <summary>
    /// 24-bit colour escapes, unless output is piped or the user opted out
    /// (https://no-color.org).
    /// </summary>
    public static bool UseColor { get; } =
        !Console.IsOutputRedirected && string.IsNullOrEmpty(Environment.GetEnvironmentVariable("NO_COLOR"));

    /// <summary>A block of the given colour, <paramref name="width"/> cells wide.</summary>
    public static string Block(Rgb color, int width = 6) =>
        UseColor ? $"\e[48;2;{color.R};{color.G};{color.B}m{new string(' ', width)}\e[0m" : string.Empty;

    /// <summary>The whole palette as one row of blocks.</summary>
    public static string Strip(Palette palette, int width = 3) =>
        string.Concat(palette.Swatches.Select(s => Block(s.Color, width)));

    /// <summary>A scheme's 16 colours as one row of blocks.</summary>
    public static string Strip(Scheme scheme, int width = 2) =>
        string.Concat(scheme.Colors.Select(c => Block(c, width)));

    public static void Log(string message) => Console.WriteLine($"[{DateTime.Now:HH:mm:ss}] {message}");

    public static int Error(string message)
    {
        Console.Error.WriteLine($"tint: {message}");
        return 1;
    }
}
