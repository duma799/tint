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
            // Watch every wallpaper tool that's present: Omarchy users can still
            // set wallpapers with waypaper, and whichever acts last wins.
            var sources = new List<IWallpaperSource>();
            if (Directory.Exists(Path.Combine(OmarchyWallpaperSource.DefaultStateDirectory, "current")))
            {
                sources.Add(new OmarchyWallpaperSource());
            }

            if (Directory.Exists(WaypaperWallpaperSource.DefaultConfigDirectory) || sources.Count == 0)
            {
                sources.Add(new WaypaperWallpaperSource());
            }

            return sources.Count == 1 ? sources[0] : new CompositeWallpaperSource([.. sources]);
        }

        throw new PlatformNotSupportedException("tint supports macOS and Linux.");
    }
}
