using System.Xml.Linq;
using Tint.Core.Colors;
using Tint.Core.Output;
using Tint.Core.Palettes;
using Tint.Core.Reload;
using Tint.Core.Service;
using Tint.Core.Themes;

namespace Tint.Core.Tests;

/// <summary>Settings, the login agent, and the app reloads added in 0.4.</summary>
public sealed class SetupTests : IDisposable
{
    private static readonly Palette Night = new([.. new[] { "#1b2233", "#48596f", "#c68a65", "#d8f4ff", "#6d9c5a", "#b8455a" }
        .Select(h => new Swatch(Rgb.FromHex(h), 1.0 / 6))]);

    private static readonly Scheme Scheme = SchemeBuilder.Build(Night, ThemeMode.Dark);

    private readonly string _dir = Directory.CreateTempSubdirectory("tint-setup-").FullName;

    public void Dispose() => Directory.Delete(_dir, recursive: true);

    [Fact]
    public void Settings_round_trip()
    {
        string path = Path.Combine(_dir, "settings.json");
        new TintSettings { Mode = null, Saturation = 1.25 }.Save(path);

        TintSettings loaded = TintSettings.Load(path);

        Assert.Null(loaded.Mode);
        Assert.Equal(1.25, loaded.Saturation);
    }

    [Theory]
    [InlineData("not json")]
    [InlineData("[1, 2]")]
    [InlineData("{\"mode\": 3}")]
    public void Broken_settings_fall_back_to_the_defaults(string content)
    {
        string path = Path.Combine(_dir, "settings.json");
        File.WriteAllText(path, content);

        Assert.Equal(new TintSettings(), TintSettings.Load(path));
    }

    [Fact]
    public void Missing_settings_are_the_defaults_and_saturation_is_clamped()
    {
        Assert.Equal(new TintSettings(), TintSettings.Load(Path.Combine(_dir, "none.json")));

        string path = Path.Combine(_dir, "settings.json");
        File.WriteAllText(path, "{\"mode\": \"light\", \"saturation\": 9}");
        TintSettings loaded = TintSettings.Load(path);

        Assert.Equal(ThemeMode.Light, loaded.Mode);
        Assert.Equal(SchemeBuilder.MaxSaturation, loaded.Saturation);
    }

    [Fact]
    public void Saturation_scales_how_colourful_the_accents_are()
    {
        static double Chroma(Scheme s) => s.Colors.Skip(1).Take(6).Average(c => c.ToLab().Chroma);

        double muted = Chroma(SchemeBuilder.Build(Night, ThemeMode.Dark, SchemeBuilder.MinSaturation));
        double normal = Chroma(SchemeBuilder.Build(Night, ThemeMode.Dark));
        double vivid = Chroma(SchemeBuilder.Build(Night, ThemeMode.Dark, SchemeBuilder.MaxSaturation));

        Assert.True(muted < normal && normal < vivid, $"{muted} < {normal} < {vivid}");
        Assert.Throws<ArgumentOutOfRangeException>(() => SchemeBuilder.Build(Night, ThemeMode.Dark, 3));
    }

    [Fact]
    public void Writes_ghostty_and_wezterm_themes()
    {
        PywalWriter.Write(Scheme, "/w.jpg", _dir, templatesDirectory: null);

        string ghostty = File.ReadAllText(Path.Combine(_dir, "colors-ghostty"));
        Assert.Contains($"background = {Scheme.Background.Hex}\n", ghostty);
        Assert.Contains($"palette = 15={Scheme[15].Hex}\n", ghostty);

        string wezterm = File.ReadAllText(Path.Combine(_dir, "colors-wezterm.toml"));
        Assert.Contains($"ansi = [\"{Scheme[0].Hex}\", ", wezterm);
        Assert.Contains($"brights = [\"{Scheme[8].Hex}\", ", wezterm);
        Assert.Contains($"\"{Scheme[15].Hex}\"]\n", wezterm);
    }

    [Fact]
    public void Ghostty_is_only_reloaded_when_its_config_uses_tints_theme()
    {
        string config = Path.Combine(_dir, "config");
        File.WriteAllText(config, "font-size = 14\n");
        Assert.False(new GhosttyReloader([config]).UsesTintTheme());

        File.AppendAllText(config, "config-file = ~/.cache/wal/colors-ghostty\n");
        Assert.True(new GhosttyReloader([config]).UsesTintTheme());
    }

    [Fact]
    public void Apps_that_are_not_running_are_skipped()
    {
        var context = new ReloadContext(Scheme, "/w.jpg", _dir);

        // Nothing is called sketchybar/borders/ghostty on a build machine.
        Assert.All(
            new IReloader[] { new SketchyBarReloader(), new BordersReloader(Path.Combine(_dir, "none")), new GhosttyReloader([]) }
                .Select(r => r.Reload(context)),
            r => Assert.True(r.Ok && r.Skipped, $"{r.Name}: {r.Detail}"));
    }

    [Fact]
    public void Launch_agent_plist_is_valid_and_escapes_its_values()
    {
        string plist = LaunchAgent.Plist(
            ["/Users/me/tools & things/tint", "watch"],
            new Dictionary<string, string> { ["PATH"] = "/opt/homebrew/bin:/usr/bin" },
            "/Users/me/Library/Logs/tint.log");

        XDocument.Parse(plist); // well-formed
        Assert.Contains("<string>/Users/me/tools &amp; things/tint</string>", plist);
        Assert.Equal(["/Users/me/tools & things/tint", "watch"], LaunchAgent.ReadProgramArguments(plist));
        Assert.Contains($"<string>{LaunchAgent.Label}</string>", plist);
    }

    [Fact]
    public void Service_path_keeps_the_users_path_and_adds_homebrew_once()
    {
        string path = LaunchAgent.ServicePath("/Users/me/.local/bin:/usr/bin");

        Assert.StartsWith("/Users/me/.local/bin:/usr/bin:/opt/homebrew/bin", path);
        Assert.Single(path.Split(':'), p => p == "/usr/bin");
    }

    [Theory]
    [InlineData("\tstate = running\n\tpid = 4242\n", 4242)]
    [InlineData("\tstate = not running\n", null)]
    public void Reads_the_pid_from_launchctl_print(string output, int? pid) =>
        Assert.Equal(pid, LaunchAgent.ParsePid(output));
}
