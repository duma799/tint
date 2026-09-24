using Tint.Core.Colors;

namespace Tint.Core.Palettes;

/// <summary>One palette colour and the share of the image it covers (0..1).</summary>
public sealed record Swatch(Rgb Color, double Share)
{
    public Lab Lab => Color.ToLab();
}

/// <summary>The colours extracted from an image, most common first.</summary>
public sealed record Palette(IReadOnlyList<Swatch> Swatches)
{
    /// <summary>Average lightness weighted by coverage, 0..100. Below ~50 reads as a dark image.</summary>
    public double Lightness => Swatches.Sum(s => s.Lab.L * s.Share);

    public bool IsDark => Lightness < 50;
}
