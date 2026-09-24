using SixLabors.ImageSharp;
using SixLabors.ImageSharp.PixelFormats;
using Tint.Core.Imaging;
using Tint.Core.Wallpapers;

namespace Tint.Core.Tests;

public sealed class SnapshotTests : IDisposable
{
    private readonly string _dir = Directory.CreateTempSubdirectory("tint-snapshots-").FullName;

    public void Dispose() => Directory.Delete(_dir, recursive: true);

    [Fact]
    public void Extension_providers_map_to_their_own_folder()
    {
        Assert.Equal(
            ["extension-com.apple.NeptuneOneExtension"],
            MacWallpaperStore.SnapshotFolderNames("com.apple.NeptuneOneExtension"));
    }

    [Fact]
    public void The_picture_provider_also_maps_to_its_extension_folder()
    {
        Assert.Equal(
            ["extension-com.apple.wallpaper.choice.image", "extension-com.apple.wallpaper.extension.image"],
            MacWallpaperStore.SnapshotFolderNames("com.apple.wallpaper.choice.image"));
    }

    [Fact]
    public void Picks_the_most_recently_rendered_snapshot()
    {
        Touch("old-2940-1912.bmp", new DateTime(2026, 9, 1, 0, 0, 0, DateTimeKind.Utc));
        Touch("new-2940-1912.bmp", new DateTime(2026, 9, 24, 12, 0, 0, DateTimeKind.Utc));
        Touch("notes.txt", new DateTime(2026, 9, 25, 0, 0, 0, DateTimeKind.Utc)); // not an image

        Assert.Equal(Path.Combine(_dir, "new-2940-1912.bmp"), MacWallpaperStore.NewestSnapshot(_dir));
    }

    [Fact]
    public void Missing_or_empty_folders_have_no_snapshot()
    {
        Assert.Null(MacWallpaperStore.NewestSnapshot(Path.Combine(_dir, "missing")));
        Assert.Null(MacWallpaperStore.NewestSnapshot(_dir));
    }

    [Fact]
    public void Reads_the_bmp_format_macOS_writes_snapshots_in()
    {
        // 32-bit, BITMAPV5HEADER, negative height (rows stored top to bottom) —
        // matching `file` on a real snapshot: "PC bitmap, Windows 98/2000 and
        // newer format, 3000 x -1688 x 32, bits offset 138".
        string path = Path.Combine(_dir, "snapshot.bmp");
        File.WriteAllBytes(path, TopDownBmpV5(
            [
                [(255, 0, 0), (0, 0, 255)], // top row: red, blue
                [(0, 255, 0), (255, 255, 255)], // bottom row: green, white
            ]));

        using Image<Rgb24> image = ImageLoader.Load(path);

        Assert.Equal(new Rgb24(255, 0, 0), image[0, 0]);
        Assert.Equal(new Rgb24(0, 0, 255), image[1, 0]);
        Assert.Equal(new Rgb24(0, 255, 0), image[0, 1]);
        Assert.Equal(new Rgb24(255, 255, 255), image[1, 1]);
    }

    private void Touch(string name, DateTime modifiedUtc)
    {
        string path = Path.Combine(_dir, name);
        File.WriteAllBytes(path, [1, 2, 3]);
        File.SetLastWriteTimeUtc(path, modifiedUtc);
    }

    private static byte[] TopDownBmpV5((byte R, byte G, byte B)[][] rows)
    {
        int height = rows.Length;
        int width = rows[0].Length;
        const int fileHeader = 14;
        const int v5Header = 124;
        int pixelBytes = width * height * 4;

        using var stream = new MemoryStream();
        using var w = new BinaryWriter(stream);

        // BITMAPFILEHEADER
        w.Write((byte)'B');
        w.Write((byte)'M');
        w.Write(fileHeader + v5Header + pixelBytes);
        w.Write(0);
        w.Write(fileHeader + v5Header); // bits offset 138

        // BITMAPV5HEADER
        w.Write(v5Header);
        w.Write(width);
        w.Write(-height); // negative: top-down
        w.Write((short)1); // planes
        w.Write((short)32); // bits per pixel
        w.Write(3); // BI_BITFIELDS
        w.Write(pixelBytes);
        w.Write(2835); // 72 dpi
        w.Write(2835);
        w.Write(0); // colours used
        w.Write(0); // important colours
        w.Write(0x00FF0000); // red mask
        w.Write(0x0000FF00); // green mask
        w.Write(0x000000FF); // blue mask
        w.Write(unchecked((int)0xFF000000)); // alpha mask
        w.Write(0x73524742); // 'sRGB' colour space
        w.Write(new byte[36]); // endpoints
        w.Write(new byte[12]); // gamma
        w.Write(4); // intent
        w.Write(0); // profile data
        w.Write(0); // profile size
        w.Write(0); // reserved

        foreach ((byte R, byte G, byte B)[] row in rows)
        {
            foreach ((byte r, byte g, byte b) in row)
            {
                w.Write(b);
                w.Write(g);
                w.Write(r);
                w.Write((byte)255);
            }
        }

        w.Flush();
        return stream.ToArray();
    }
}
