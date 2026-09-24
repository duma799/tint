using Tint.Core.Colors;

namespace Tint.Core.Tests;

public class ColorTests
{
    [Theory]
    [InlineData("#1b2233", 0x1b, 0x22, 0x33)]
    [InlineData("d8f4ff", 0xd8, 0xf4, 0xff)]
    [InlineData("  #FFFFFF ", 255, 255, 255)]
    public void FromHex_parses_with_or_without_hash(string hex, byte r, byte g, byte b)
    {
        Assert.Equal(new Rgb(r, g, b), Rgb.FromHex(hex));
    }

    [Theory]
    [InlineData("#12345")]
    [InlineData("#1234567")]
    [InlineData("zzzzzz")]
    public void FromHex_rejects_malformed_input(string hex)
    {
        Assert.ThrowsAny<FormatException>(() => Rgb.FromHex(hex));
    }

    [Fact]
    public void Hex_is_lowercase_and_padded()
    {
        Assert.Equal("#0a0b0c", new Rgb(10, 11, 12).Hex);
    }

    [Fact]
    public void White_and_black_sit_at_the_ends_of_lightness()
    {
        Lab white = new Rgb(255, 255, 255).ToLab();
        Lab black = new Rgb(0, 0, 0).ToLab();

        Assert.Equal(100, white.L, precision: 2);
        Assert.Equal(0, white.A, precision: 2);
        Assert.Equal(0, white.B, precision: 2);
        Assert.Equal(0, black.L, precision: 2);
    }

    [Fact]
    public void Pure_red_matches_reference_Lab_values()
    {
        // Reference: sRGB (255, 0, 0) under D65 is about L 53.24, a 80.09, b 67.20.
        Lab red = new Rgb(255, 0, 0).ToLab();

        Assert.Equal(53.24, red.L, precision: 1);
        Assert.Equal(80.09, red.A, precision: 1);
        Assert.Equal(67.20, red.B, precision: 1);
    }

    [Fact]
    public void Rgb_to_Lab_and_back_is_lossless()
    {
        for (int r = 0; r < 256; r += 15)
        {
            for (int g = 0; g < 256; g += 15)
            {
                for (int b = 0; b < 256; b += 15)
                {
                    var original = new Rgb((byte)r, (byte)g, (byte)b);
                    Assert.Equal(original, original.ToLab().ToRgb());
                }
            }
        }
    }

    [Fact]
    public void Distance_is_zero_for_equal_colours_and_symmetric()
    {
        Lab a = new Rgb(30, 60, 90).ToLab();
        Lab b = new Rgb(200, 100, 50).ToLab();

        Assert.Equal(0, a.DistanceTo(a));
        Assert.Equal(a.DistanceTo(b), b.DistanceTo(a), precision: 10);
    }
}
