using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Input.Platform;
using Avalonia.Interactivity;
using Avalonia.Media;
using Avalonia.Media.Imaging;
using Avalonia.Platform.Storage;
using Avalonia.Styling;
using Avalonia.Themes.Fluent;
using SixLabors.ImageSharp;
using SixLabors.ImageSharp.PixelFormats;
using SixLabors.ImageSharp.Processing;
using Tint.Core;
using Tint.Core.Imaging;
using Tint.Core.Palettes;
using Tint.Core.Reload;
using Tint.Core.Themes;
using Tint.Core.Wallpapers;
using Color = Avalonia.Media.Color;
using Rgb = Tint.Core.Colors.Rgb;

namespace Tint.App;

/// <summary>
/// The one window: an image on the left; its palette, the scheme made from it,
/// a terminal preview and the knobs on the right. The whole window takes the
/// scheme's colours, so what you see is what you'll get.
/// </summary>
public partial class MainWindow : Window
{
    private string? _image;
    private Palette? _palette;
    private Scheme? _scheme;
    private string? _currentWallpaper;

    public MainWindow()
    {
        InitializeComponent();

        TintSettings saved = TintSettings.Load();
        DarkMode.IsChecked = saved.Mode == ThemeMode.Dark;
        LightMode.IsChecked = saved.Mode == ThemeMode.Light;
        AutoMode.IsChecked = saved.Mode is null;
        SaturationSlider.Value = saved.Saturation;
        ShowSaturation();

        foreach (RadioButton mode in new[] { DarkMode, LightMode, AutoMode })
        {
            mode.IsCheckedChanged += (_, _) => Refresh();
        }

        SaturationSlider.ValueChanged += (_, _) =>
        {
            ShowSaturation();
            Refresh();
        };

        ImageFrame.AddHandler(DragDrop.DropEvent, OnDrop);
        CurrentButton.IsEnabled = OperatingSystem.IsMacOS();
        Opened += async (_, _) => await LoadCurrentWallpaperAsync();
    }

    /// <summary>The scheme on screen now; null until an image is loaded.</summary>
    internal Scheme? Scheme => _scheme;

    private ThemeMode? SelectedMode =>
        LightMode.IsChecked == true ? ThemeMode.Light : AutoMode.IsChecked == true ? null : ThemeMode.Dark;

    private double Saturation => Math.Round(SaturationSlider.Value, 2);

    /// <summary>Reads the image off the UI thread, then shows it and its scheme.</summary>
    internal async Task LoadImageAsync(string path)
    {
        Status.Text = $"Reading {Path.GetFileName(path)}…";
        try
        {
            (Bitmap preview, Palette palette) = await Task.Run(() => Read(path));
            (Preview.Source as IDisposable)?.Dispose();
            Preview.Source = preview;
            DropHint.IsVisible = false;
            _image = path;
            _palette = palette;
            FileName.Text = path;
            SetWallpaper.IsEnabled = OperatingSystem.IsMacOS() && path != _currentWallpaper;
            SetWallpaper.IsChecked = false;
            ApplyButton.IsEnabled = true;
            Status.Text = string.Empty;
            Refresh();
        }
        catch (Exception ex) when (ex is IOException or NotSupportedException or InvalidOperationException
            or UnauthorizedAccessException or ImageFormatException)
        {
            Status.Text = $"Couldn't read it: {ex.Message}";
        }
    }

    private static (Bitmap Preview, Palette Palette) Read(string path)
    {
        using Image<Rgb24> image = ImageLoader.Load(path);
        Palette palette = PaletteExtractor.FromImage(image);

        // A screen-sized copy for the preview; 6K wallpapers would be slow to draw.
        image.Mutate(ctx => ctx.Resize(new ResizeOptions { Size = new Size(1800, 1800), Mode = ResizeMode.Max }));
        using var png = new MemoryStream();
        image.SaveAsPng(png);
        png.Position = 0;
        return (new Bitmap(png), palette);
    }

    private async Task LoadCurrentWallpaperAsync()
    {
        if (!OperatingSystem.IsMacOS())
        {
            return;
        }

        _currentWallpaper = await Task.Run(() =>
        {
            using IWallpaperSource source = WallpaperSources.ForCurrentPlatform();
            return source.Current();
        });

        if (_currentWallpaper is null)
        {
            Status.Text = "Couldn't find the current wallpaper — open an image instead.";
            return;
        }

        await LoadImageAsync(_currentWallpaper);
    }

    /// <summary>Rebuilds the scheme from the palette with the current knobs, and repaints.</summary>
    private void Refresh()
    {
        if (_palette is null)
        {
            return;
        }

        ThemeMode mode = SelectedMode ?? (_palette.IsDark ? ThemeMode.Dark : ThemeMode.Light);
        _scheme = SchemeBuilder.Build(_palette, mode, Saturation);
        Paint(_palette, _scheme);
    }

    private void Paint(Palette palette, Scheme scheme)
    {
        RequestedThemeVariant = scheme.Mode == ThemeMode.Dark ? ThemeVariant.Dark : ThemeVariant.Light;
        Background = Brush(scheme.Background);
        Foreground = Brush(scheme.Foreground);
        Mood.Text = $"{(palette.IsDark ? "a dark" : "a light")} image → {(scheme.Mode == ThemeMode.Dark ? "dark" : "light")} scheme";

        // Palette: one bar per colour, as wide as its share of the image.
        PaletteStrip.Children.Clear();
        PaletteStrip.ColumnDefinitions.Clear();
        foreach ((Swatch swatch, int i) in palette.Swatches.OrderBy(s => s.Lab.L).Select((s, i) => (s, i)))
        {
            PaletteStrip.ColumnDefinitions.Add(new ColumnDefinition(swatch.Share, GridUnitType.Star));
            var bar = new Border { Background = Brush(swatch.Color) };
            ToolTip.SetTip(bar, $"{swatch.Color.Hex} · {swatch.Share:P0} of the image");
            Grid.SetColumn(bar, i);
            PaletteStrip.Children.Add(bar);
        }

        // Scheme: the 16 terminal colours, with their hex codes.
        SchemeGrid.Children.Clear();
        for (int i = 0; i < 16; i++)
        {
            SchemeGrid.Children.Add(Chip(scheme[i], i, scheme));
        }

        TerminalFrame.Background = Brush(scheme.Background);
        TerminalFrame.BorderBrush = Brush(scheme[8]);
        TerminalPreview.Fill(TerminalText, scheme);

        ApplyButton.Background = Brush(scheme[4]);
        ApplyButton.Foreground = Brush(scheme.Background);

        // Fluent's accent (radio buttons, the slider, focus rings) becomes the scheme's blue.
        if (Avalonia.Application.Current?.Styles.OfType<FluentTheme>().FirstOrDefault() is { } fluent)
        {
            Color accent = Brush(scheme[4]).Color;
            foreach (ThemeVariant variant in new[] { ThemeVariant.Dark, ThemeVariant.Light })
            {
                if (fluent.Palettes.TryGetValue(variant, out ColorPaletteResources? resources))
                {
                    resources.Accent = accent;
                }
                else
                {
                    fluent.Palettes[variant] = new ColorPaletteResources { Accent = accent };
                }
            }
        }
    }

    private Control Chip(Rgb color, int index, Scheme scheme)
    {
        var chip = new Button
        {
            Background = Brush(color),
            Height = 30,
            Margin = new Avalonia.Thickness(0, 0, 6, 0),
            HorizontalAlignment = Avalonia.Layout.HorizontalAlignment.Stretch,
            CornerRadius = new Avalonia.CornerRadius(6),
            BorderBrush = Brush(scheme[8]),
            BorderThickness = new Avalonia.Thickness(index == 0 ? 1 : 0),
        };
        ToolTip.SetTip(chip, $"color{index} {color.Hex}");
        chip.Click += async (_, _) =>
        {
            if (Clipboard is { } clipboard)
            {
                await clipboard.SetTextAsync(color.Hex);
                Status.Text = $"Copied color{index} {color.Hex}";
            }
        };

        var label = new TextBlock
        {
            Text = color.Hex[1..],
            FontSize = 10,
            Opacity = 0.6,
            Margin = new Avalonia.Thickness(0, 3, 6, 6),
            HorizontalAlignment = Avalonia.Layout.HorizontalAlignment.Center,
        };
        return new StackPanel { Children = { chip, label } };
    }

    private async void OnApply(object? sender, RoutedEventArgs e)
    {
        if (_image is null)
        {
            return;
        }

        string image = _image;
        bool setWallpaper = SetWallpaper.IsChecked == true && SetWallpaper.IsEnabled;
        var settings = new TintSettings { Mode = SelectedMode, Saturation = Saturation };
        var options = new ApplyOptions { Mode = settings.Mode, Saturation = settings.Saturation };

        ApplyButton.IsEnabled = false;
        Status.Text = "Applying…";
        try
        {
            ApplyResult result = await Task.Run(() =>
            {
                settings.Save();
                ApplyResult applied = ThemeApplier.Apply(image, options);

                // After applying, so a running `tint watch` finds this image
                // already themed and leaves it alone.
                if (setWallpaper)
                {
                    WallpaperSetter.Set(image);
                }

                return applied;
            });

            if (setWallpaper)
            {
                _currentWallpaper = image;
                SetWallpaper.IsEnabled = false;
                SetWallpaper.IsChecked = false;
            }

            Status.Text = Describe(result, setWallpaper);
        }
        catch (Exception ex) when (ex is IOException or NotSupportedException or InvalidOperationException
            or UnauthorizedAccessException or ImageFormatException or TimeoutException)
        {
            Status.Text = $"Couldn't apply: {ex.Message}";
        }
        finally
        {
            ApplyButton.IsEnabled = true;
        }
    }

    private static string Describe(ApplyResult result, bool setWallpaper)
    {
        var lines = new List<string> { $"✓ wrote {result.Written.Count} files to ~/.cache/wal" };
        if (setWallpaper)
        {
            lines.Add("✓ set as the wallpaper");
        }

        foreach (ReloadResult r in result.Reloads)
        {
            string mark = r.Skipped ? "·" : r.Ok ? "✓" : "✗";
            lines.Add($"{mark} {r.Name}: {r.Detail}");
        }

        lines.AddRange(result.Warnings.Select(w => $"! {w}"));
        return string.Join('\n', lines);
    }

    private async void OnOpenImage(object? sender, RoutedEventArgs e)
    {
        IReadOnlyList<IStorageFile> files = await StorageProvider.OpenFilePickerAsync(new FilePickerOpenOptions
        {
            Title = "Choose an image",
            AllowMultiple = false,
            FileTypeFilter = [FilePickerFileTypes.ImageAll, new FilePickerFileType("HEIC") { Patterns = ["*.heic", "*.heif"] }],
        });

        if (files is [IStorageFile file] && file.TryGetLocalPath() is { } path)
        {
            await LoadImageAsync(path);
        }
    }

    private async void OnCurrentWallpaper(object? sender, RoutedEventArgs e) => await LoadCurrentWallpaperAsync();

    private async void OnDrop(object? sender, DragEventArgs e)
    {
        if (e.DataTransfer.TryGetFiles() is [IStorageItem item, ..] && item.TryGetLocalPath() is { } path)
        {
            await LoadImageAsync(path);
        }
    }

    private void ShowSaturation() => SaturationValue.Text = $"{Saturation:0.00}×";

    internal static SolidColorBrush Brush(Rgb c) => new(Color.FromRgb(c.R, c.G, c.B));
}
