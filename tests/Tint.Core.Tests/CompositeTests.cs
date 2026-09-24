using Microsoft.Extensions.Time.Testing;
using Tint.Core.Wallpapers;

namespace Tint.Core.Tests;

public class CompositeTests
{
    /// <summary>A polled source (its directory doesn't exist) whose wallpaper and timestamp the test sets.</summary>
    private sealed class ManualSource(string name, TimeProvider time) : WatchedWallpaperSource(time)
    {
        public string? Wallpaper { get; set; }

        public DateTime? SetAt { get; set; }

        public override string Name => name;

        public override DateTime? LastSetUtc => SetAt;

        protected override string WatchDirectory => Path.Combine(Path.GetTempPath(), $"tint-missing-{Guid.NewGuid():N}");

        public override string? Current() => Wallpaper;
    }

    private readonly FakeTimeProvider _time = new();

    private void Tick() => _time.Advance(TimeSpan.FromSeconds(2));

    [Fact]
    public void At_start_the_most_recently_set_source_wins()
    {
        var omarchy = new ManualSource("Omarchy", _time) { Wallpaper = "/omarchy.jpg", SetAt = new DateTime(2026, 9, 1) };
        var waypaper = new ManualSource("waypaper", _time) { Wallpaper = "/waypaper.jpg", SetAt = new DateTime(2026, 9, 24) };
        using var composite = new CompositeWallpaperSource(omarchy, waypaper);

        Assert.Equal("/waypaper.jpg", composite.Current());
        Assert.Equal("Omarchy + waypaper", composite.Name);
    }

    [Fact]
    public void A_change_in_either_source_is_reported_and_becomes_current()
    {
        var omarchy = new ManualSource("Omarchy", _time) { Wallpaper = "/omarchy-1.jpg", SetAt = new DateTime(2026, 9, 24) };
        var waypaper = new ManualSource("waypaper", _time) { Wallpaper = "/waypaper-1.jpg", SetAt = new DateTime(2026, 9, 1) };
        using var composite = new CompositeWallpaperSource(omarchy, waypaper);
        var seen = new List<string>();
        composite.Changed += (_, e) => seen.Add(e.Path);
        composite.Start();

        waypaper.Wallpaper = "/waypaper-2.jpg";
        Tick();
        Assert.Equal(["/waypaper-2.jpg"], seen);
        Assert.Equal("/waypaper-2.jpg", composite.Current());

        omarchy.Wallpaper = "/omarchy-2.jpg";
        Tick();
        Assert.Equal(["/waypaper-2.jpg", "/omarchy-2.jpg"], seen);
        Assert.Equal("/omarchy-2.jpg", composite.Current());
    }

    [Fact]
    public void Switching_back_to_a_picture_set_earlier_still_counts()
    {
        var omarchy = new ManualSource("Omarchy", _time) { Wallpaper = "/b.jpg" };
        var waypaper = new ManualSource("waypaper", _time) { Wallpaper = "/a.jpg" };
        using var composite = new CompositeWallpaperSource(omarchy, waypaper);
        var seen = new List<string>();
        composite.Changed += (_, e) => seen.Add(e.Path);
        composite.Start();

        // Omarchy takes over with c.jpg…
        omarchy.Wallpaper = "/c.jpg";
        Tick();
        Assert.Equal(["/c.jpg"], seen);

        // …a poll alone must not bring waypaper's old picture back…
        Tick();
        Assert.Equal(["/c.jpg"], seen);

        // …but waypaper actually writing a.jpg again (a file event) must.
        waypaper.Check(fromFileEvent: true);
        Assert.Equal(["/c.jpg", "/a.jpg"], seen);
        Assert.Equal("/a.jpg", composite.Current());
    }

    [Fact]
    public void Without_a_takeover_rewriting_the_same_picture_is_not_a_change()
    {
        var waypaper = new ManualSource("waypaper", _time) { Wallpaper = "/a.jpg" };
        var seen = new List<string>();
        waypaper.Changed += (_, e) => seen.Add(e.Path);
        waypaper.Start();

        waypaper.Check(fromFileEvent: true);

        Assert.Empty(seen);
    }
}
