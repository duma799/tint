using SixLabors.ImageSharp;
using SixLabors.ImageSharp.PixelFormats;
using Tint.Core.Util;

namespace Tint.Core.Imaging;

public static class ImageLoader
{
    private static readonly string[] HeifExtensions = [".heic", ".heif"];

    /// <summary>
    /// Loads JPG, PNG, WebP, BMP, GIF and TIFF directly. HEIC — the format of
    /// macOS's built-in wallpapers — is not supported by ImageSharp, so on macOS
    /// it is converted with <c>sips</c>, which ships with the system.
    /// </summary>
    public static Image<Rgb24> Load(string path)
    {
        if (!File.Exists(path))
        {
            throw new FileNotFoundException($"No such image: {path}", path);
        }

        bool isHeif = HeifExtensions.Contains(Path.GetExtension(path).ToLowerInvariant());
        if (!isHeif)
        {
            try
            {
                return Image.Load<Rgb24>(path);
            }
            catch (UnknownImageFormatException) when (OperatingSystem.IsMacOS())
            {
                // Fall through: sips reads nearly anything macOS can display.
            }
            catch (UnknownImageFormatException)
            {
                throw new NotSupportedException(
                    $"Can't read {Path.GetFileName(path)}: not a supported image. " +
                    "Use JPG, PNG, WebP, BMP, GIF or TIFF.");
            }
        }

        if (!OperatingSystem.IsMacOS())
        {
            throw new NotSupportedException(
                $"Can't read {Path.GetFileName(path)}: HEIC images are only supported on macOS for now. " +
                "Convert it to JPG or PNG first.");
        }

        return LoadViaSips(path);
    }

    private static Image<Rgb24> LoadViaSips(string path)
    {
        string temp = Path.Combine(Path.GetTempPath(), $"tint-{Guid.NewGuid():N}.png");
        try
        {
            ProcessResult result = ProcessRunner.Run("sips", ["-s", "format", "png", path, "--out", temp]);
            if (!result.Succeeded || !File.Exists(temp))
            {
                throw new InvalidOperationException($"sips could not convert {path}: {result.StdErr}");
            }

            return Image.Load<Rgb24>(temp);
        }
        finally
        {
            File.Delete(temp);
        }
    }
}
