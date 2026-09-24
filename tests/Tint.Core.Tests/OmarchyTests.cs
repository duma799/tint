using Tint.Core.Wallpapers;

namespace Tint.Core.Tests;

public sealed class OmarchyTests : IDisposable
{
    private readonly string _state = Directory.CreateTempSubdirectory("tint-omarchy-").FullName;
    private readonly string _current;
    private readonly string _backgrounds;

    public OmarchyTests()
    {
        _current = Directory.CreateDirectory(Path.Combine(_state, "current")).FullName;
        _backgrounds = Directory.CreateDirectory(Path.Combine(_state, "backgrounds")).FullName;
        File.WriteAllBytes(Path.Combine(_backgrounds, "1-mountains.jpg"), [1]);
        File.WriteAllBytes(Path.Combine(_backgrounds, "2-city.png"), [1]);
    }

    public void Dispose() => Directory.Delete(_state, recursive: true);

    [Fact]
    public void Follows_the_background_symlink_to_the_real_file()
    {
        PointAt("1-mountains.jpg");
        using var source = new OmarchyWallpaperSource(_state);

        Assert.Equal(Path.Combine(_backgrounds, "1-mountains.jpg"), source.Current());
    }

    [Fact]
    public void Re_pointing_the_symlink_changes_the_wallpaper()
    {
        using var source = new OmarchyWallpaperSource(_state);

        PointAt("1-mountains.jpg");
        string? before = source.Current();
        PointAt("2-city.png");
        string? after = source.Current();

        Assert.NotEqual(before, after);
        Assert.Equal(Path.Combine(_backgrounds, "2-city.png"), after);
    }

    [Fact]
    public void A_broken_symlink_means_no_wallpaper()
    {
        File.CreateSymbolicLink(Path.Combine(_current, "background"), Path.Combine(_backgrounds, "deleted.jpg"));
        using var source = new OmarchyWallpaperSource(_state);

        Assert.Null(source.Current());
    }

    [Fact]
    public void A_plain_file_is_used_as_is()
    {
        string plain = Path.Combine(_current, "background");
        File.WriteAllBytes(plain, [1]);
        using var source = new OmarchyWallpaperSource(_state);

        Assert.Equal(plain, source.Current());
    }

    [Fact]
    public void Nothing_set_yet_means_no_wallpaper()
    {
        using var source = new OmarchyWallpaperSource(_state);

        Assert.Null(source.Current());
    }

    private void PointAt(string name)
    {
        string link = Path.Combine(_current, "background");
        if (File.Exists(link) || new FileInfo(link).LinkTarget is not null)
        {
            File.Delete(link);
        }

        File.CreateSymbolicLink(link, Path.Combine(_backgrounds, name));
    }
}
