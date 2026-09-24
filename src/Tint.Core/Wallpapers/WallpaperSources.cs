namespace Tint.Core.Wallpapers;

public static class WallpaperSources
{
    /// <summary>The wallpaper source for this machine. tint is macOS-only.</summary>
    public static IWallpaperSource ForCurrentPlatform()
    {
        if (OperatingSystem.IsMacOS())
        {
            return new MacWallpaperSource();
        }

        throw new PlatformNotSupportedException("tint runs on macOS.");
    }
}
