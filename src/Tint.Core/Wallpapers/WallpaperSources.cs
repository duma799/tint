namespace Tint.Core.Wallpapers;

public static class WallpaperSources
{
    /// <summary>
    /// The one place that knows which OS we're on. Everything after this talks
    /// to <see cref="IWallpaperSource"/> and doesn't care.
    /// </summary>
    public static IWallpaperSource ForCurrentPlatform()
    {
        if (OperatingSystem.IsMacOS())
        {
            return new MacWallpaperSource();
        }

        if (OperatingSystem.IsLinux())
        {
            // Omarchy manages its own backgrounds; everywhere else, waypaper.
            return Directory.Exists(Path.Combine(OmarchyWallpaperSource.DefaultStateDirectory, "current"))
                ? new OmarchyWallpaperSource()
                : new WaypaperWallpaperSource();
        }

        throw new PlatformNotSupportedException("tint supports macOS and Linux.");
    }
}
