namespace Tint.Core.Wallpapers;

public sealed class WallpaperChangedEventArgs(string path) : EventArgs
{
    public string Path { get; } = path;
}

/// <summary>
/// Knows where the current wallpaper is and says when it changes. There is one
/// implementation per platform; the rest of tint only ever sees this interface.
/// </summary>
public interface IWallpaperSource : IDisposable
{
    /// <summary>Human-readable name, e.g. "macOS" or "waypaper".</summary>
    string Name { get; }

    /// <summary>Path of the current wallpaper, or null if it can't be determined.</summary>
    string? Current();

    /// <summary>Raised once per actual change, after bursts of file events have settled.</summary>
    event EventHandler<WallpaperChangedEventArgs>? Changed;

    /// <summary>Low-level detail (raw file events, fallbacks) for <c>--verbose</c>.</summary>
    event Action<string>? Trace;

    /// <summary>Begins watching. Events are raised on a background thread.</summary>
    void Start();
}
