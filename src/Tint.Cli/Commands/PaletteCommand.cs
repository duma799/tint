using System.CommandLine;
using System.Globalization;
using Tint.Core.Palettes;

namespace Tint.Cli.Commands;

/// <summary><c>tint palette &lt;image&gt;</c> — extract and print a palette.</summary>
internal static class PaletteCommand
{
    public static Command Create()
    {
        var image = new Argument<FileInfo>("image") { Description = "Image to extract colours from." };
        var count = new Option<int>("--count", "-n")
        {
            Description = "How many colours to extract.",
            DefaultValueFactory = _ => 16,
        };

        var command = new Command("palette", "Extract a colour palette from an image.") { image, count };
        command.SetAction(parse =>
        {
            FileInfo file = parse.GetValue(image)!;
            int n = parse.GetValue(count);
            if (n is < 1 or > 64)
            {
                return Terminal.Error("--count must be between 1 and 64.");
            }

            Palette palette;
            try
            {
                palette = PaletteExtractor.FromFile(file.FullName, new ExtractOptions { Count = n });
            }
            catch (Exception ex) when (ex is IOException or NotSupportedException or InvalidOperationException
                or SixLabors.ImageSharp.ImageFormatException)
            {
                return Terminal.Error(ex.Message);
            }

            Print(palette);
            return 0;
        });

        return command;
    }

    internal static void Print(Palette palette)
    {
        foreach (Swatch swatch in palette.Swatches)
        {
            string share = (swatch.Share * 100).ToString("0.0", CultureInfo.InvariantCulture).PadLeft(5);
            Console.WriteLine($"  {Terminal.Block(swatch.Color)}  {swatch.Color.Hex}  {share}%");
        }

        string mood = palette.IsDark ? "dark" : "light";
        Console.WriteLine();
        Console.WriteLine($"  {palette.Swatches.Count} colours · {mood} image (lightness {palette.Lightness:0})");
    }
}
