namespace Tint.Core.Colors;

/// <summary>
/// A colour in CIELAB (D65). Unlike RGB, straight-line distance here roughly
/// matches how different two colours look to a person, which is what palette
/// clustering needs. <see cref="L"/> is lightness from 0 (black) to 100 (white);
/// <see cref="A"/> runs green→red and <see cref="B"/> blue→yellow.
/// </summary>
public readonly record struct Lab(double L, double A, double B)
{
    // D65 reference white, the white point sRGB is defined against.
    private const double Xn = 0.95047;
    private const double Yn = 1.00000;
    private const double Zn = 1.08883;

    // CIE constants, as exact fractions rather than the rounded 0.008856 / 903.3.
    private const double Epsilon = 216.0 / 24389.0;
    private const double Kappa = 24389.0 / 27.0;

    /// <summary>sRGB byte → linear light. 256 entries, so conversion avoids Math.Pow per pixel.</summary>
    private static readonly double[] LinearLut = BuildLinearLut();

    public static Lab FromRgb(Rgb c)
    {
        double r = LinearLut[c.R];
        double g = LinearLut[c.G];
        double b = LinearLut[c.B];

        // Linear sRGB → CIE XYZ.
        double x = (0.4124564 * r) + (0.3575761 * g) + (0.1804375 * b);
        double y = (0.2126729 * r) + (0.7151522 * g) + (0.0721750 * b);
        double z = (0.0193339 * r) + (0.1191920 * g) + (0.9503041 * b);

        // XYZ → Lab.
        double fx = F(x / Xn);
        double fy = F(y / Yn);
        double fz = F(z / Zn);
        return new Lab((116 * fy) - 16, 500 * (fx - fy), 200 * (fy - fz));
    }

    /// <summary>Back to sRGB. Colours outside the sRGB gamut are clamped.</summary>
    public Rgb ToRgb()
    {
        double fy = (L + 16) / 116;
        double fx = fy + (A / 500);
        double fz = fy - (B / 200);

        double x = Xn * FInverse(fx);
        double y = Yn * FInverse(fy);
        double z = Zn * FInverse(fz);

        double r = (3.2404542 * x) - (1.5371385 * y) - (0.4985314 * z);
        double g = (-0.9692660 * x) + (1.8760108 * y) + (0.0415560 * z);
        double b = (0.0556434 * x) - (0.2040259 * y) + (1.0572252 * z);
        return new Rgb(ToByte(r), ToByte(g), ToByte(b));
    }

    /// <summary>Squared CIE76 ΔE. Cheaper than <see cref="DistanceTo"/> when only comparing.</summary>
    public double DistanceSquared(Lab other)
    {
        double dl = L - other.L;
        double da = A - other.A;
        double db = B - other.B;
        return (dl * dl) + (da * da) + (db * db);
    }

    /// <summary>CIE76 ΔE: about 2.3 is the smallest difference most people notice.</summary>
    public double DistanceTo(Lab other) => Math.Sqrt(DistanceSquared(other));

    /// <summary>Colourfulness: 0 for greys, 30+ for clearly coloured, 100+ for vivid.</summary>
    public double Chroma => Math.Sqrt((A * A) + (B * B));

    /// <summary>Hue angle in degrees, 0..360 (≈40 red, 100 yellow, 136 green, 196 cyan, 306 blue).</summary>
    public double Hue => (Math.Atan2(B, A) * 180 / Math.PI + 360) % 360;

    /// <summary>Builds a colour from lightness, chroma and hue (the LCh form of Lab).</summary>
    public static Lab FromLch(double l, double chroma, double hue)
    {
        double radians = hue * Math.PI / 180;
        return new Lab(l, chroma * Math.Cos(radians), chroma * Math.Sin(radians));
    }

    /// <summary>Same hue, chroma capped at <paramref name="max"/>.</summary>
    public Lab WithMaxChroma(double max)
    {
        double chroma = Chroma;
        return chroma <= max || chroma == 0 ? this : this with { A = A * max / chroma, B = B * max / chroma };
    }

    /// <summary>sRGB byte → linear light (0..1), shared with the contrast maths.</summary>
    internal static double ToLinear(byte channel) => LinearLut[channel];

    private static double F(double t) => t > Epsilon ? Math.Cbrt(t) : ((Kappa * t) + 16) / 116;

    private static double FInverse(double t)
    {
        double t3 = t * t * t;
        return t3 > Epsilon ? t3 : ((116 * t) - 16) / Kappa;
    }

    private static byte ToByte(double linear)
    {
        linear = Math.Clamp(linear, 0, 1);
        double encoded = linear <= 0.0031308 ? 12.92 * linear : (1.055 * Math.Pow(linear, 1 / 2.4)) - 0.055;
        return (byte)Math.Round(Math.Clamp(encoded, 0, 1) * 255);
    }

    private static double[] BuildLinearLut()
    {
        var lut = new double[256];
        for (int i = 0; i < lut.Length; i++)
        {
            double c = i / 255.0;
            lut[i] = c <= 0.04045 ? c / 12.92 : Math.Pow((c + 0.055) / 1.055, 2.4);
        }

        return lut;
    }
}
