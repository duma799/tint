using Tint.Core.Colors;
using Tint.Core.Palettes;
using Tint.Core.Themes;

namespace Tint.Core.Tests;

public class SchemeTests
{
    /// <summary>A wallpaper-like palette: dark blues and greys with a few accents, most common first.</summary>
    private static readonly Palette Night = FromHex(
        "#1b2233", "#2a3450", "#48596f", "#606b7e", "#8f8e9a", "#c68a65", "#d8f4ff", "#6d9c5a", "#b8455a", "#c9b46a");

    public static TheoryData<ThemeMode> Modes => new() { ThemeMode.Dark, ThemeMode.Light };

    [Theory]
    [MemberData(nameof(Modes))]
    public void Has_pywal_shape(ThemeMode mode)
    {
        Scheme s = SchemeBuilder.Build(Night, mode);

        Assert.Equal(16, s.Colors.Count);
        Assert.Equal(s.Background, s[0]);
        Assert.Equal(s.Foreground, s[15]);
        Assert.Equal(s.Foreground, s.Cursor);
        Assert.Equal(mode, s.Mode);
    }

    [Fact]
    public void Dark_scheme_has_a_dark_background_and_light_text()
    {
        Scheme s = SchemeBuilder.Build(Night, ThemeMode.Dark);

        Assert.True(Contrast.Luminance(s.Background) < 0.05);
        Assert.True(Contrast.Luminance(s.Foreground) > Contrast.Luminance(s.Background));
    }

    [Fact]
    public void Light_scheme_has_a_light_background_and_dark_text()
    {
        Scheme s = SchemeBuilder.Build(Night, ThemeMode.Light);

        Assert.True(Contrast.Luminance(s.Background) > 0.7);
        Assert.True(Contrast.Luminance(s.Foreground) < Contrast.Luminance(s.Background));
    }

    [Theory]
    [MemberData(nameof(Modes))]
    public void Every_colour_is_readable_on_the_background(ThemeMode mode)
    {
        Scheme s = SchemeBuilder.Build(Night, mode);

        Assert.True(Contrast.Ratio(s.Foreground, s.Background) >= Contrast.Enhanced);
        foreach (int i in new[] { 1, 2, 3, 4, 5, 6, 7, 9, 10, 11, 12, 13, 14 })
        {
            Assert.True(Contrast.Ratio(s[i], s.Background) >= Contrast.Text, $"color{i} {s[i]} on {s.Background}");
        }

        Assert.True(Contrast.Ratio(s[8], s.Background) >= Contrast.Large);
    }

    [Fact]
    public void Accents_land_in_the_slot_their_hue_belongs_to()
    {
        // Deliberately shuffled; each should find its ANSI slot anyway.
        Palette palette = FromHex("#101418", "#3a6ee0", "#e0c040", "#c03a3a", "#40b0c8", "#b048b0", "#48a848", "#e8e8e8");

        Scheme s = SchemeBuilder.Build(palette, ThemeMode.Dark);

        Assert.InRange(HueDistance(s[1], 30), 0, 35); // red
        Assert.InRange(HueDistance(s[2], 135), 0, 35); // green
        Assert.InRange(HueDistance(s[3], 95), 0, 35); // yellow
        Assert.InRange(HueDistance(s[4], 280), 0, 40); // blue
        Assert.InRange(HueDistance(s[5], 330), 0, 40); // magenta
        Assert.InRange(HueDistance(s[6], 200), 0, 35); // cyan
    }

    [Fact]
    public void A_warm_image_does_not_turn_blue_into_brown()
    {
        // Only browns and ambers, like a warm night photo: no colour anywhere
        // near blue, so the blue slot must not borrow one of these.
        Palette warm = FromHex("#0f0e0a", "#402d23", "#281f19", "#5f5d50", "#8e7569", "#b8ac7f", "#c0c5bb");

        Scheme s = SchemeBuilder.Build(warm, ThemeMode.Dark);

        Assert.InRange(HueDistance(s[4], 280), 0, 40);
        Assert.InRange(HueDistance(s[12], 280), 0, 40);
    }

    [Theory]
    [MemberData(nameof(Modes))]
    public void A_single_grey_still_gives_a_complete_readable_scheme(ThemeMode mode)
    {
        Scheme s = SchemeBuilder.Build(FromHex("#808080"), mode);

        Assert.Equal(16, s.Colors.Count);
        Assert.True(Contrast.Ratio(s.Foreground, s.Background) >= Contrast.Enhanced);
        Assert.All(s.Colors.Skip(1).Take(6), c => Assert.True(Contrast.Ratio(c, s.Background) >= Contrast.Text));
    }

    [Fact]
    public void Same_palette_gives_the_same_scheme()
    {
        Assert.Equal(SchemeBuilder.Build(Night, ThemeMode.Dark).Colors, SchemeBuilder.Build(Night, ThemeMode.Dark).Colors);
    }

    private static Palette FromHex(params string[] hex) =>
        new([.. hex.Select(h => new Swatch(Rgb.FromHex(h), 1.0 / hex.Length))]);

    private static double HueDistance(Rgb color, double target)
    {
        double d = Math.Abs(color.ToLab().Hue - target) % 360;
        return d > 180 ? 360 - d : d;
    }
}
