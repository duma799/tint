using SixLabors.ImageSharp;
using SixLabors.ImageSharp.PixelFormats;
using Tint.Core.Colors;
using Tint.Core.Palettes;

namespace Tint.Core.Tests;

public class PaletteExtractorTests
{
    private static readonly Rgb24 Red = new(255, 0, 0);
    private static readonly Rgb24 Blue = new(0, 0, 255);

    [Fact]
    public void Finds_the_colours_of_a_two_colour_image_and_their_shares()
    {
        // Left three quarters red, right quarter blue.
        using var image = new Image<Rgb24>(100, 40);
        Fill(image, (x, _) => x < 75 ? Red : Blue);

        Palette palette = PaletteExtractor.FromImage(image, new ExtractOptions { Count = 16 });

        // Only two distinct colours exist, so asking for 16 still yields 2.
        Assert.Equal(2, palette.Swatches.Count);
        Assert.Equal(new Rgb(255, 0, 0), palette.Swatches[0].Color);
        Assert.Equal(new Rgb(0, 0, 255), palette.Swatches[1].Color);
        Assert.Equal(0.75, palette.Swatches[0].Share, precision: 3);
        Assert.Equal(0.25, palette.Swatches[1].Share, precision: 3);
    }

    [Fact]
    public void Shares_add_up_to_one_and_are_sorted_most_common_first()
    {
        using Image<Rgb24> image = Gradient(320, 180);

        Palette palette = PaletteExtractor.FromImage(image);

        Assert.Equal(1.0, palette.Swatches.Sum(s => s.Share), precision: 6);
        Assert.Equal(palette.Swatches.OrderByDescending(s => s.Share), palette.Swatches);
    }

    [Fact]
    public void Returns_the_requested_number_of_colours_for_a_rich_image()
    {
        using Image<Rgb24> image = Gradient(640, 360);

        Palette palette = PaletteExtractor.FromImage(image, new ExtractOptions { Count = 16 });

        Assert.Equal(16, palette.Swatches.Count);
        Assert.Equal(16, palette.Swatches.Select(s => s.Color).Distinct().Count());
    }

    [Fact]
    public void Same_image_always_gives_the_same_palette()
    {
        using Image<Rgb24> image = Gradient(400, 300);

        Palette first = PaletteExtractor.FromImage(image);
        Palette second = PaletteExtractor.FromImage(image);

        Assert.Equal(first.Swatches, second.Swatches);
    }

    [Fact]
    public void Does_not_modify_the_callers_image()
    {
        using Image<Rgb24> image = Gradient(1000, 500);

        PaletteExtractor.FromImage(image);

        Assert.Equal(1000, image.Width);
        Assert.Equal(500, image.Height);
    }

    [Fact]
    public void Dark_image_is_reported_as_dark()
    {
        using var image = new Image<Rgb24>(50, 50);
        Fill(image, (_, _) => new Rgb24(20, 24, 40));

        Assert.True(PaletteExtractor.FromImage(image).IsDark);
    }

    [Fact]
    public void Rejects_a_count_below_one()
    {
        using var image = new Image<Rgb24>(4, 4);

        Assert.Throws<ArgumentOutOfRangeException>(() =>
            PaletteExtractor.FromImage(image, new ExtractOptions { Count = 0 }));
    }

    private static Image<Rgb24> Gradient(int width, int height)
    {
        var image = new Image<Rgb24>(width, height);
        Fill(image, (x, y) => new Rgb24((byte)(255 * x / width), (byte)(255 * y / height), (byte)(255 - (255 * x / width))));
        return image;
    }

    private static void Fill(Image<Rgb24> image, Func<int, int, Rgb24> color)
    {
        for (int y = 0; y < image.Height; y++)
        {
            for (int x = 0; x < image.Width; x++)
            {
                image[x, y] = color(x, y);
            }
        }
    }
}
