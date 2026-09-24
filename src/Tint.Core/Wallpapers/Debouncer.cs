namespace Tint.Core.Wallpapers;

/// <summary>
/// Collapses a burst of triggers into one call, made once things have been
/// quiet for <c>delay</c>. Changing the wallpaper writes several files in quick
/// succession; without this, every write would re-theme everything.
/// </summary>
/// <remarks>
/// Takes a <see cref="TimeProvider"/> so tests can move time forward instantly
/// instead of sleeping.
/// </remarks>
public sealed class Debouncer : IDisposable
{
    private readonly TimeSpan _delay;
    private readonly ITimer _timer;

    public Debouncer(TimeSpan delay, Action action, TimeProvider? timeProvider = null)
    {
        _delay = delay;
        _timer = (timeProvider ?? TimeProvider.System)
            .CreateTimer(_ => action(), state: null, Timeout.InfiniteTimeSpan, Timeout.InfiniteTimeSpan);
    }

    /// <summary>(Re)starts the countdown. Only the last trigger in a burst leads to a call.</summary>
    public void Trigger() => _timer.Change(_delay, Timeout.InfiniteTimeSpan);

    public void Dispose() => _timer.Dispose();
}
