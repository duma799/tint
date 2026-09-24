namespace Tint.Core.Wallpapers;

/// <summary>
/// Several sources on one machine — Omarchy's backgrounds and waypaper on the
/// same Linux install, say. Whichever changes is the new wallpaper; at start,
/// the one that set a wallpaper most recently wins.
/// </summary>
public sealed class CompositeWallpaperSource : IWallpaperSource
{
    private readonly IWallpaperSource[] _sources;
    private readonly Lock _gate = new();
    private IWallpaperSource? _active;

    public CompositeWallpaperSource(params IWallpaperSource[] sources)
    {
        if (sources.Length == 0)
        {
            throw new ArgumentException("At least one source is required.", nameof(sources));
        }

        _sources = sources;
        foreach (IWallpaperSource source in _sources)
        {
            source.Changed += (_, e) =>
            {
                lock (_gate)
                {
                    _active = source;
                }

                // The others no longer show what's on screen, so their next
                // write must count even if it's a picture they set before.
                foreach (WatchedWallpaperSource other in _sources.OfType<WatchedWallpaperSource>())
                {
                    if (!ReferenceEquals(other, source))
                    {
                        other.MarkSuperseded();
                    }
                }

                Changed?.Invoke(this, e);
            };
            source.Trace += message => Trace?.Invoke($"[{source.Name}] {message}");
            source.Notice += message => Notice?.Invoke(message);
        }
    }

    public string Name => string.Join(" + ", _sources.Select(s => s.Name));

    public event EventHandler<WallpaperChangedEventArgs>? Changed;

    public event Action<string>? Trace;

    public event Action<string>? Notice;

    public DateTime? LastSetUtc => _sources.Max(s => s.LastSetUtc);

    public string? Current()
    {
        IWallpaperSource? active;
        lock (_gate)
        {
            active = _active;
        }

        return active?.Current() ?? MostRecent()?.Current();
    }

    public void Start()
    {
        foreach (IWallpaperSource source in _sources)
        {
            source.Start();
        }
    }

    public void Dispose()
    {
        foreach (IWallpaperSource source in _sources)
        {
            source.Dispose();
        }
    }

    /// <summary>The source that set a wallpaper last, among those that have one.</summary>
    private IWallpaperSource? MostRecent() =>
        _sources
            .Where(s => s.Current() is not null)
            .OrderByDescending(s => s.LastSetUtc ?? DateTime.MinValue)
            .FirstOrDefault();
}
