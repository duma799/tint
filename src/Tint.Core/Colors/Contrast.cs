namespace Tint.Core.Colors;

/// <summary>
/// WCAG 2 contrast. 4.5 is the minimum for normal text to be comfortably
/// readable, 3 for large text and UI borders, 7 for "enhanced".
/// </summary>
public static class Contrast
{
    public const double Text = 4.5;
    public const double Large = 3.0;
    public const double Enhanced = 7.0;

    /// <summary>Relative luminance, 0 (black) to 1 (white).</summary>
    public static double Luminance(Rgb c) =>
        (0.2126 * Lab.ToLinear(c.R)) + (0.7152 * Lab.ToLinear(c.G)) + (0.0722 * Lab.ToLinear(c.B));

    /// <summary>Contrast ratio between two colours, 1 (identical) to 21 (black on white).</summary>
    public static double Ratio(Rgb a, Rgb b)
    {
        double la = Luminance(a);
        double lb = Luminance(b);
        return (Math.Max(la, lb) + 0.05) / (Math.Min(la, lb) + 0.05);
    }
}
