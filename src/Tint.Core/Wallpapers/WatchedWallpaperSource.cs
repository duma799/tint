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
    private readonly List<FileSystemWatcher> _watchers = [];
    private ITimer? _poll;
    private string? _last;
    private string? _lastNotice;
    private bool _superseded;

    protected WatchedWallpaperSource(TimeProvider? timeProvider = null)
    {
        _time = timeProvider ?? TimeProvider.System;
        _debouncer = new Debouncer(SettleDelay, () => Check(fromFileEvent: true), _time);
    }

    public abstract string Name { get; }

    /// <summary>Directory whose changes mean "the wallpaper may have changed".</summary>
    protected abstract string WatchDirectory { get; }

    /// <summary>File name filter inside <see cref="WatchDirectory"/>, e.g. "config.ini" or "*".</summary>
    protected virtual string WatchFilter => "*";

    /// <summary>Further directories whose changes should trigger a re-check (all files).</summary>
    protected virtual IEnumerable<string> ExtraWatchDirectories => [];

    public event EventHandler<WallpaperChangedEventArgs>? Changed;

    public event Action<string>? Trace;

    public event Action<string>? Notice;

    public abstract string? Current();

    /// <summary>
    /// A file or folder whose modified time is when this source last set a
    /// wallpaper. Null if there is no such marker.
    /// </summary>
    protected virtual string? StampPath => null;

    public virtual DateTime? LastSetUtc
    {
        get
        {
            string? stamp = StampPath;
            if (stamp is null)
            {
                return null;
            }

            if (File.Exists(stamp))
            {
                return File.GetLastWriteTimeUtc(stamp);
            }

            return Directory.Exists(stamp) ? Directory.GetLastWriteTimeUtc(stamp) : null;
        }
    }

    public void Start()
    {
        _last = SafeCurrent();

        if (Directory.Exists(WatchDirectory))
        {
            Watch(WatchDirectory, WatchFilter);
        }
        else
        {
            // Better slow than blind: if the expected directory isn't there
            // (a different OS version, say), fall back to asking periodically.
            OnTrace($"{WatchDirectory} not found — checking every {PollInterval.TotalSeconds:0} s instead");
            _poll = _time.CreateTimer(_ => Check(), state: null, PollInterval, PollInterval);
        }

        foreach (string extra in ExtraWatchDirectories)
        {
            if (Directory.Exists(extra))
            {
                Watch(extra, "*");
            }
            else
            {
                OnTrace($"{extra} not found — not watching it");
            }
        }
    }

    public void Dispose()
    {
        foreach (FileSystemWatcher watcher in _watchers)
        {
            watcher.Dispose();
        }

        _poll?.Dispose();
        _debouncer.Dispose();
        GC.SuppressFinalize(this);
    }

    protected void OnTrace(string message) => Trace?.Invoke(message);

    /// <summary>Tells the user something, once — repeats of the same message are dropped.</summary>
    protected void OnNotice(string message)
    {
        lock (_gate)
        {
            if (message == _lastNotice)
            {
                return;
            }

            _lastNotice = message;
        }

        Notice?.Invoke(message);
    }

    /// <summary>
    /// Another source on the same machine took over the screen. From now on,
    /// if this source's tool writes again — even the same picture as before —
    /// that is a real change and gets reported.
    /// </summary>
    internal void MarkSuperseded()
    {
        lock (_gate)
        {
            _superseded = true;
        }
    }

    /// <summary>
    /// Re-reads the wallpaper and raises <see cref="Changed"/> if it moved on.
    /// <paramref name="fromFileEvent"/> is true when the tool actually wrote
    /// something (as opposed to a periodic poll); only then does re-setting the
    /// same picture after being superseded count as a change.
    /// </summary>
    internal void Check(bool fromFileEvent = false)
    {
        string? current = SafeCurrent();
        lock (_gate)
        {
            bool resetAfterTakeover = fromFileEvent && _superseded;
            if (current is null || (current == _last && !resetAfterTakeover))
            {
                return;
            }

            _last = current;
            _superseded = false;
            _lastNotice = null; // a readable wallpaper again: allow the same notice next time
        }

        Changed?.Invoke(this, new WallpaperChangedEventArgs(current));
    }

    private void Watch(string directory, string filter)
    {
        var watcher = new FileSystemWatcher(directory, filter)
        {
            IncludeSubdirectories = true,
            NotifyFilter = NotifyFilters.FileName | NotifyFilters.DirectoryName
                | NotifyFilters.LastWrite | NotifyFilters.Size | NotifyFilters.CreationTime,
        };
        watcher.Changed += OnFileEvent;
        watcher.Created += OnFileEvent;
        watcher.Deleted += OnFileEvent;
        watcher.Renamed += OnFileEvent;
        watcher.Error += (_, e) => OnTrace($"watcher error: {e.GetException().Message}");
        watcher.EnableRaisingEvents = true;
        _watchers.Add(watcher);
        OnTrace($"watching {directory}");
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
