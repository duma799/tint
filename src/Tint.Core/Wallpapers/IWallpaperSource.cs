namespace Tint.Core.Wallpapers;

public sealed class WallpaperChangedEventArgs(string path) : EventArgs
{
    public string Path { get; } = path;
}

/// <summary>
/// Knows where the current wallpaper is and says when it changes. The real
/// one is <see cref="MacWallpaperSource"/>; the interface lets tests (and the
/// rest of tint) work without a Mac's wallpaper service.
/// </summary>
public interface IWallpaperSource : IDisposable
{
    /// <summary>Human-readable name, e.g. "macOS".</summary>
    string Name { get; }

    /// <summary>Path of the current wallpaper, or null if it can't be determined.</summary>
    string? Current();

    /// <summary>Raised once per actual change, after bursts of file events have settled.</summary>
    event EventHandler<WallpaperChangedEventArgs>? Changed;

    /// <summary>Low-level detail (raw file events, fallbacks) for <c>--verbose</c>.</summary>
    event Action<string>? Trace;

    /// <summary>
    /// Things the user should always see, e.g. "the new wallpaper has no image
    /// file to read". Raised once per distinct message, not on every file event.
    /// </summary>
    event Action<string>? Notice;

    /// <summary>Begins watching. Events are raised on a background thread.</summary>
    void Start();
}
