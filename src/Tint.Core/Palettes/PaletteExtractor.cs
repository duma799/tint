using SixLabors.ImageSharp;
using SixLabors.ImageSharp.PixelFormats;
using SixLabors.ImageSharp.Processing;
using Tint.Core.Colors;
using Tint.Core.Imaging;

namespace Tint.Core.Palettes;

public sealed record ExtractOptions
{
    /// <summary>How many colours to extract.</summary>
    public int Count { get; init; } = 16;

    /// <summary>
    /// The image is shrunk so its longer side is at most this many pixels before
    /// clustering. 256 keeps a 5K wallpaper to ~65k pixels — fast, and the
    /// palette barely changes compared with using every pixel.
    /// </summary>
    public int MaxSide { get; init; } = 256;

    /// <summary>Fixed seed: the same image always produces the same palette.</summary>
    public int Seed { get; init; } = 7;
}

public static class PaletteExtractor
{
    public static Palette FromFile(string path, ExtractOptions? options = null)
    {
        using Image<Rgb24> image = ImageLoader.Load(path);
        return FromImage(image, options);
    }

    public static Palette FromImage(Image<Rgb24> image, ExtractOptions? options = null)
    {
        options ??= new ExtractOptions();
        if (options.Count < 1)
        {
            throw new ArgumentOutOfRangeException(nameof(options), "Count must be at least 1.");
        }

        using Image<Rgb24> small = image.Clone(ctx =>
        {
            if (image.Width > options.MaxSide || image.Height > options.MaxSide)
            {
                ctx.Resize(new ResizeOptions
                {
                    Size = new Size(options.MaxSide, options.MaxSide),
                    Mode = ResizeMode.Max,
                    // Box averages whole blocks of pixels: no sharpening halos,
                    // which would otherwise invent colours that are not there.
                    Sampler = KnownResamplers.Box,
                });
            }
        });

        var points = new Lab[small.Width * small.Height];
        small.ProcessPixelRows(rows =>
        {
            for (int y = 0; y < rows.Height; y++)
            {
                Span<Rgb24> row = rows.GetRowSpan(y);
                for (int x = 0; x < row.Length; x++)
                {
                    Rgb24 p = row[x];
                    points[(y * row.Length) + x] = Lab.FromRgb(new Rgb(p.R, p.G, p.B));
                }
            }
        });

        KMeans.Cluster[] clusters = KMeans.Run(points, options.Count, options.Seed);
        double total = points.Length;

        Swatch[] swatches =
        [
            .. clusters
                .OrderByDescending(c => c.Count)
                .Select(c => new Swatch(c.Center.ToRgb(), c.Count / total)),
        ];

        return new Palette(swatches);
    }
}
