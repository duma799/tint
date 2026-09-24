using System.Globalization;

namespace Tint.Core.Colors;

/// <summary>An sRGB colour with 8 bits per channel — what images and terminals use.</summary>
public readonly record struct Rgb(byte R, byte G, byte B)
{
    /// <summary>Lower-case hex, e.g. <c>#1b2233</c>.</summary>
    public string Hex => $"#{R:x2}{G:x2}{B:x2}";

    /// <summary>Parses <c>#rrggbb</c> or <c>rrggbb</c>.</summary>
    public static Rgb FromHex(string hex)
    {
        ReadOnlySpan<char> s = hex.AsSpan().Trim().TrimStart('#');
        if (s.Length != 6)
        {
            throw new FormatException($"Expected a colour like #rrggbb, got \"{hex}\".");
        }

        return new Rgb(ParseByte(s[..2]), ParseByte(s[2..4]), ParseByte(s[4..]));
    }

    public Lab ToLab() => Lab.FromRgb(this);

    public override string ToString() => Hex;

    private static byte ParseByte(ReadOnlySpan<char> pair) =>
        byte.Parse(pair, NumberStyles.HexNumber, CultureInfo.InvariantCulture);
}
