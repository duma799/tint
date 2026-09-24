using Tint.Core.Output;
using Tint.Core.Palettes;
using Tint.Core.Reload;
using Tint.Core.Themes;
using Tint.Core.Util;

namespace Tint.Core;

public sealed record ApplyOptions
{
    /// <summary>Dark or light scheme; null picks from the image's brightness.</summary>
    public ThemeMode? Mode { get; init; } = ThemeMode.Dark;

    /// <summary>Accent saturation, 0.5–1.5; see <see cref="SchemeBuilder.Build"/>.</summary>
    public double Saturation { get; init; } = 1;

    /// <summary>Tell apps to reload. Off: only write the files.</summary>
    public bool Reload { get; init; } = true;

    public string CacheDirectory { get; init; } = TintPaths.WalCache;

    public string? TemplatesDirectory { get; init; } = TintPaths.WalTemplates;
}

public sealed record ApplyResult(
    Palette Palette,
    Scheme Scheme,
    IReadOnlyList<string> Written,
    IReadOnlyList<string> Warnings,
    IReadOnlyList<ReloadResult> Reloads);

/// <summary>The whole of <c>tint apply</c>: image → palette → scheme → files → app reloads.</summary>
public static class ThemeApplier
{
    public static ApplyResult Apply(string imagePath, ApplyOptions? options = null, IReadOnlyList<IReloader>? reloaders = null)
    {
        options ??= new ApplyOptions();
        string wallpaper = Path.GetFullPath(imagePath);

        Palette palette = PaletteExtractor.FromFile(wallpaper);
        ThemeMode mode = options.Mode ?? (palette.IsDark ? ThemeMode.Dark : ThemeMode.Light);
        Scheme scheme = SchemeBuilder.Build(palette, mode, options.Saturation);

        PywalWriter.Result files = PywalWriter.Write(scheme, wallpaper, options.CacheDirectory, options.TemplatesDirectory);

        var context = new ReloadContext(scheme, wallpaper, options.CacheDirectory);
        ReloadResult[] reloads = options.Reload
            ? [.. (reloaders ?? Reloaders.ForCurrentPlatform()).Select(r => r.Reload(context))]
            : [];

        return new ApplyResult(palette, scheme, files.Written, files.Warnings, reloads);
    }

    /// <summary>The image the current theme was made from (pywal's <c>wal</c> file), or null.</summary>
    public static string? LastApplied(string? cacheDirectory = null)
    {
        string file = Path.Combine(cacheDirectory ?? TintPaths.WalCache, "wal");
        try
        {
            return File.Exists(file) ? File.ReadAllText(file).Trim() : null;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            return null;
        }
    }
}
