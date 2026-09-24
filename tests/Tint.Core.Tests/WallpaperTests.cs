using Microsoft.Extensions.Time.Testing;
using Tint.Core.Wallpapers;

namespace Tint.Core.Tests;

public class DebouncerTests
{
    [Fact]
    public void A_burst_of_triggers_causes_one_call_after_the_delay()
    {
        var time = new FakeTimeProvider();
        int calls = 0;
        using var debouncer = new Debouncer(TimeSpan.FromMilliseconds(400), () => calls++, time);

        debouncer.Trigger();
        time.Advance(TimeSpan.FromMilliseconds(100));
        debouncer.Trigger();
        time.Advance(TimeSpan.FromMilliseconds(100));
        debouncer.Trigger();

        time.Advance(TimeSpan.FromMilliseconds(399));
        Assert.Equal(0, calls);

        time.Advance(TimeSpan.FromMilliseconds(1));
        Assert.Equal(1, calls);
    }

    [Fact]
    public void Separate_bursts_cause_separate_calls()
    {
        var time = new FakeTimeProvider();
        int calls = 0;
        using var debouncer = new Debouncer(TimeSpan.FromMilliseconds(400), () => calls++, time);

        debouncer.Trigger();
        time.Advance(TimeSpan.FromSeconds(1));
        debouncer.Trigger();
        time.Advance(TimeSpan.FromSeconds(1));

        Assert.Equal(2, calls);
    }
}

public class WatchedWallpaperSourceTests
{
    /// <summary>A source whose "current wallpaper" the test controls directly.</summary>
    private sealed class FakeSource(TimeProvider time) : WatchedWallpaperSource(time)
    {
        public string? Wallpaper { get; set; }

        public override string Name => "fake";

        // Doesn't exist, so the source falls back to polling on the fake clock.
        protected override string WatchDirectory => Path.Combine(Path.GetTempPath(), $"tint-missing-{Guid.NewGuid():N}");

        public override string? Current()
        {
            if (Wallpaper is null)
            {
                OnNotice("no image file");
            }

            return Wallpaper;
        }
    }

    [Fact]
    public void Notices_are_shown_once_until_a_readable_wallpaper_returns()
    {
        var time = new FakeTimeProvider();
        using var source = new FakeSource(time) { Wallpaper = "/walls/a.jpg" };
        var notices = new List<string>();
        source.Notice += notices.Add;
        source.Start();

        source.Wallpaper = null;
        time.Advance(TimeSpan.FromSeconds(2));
        time.Advance(TimeSpan.FromSeconds(2));
        time.Advance(TimeSpan.FromSeconds(2));
        Assert.Single(notices);

        source.Wallpaper = "/walls/b.jpg";
        time.Advance(TimeSpan.FromSeconds(2));
        source.Wallpaper = null;
        time.Advance(TimeSpan.FromSeconds(2));
        Assert.Equal(2, notices.Count);
    }

    [Fact]
    public void Raises_Changed_once_per_actual_change()
    {
        var time = new FakeTimeProvider();
        using var source = new FakeSource(time) { Wallpaper = "/walls/a.jpg" };
        var seen = new List<string>();
        source.Changed += (_, e) => seen.Add(e.Path);
        source.Start();

        time.Advance(TimeSpan.FromSeconds(2));
        Assert.Empty(seen); // unchanged since Start

        source.Wallpaper = "/walls/b.jpg";
        time.Advance(TimeSpan.FromSeconds(2));
        time.Advance(TimeSpan.FromSeconds(2));
        Assert.Equal(["/walls/b.jpg"], seen); // reported once, not on every poll

        source.Wallpaper = "/walls/a.jpg";
        time.Advance(TimeSpan.FromSeconds(2));
        Assert.Equal(["/walls/b.jpg", "/walls/a.jpg"], seen);
    }

    [Fact]
    public void Ignores_moments_when_the_wallpaper_cannot_be_read()
    {
        var time = new FakeTimeProvider();
        using var source = new FakeSource(time) { Wallpaper = "/walls/a.jpg" };
        var seen = new List<string>();
        source.Changed += (_, e) => seen.Add(e.Path);
        source.Start();

        source.Wallpaper = null;
        time.Advance(TimeSpan.FromSeconds(2));
        source.Wallpaper = "/walls/a.jpg";
        time.Advance(TimeSpan.FromSeconds(2));

        Assert.Empty(seen);
    }

    [Fact]
    public void Reports_the_fallback_through_Trace()
    {
        using var source = new FakeSource(new FakeTimeProvider());
        var trace = new List<string>();
        source.Trace += trace.Add;

        source.Start();

        Assert.Contains(trace, line => line.Contains("checking every", StringComparison.Ordinal));
    }
}

public class WaypaperConfigTests
{
    private const string Home = "/home/duma";

    [Fact]
    public void Reads_the_wallpaper_line_and_expands_the_home_folder()
    {
        const string ini = """
            [Settings]
            language = en
            folder = ~/Pictures/wallpapers
            wallpaper = ~/Pictures/wallpapers/city.jpg
            backend = swaybg
            """;

        Assert.Equal("/home/duma/Pictures/wallpapers/city.jpg", WaypaperWallpaperSource.ParseWallpaper(ini, Home));
    }

    [Fact]
    public void Takes_the_first_of_several_monitors()
    {
        const string ini = "[Settings]\nwallpaper = /walls/left.png,/walls/right.png\n";

        Assert.Equal("/walls/left.png", WaypaperWallpaperSource.ParseWallpaper(ini, Home));
    }

    [Fact]
    public void Tolerates_spacing_and_windows_line_endings()
    {
        const string ini = "[Settings]\r\n  wallpaper=/walls/a.jpg  \r\n";

        Assert.Equal("/walls/a.jpg", WaypaperWallpaperSource.ParseWallpaper(ini, Home));
    }

    [Theory]
    [InlineData("[Settings]\nfolder = ~/Pictures\n")]
    [InlineData("[Settings]\nwallpaper =\n")]
    [InlineData("")]
    public void Returns_null_when_no_wallpaper_is_set(string ini)
    {
        Assert.Null(WaypaperWallpaperSource.ParseWallpaper(ini, Home));
    }

    [Fact]
    public void Does_not_confuse_similar_keys()
    {
        const string ini = "[Settings]\nwallpaper_folder = /walls\nwallpaper = /walls/a.jpg\n";

        Assert.Equal("/walls/a.jpg", WaypaperWallpaperSource.ParseWallpaper(ini, Home));
    }
}
