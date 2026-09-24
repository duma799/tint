namespace Tint.Core.Wallpapers;

/// <summary>
/// Shared machinery for sources that learn about changes from files on disk:
/// watch a directory, debounce the burst of events a change produces, then ask
/// <see cref="Current"/> what the wallpaper is now and raise
/// <see cref="Changed"/> only if it is actually different.
/// </summary>
public abstract class WatchedWallpaperSource : IWallpaperSource
{
    private static readonly TimeSpan SettleDelay = TimeSpan.FromMilliseconds(400);
    private static readonly TimeSpan PollInterval = TimeSpan.FromSeconds(2);

    private readonly TimeProvider _time;
    private readonly Debouncer _debouncer;
    private readonly Lock _gate = new();
    private FileSystemWatcher? _watcher;
    private ITimer? _poll;
    private string? _last;

    protected WatchedWallpaperSource(TimeProvider? timeProvider = null)
    {
        _time = timeProvider ?? TimeProvider.System;
        _debouncer = new Debouncer(SettleDelay, Check, _time);
    }

    public abstract string Name { get; }

    /// <summary>Directory whose changes mean "the wallpaper may have changed".</summary>
    protected abstract string WatchDirectory { get; }

    /// <summary>File name filter inside <see cref="WatchDirectory"/>, e.g. "config.ini" or "*".</summary>
    protected virtual string WatchFilter => "*";

    public event EventHandler<WallpaperChangedEventArgs>? Changed;

    public event Action<string>? Trace;

    public abstract string? Current();

    public void Start()
    {
        _last = SafeCurrent();

        if (Directory.Exists(WatchDirectory))
        {
            _watcher = new FileSystemWatcher(WatchDirectory, WatchFilter)
            {
                IncludeSubdirectories = true,
                NotifyFilter = NotifyFilters.FileName | NotifyFilters.DirectoryName
                    | NotifyFilters.LastWrite | NotifyFilters.Size | NotifyFilters.CreationTime,
            };
            _watcher.Changed += OnFileEvent;
            _watcher.Created += OnFileEvent;
            _watcher.Deleted += OnFileEvent;
            _watcher.Renamed += OnFileEvent;
            _watcher.Error += (_, e) => OnTrace($"watcher error: {e.GetException().Message}");
            _watcher.EnableRaisingEvents = true;
            OnTrace($"watching {WatchDirectory}");
        }
        else
        {
            // Better slow than blind: if the expected directory isn't there
            // (a different OS version, say), fall back to asking periodically.
            OnTrace($"{WatchDirectory} not found — checking every {PollInterval.TotalSeconds:0} s instead");
            _poll = _time.CreateTimer(_ => Check(), state: null, PollInterval, PollInterval);
        }
    }

    public void Dispose()
    {
        _watcher?.Dispose();
        _poll?.Dispose();
        _debouncer.Dispose();
        GC.SuppressFinalize(this);
    }

    protected void OnTrace(string message) => Trace?.Invoke(message);

    /// <summary>Re-reads the wallpaper and raises <see cref="Changed"/> if it moved on.</summary>
    internal void Check()
    {
        string? current = SafeCurrent();
        lock (_gate)
        {
            if (current is null || current == _last)
            {
                return;
            }

            _last = current;
        }

        Changed?.Invoke(this, new WallpaperChangedEventArgs(current));
    }

    private void OnFileEvent(object sender, FileSystemEventArgs e)
    {
        OnTrace($"{e.ChangeType.ToString().ToLowerInvariant()}: {e.FullPath}");
        _debouncer.Trigger();
    }

    private string? SafeCurrent()
    {
        try
        {
            return Current();
        }
        catch (Exception ex) when (ex is IOException or InvalidOperationException or TimeoutException or UnauthorizedAccessException)
        {
            OnTrace($"could not read the current wallpaper: {ex.Message}");
            return null;
        }
    }
}
