using System.Text.Json;
using Tint.Core.Colors;
using Tint.Core.Output;
using Tint.Core.Palettes;
using Tint.Core.Reload;
using Tint.Core.Themes;

namespace Tint.Core.Tests;

public sealed class OutputTests : IDisposable
{
    private static readonly string Fixtures = Path.Combine(AppContext.BaseDirectory, "Fixtures", "templates");

    private static readonly Scheme Scheme = SchemeBuilder.Build(
        new Palette([.. new[] { "#1b2233", "#48596f", "#c68a65", "#d8f4ff", "#6d9c5a", "#b8455a" }
            .Select(h => new Swatch(Rgb.FromHex(h), 1.0 / 6))]),
        ThemeMode.Dark);

    private readonly string _dir = Directory.CreateTempSubdirectory("tint-out-").FullName;

    public void Dispose() => Directory.Delete(_dir, recursive: true);

    [Theory]
    [InlineData("{color4}", "#")]
    [InlineData("{color4.strip}", "")]
    public void Colour_placeholders_render_as_hex(string template, string prefix)
    {
        string rendered = TemplateRenderer.Render(template, Scheme, "/w.jpg").Text;

        Assert.Equal(prefix + Scheme[4].Hex[1..], rendered);
    }

    [Fact]
    public void Modifiers_braces_and_specials_render_like_pywal()
    {
        Rgb bg = Scheme.Background;
        string rendered = TemplateRenderer.Render(
            "{{ {background.rgb} | {background.xrgba} | {wallpaper} | {alpha} | {alpha.decimal} }}", Scheme, "/w.jpg").Text;

        Assert.Equal($"{{ {bg.R},{bg.G},{bg.B} | {bg.R:x2}/{bg.G:x2}/{bg.B:x2}/ff | /w.jpg | 100 | 1.0 }}", rendered);
    }

    [Fact]
    public void Unknown_placeholders_are_kept_and_reported()
    {
        TemplateRenderer.Result result = TemplateRenderer.Render("a {color4.lighten(0.2)} b {nope}", Scheme, "/w.jpg");

        Assert.Equal("a {color4.lighten(0.2)} b {nope}", result.Text);
        Assert.Equal(["{color4.lighten(0.2)}", "{nope}"], result.Unknown);
    }

    [Fact]
    public void The_real_hyprland_template_renders_completely()
    {
        TemplateRenderer.Result result = TemplateRenderer.Render(
            File.ReadAllText(Path.Combine(Fixtures, "hyprland-colors.conf")), Scheme, "/w.jpg");

        Assert.Empty(result.Unknown);
        Assert.Contains($"col.active_border = rgba({Scheme[4].Hex[1..]}ee) rgba({Scheme[6].Hex[1..]}ee) 45deg", result.Text);
        Assert.Contains("general {\n", result.Text);
    }

    [Fact]
    public void The_real_caelestia_template_renders_to_valid_json()
    {
        TemplateRenderer.Result result = TemplateRenderer.Render(
            File.ReadAllText(Path.Combine(Fixtures, "caelestia-scheme.json")), Scheme, "/w.jpg");

        Assert.Empty(result.Unknown);
        using JsonDocument json = JsonDocument.Parse(result.Text);
        Assert.Equal(Scheme[4].Hex[1..], json.RootElement.GetProperty("colours").GetProperty("primary").GetString());
    }

    [Fact]
    public void Writes_every_pywal_file_plus_templates()
    {
        PywalWriter.Result result = PywalWriter.Write(Scheme, "/walls/city.jpg", _dir, Fixtures);

        string[] expected =
        [
            "wal", "colors", "colors.json", "colors.sh", "colors.css", "colors-waybar.css", "colors-kitty.conf",
            "colors-wal.vim", "caelestia-scheme.json", "hyprland-colors.conf",
        ];
        Assert.Equal(expected.Order(), result.Written.Select(Path.GetFileName).Order()!);
        Assert.Empty(result.Warnings);
        Assert.DoesNotContain(Directory.EnumerateFiles(_dir), f => f.EndsWith(".tmp", StringComparison.Ordinal));
    }

    [Fact]
    public void Colors_json_has_pywals_structure()
    {
        PywalWriter.Write(Scheme, "/walls/city.jpg", _dir, templatesDirectory: null);

        using JsonDocument json = JsonDocument.Parse(File.ReadAllText(Path.Combine(_dir, "colors.json")));
        JsonElement root = json.RootElement;
        Assert.Equal("/walls/city.jpg", root.GetProperty("wallpaper").GetString());
        Assert.Equal(Scheme.Background.Hex, root.GetProperty("special").GetProperty("background").GetString());
        Assert.Equal(Scheme[15].Hex, root.GetProperty("colors").GetProperty("color15").GetString());
    }

    [Fact]
    public void Vim_and_plain_colour_files_match_pywals_format()
    {
        PywalWriter.Write(Scheme, "/walls/city.jpg", _dir, templatesDirectory: null);

        string vim = File.ReadAllText(Path.Combine(_dir, "colors-wal.vim"));
        Assert.Contains($"let color0  = \"{Scheme[0].Hex}\"", vim);
        Assert.Contains($"let color10 = \"{Scheme[10].Hex}\"", vim);
        Assert.Contains($"let background = \"{Scheme.Background.Hex}\"", vim);

        string[] lines = File.ReadAllLines(Path.Combine(_dir, "colors"));
        Assert.Equal(Scheme.Colors.Select(c => c.Hex), lines);
        Assert.Equal("/walls/city.jpg", File.ReadAllText(Path.Combine(_dir, "wal")));
    }

    [Fact]
    public void Shell_file_quotes_awkward_wallpaper_paths()
    {
        PywalWriter.Write(Scheme, "/walls/it's here.jpg", _dir, templatesDirectory: null);

        Assert.Contains("wallpaper='/walls/it'\\''s here.jpg'", File.ReadAllText(Path.Combine(_dir, "colors.sh")));
    }

    [Fact]
    public void Hook_runs_with_the_wallpaper_and_mode_in_its_environment()
    {
        if (OperatingSystem.IsWindows())
        {
            return;
        }

        string hooks = Directory.CreateDirectory(Path.Combine(_dir, "hooks")).FullName;
        string outFile = Path.Combine(_dir, "hook-ran.txt");
        string hook = Path.Combine(hooks, "post-apply");
        File.WriteAllText(hook, $"#!/bin/sh\necho \"$TINT_WALLPAPER|$TINT_MODE|$TINT_CACHE\" > '{outFile}'\n");
        File.SetUnixFileMode(hook, UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute);

        ReloadResult result = new HookReloader(hooks).Reload(new ReloadContext(Scheme, "/walls/city.jpg", _dir));

        Assert.True(result is { Ok: true, Skipped: false }, result.Detail);
        Assert.Equal($"/walls/city.jpg|dark|{_dir}", File.ReadAllText(outFile).Trim());
    }

    [Fact]
    public void A_non_executable_hook_is_reported_not_run()
    {
        if (OperatingSystem.IsWindows())
        {
            return;
        }

        string hooks = Directory.CreateDirectory(Path.Combine(_dir, "hooks")).FullName;
        string hook = Path.Combine(hooks, "post-apply");
        File.WriteAllText(hook, "#!/bin/sh\nexit 0\n");
        File.SetUnixFileMode(hook, UnixFileMode.UserRead | UnixFileMode.UserWrite);

        ReloadResult result = new HookReloader(hooks).Reload(new ReloadContext(Scheme, "/w.jpg", _dir));

        Assert.False(result.Ok);
        Assert.Contains("chmod +x", result.Detail, StringComparison.Ordinal);
    }

    [Fact]
    public void No_hook_is_simply_skipped()
    {
        ReloadResult result = new HookReloader(Path.Combine(_dir, "none")).Reload(new ReloadContext(Scheme, "/w.jpg", _dir));

        Assert.True(result is { Ok: true, Skipped: true });
    }
}
