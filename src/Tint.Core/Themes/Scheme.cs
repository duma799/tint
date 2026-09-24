using Tint.Core.Colors;

namespace Tint.Core.Themes;

public enum ThemeMode
{
    Dark,
    Light,
}

/// <summary>
/// A terminal colour scheme in pywal's shape: background, foreground, cursor,
/// and 16 colours. 0 is the background, 1–6 red, green, yellow, blue, magenta,
/// cyan, 7 dim foreground, 8 "bright black", 9–14 brighter 1–6, 15 foreground.
/// </summary>
public sealed record Scheme(Rgb Background, Rgb Foreground, Rgb Cursor, IReadOnlyList<Rgb> Colors, ThemeMode Mode)
{
    public Rgb this[int index] => Colors[index];
}
