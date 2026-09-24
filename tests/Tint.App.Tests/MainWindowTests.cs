using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.Primitives;
using Avalonia.Headless;
using Avalonia.Media.Imaging;
using SixLabors.ImageSharp;
using SixLabors.ImageSharp.PixelFormats;
using Tint.Core.Themes;

namespace Tint.App.Tests;

/// <summary>The same app, run without a screen: Skia still draws, so frames can be captured.</summary>
public static class TestApp
{
    public static AppBuilder BuildAvaloniaApp() =>
        AppBuilder.Configure<App>()
            .UseSkia()
            .WithInterFont()
            .UseHeadless(new AvaloniaHeadlessPlatformOptions { UseHeadlessDrawing = false });
}

public sealed class MainWindowTests : IDisposable
{
    private static readonly HeadlessUnitTestSession Session = HeadlessUnitTestSession.StartNew(typeof(TestApp));

    private readonly string _dir = Directory.CreateTempSubdirectory("tint-app-").FullName;

    public void Dispose() => Directory.Delete(_dir, recursive: true);

    // Dispatch needs a Func<Task<T>>: an async lambda with no result would
    // bind to Action and run as async void, and the test would end early.
    [Fact]
    public Task Shows_the_scheme_of_a_loaded_image_and_follows_the_mode() => Session.Dispatch(async () =>
    {
        // TINT_SCREENSHOT_IMAGE: render a real wallpaper instead of the made-up one.
        string image = Environment.GetEnvironmentVariable("TINT_SCREENSHOT_IMAGE") ?? Sunset(Path.Combine(_dir, "sunset.png"));
        var window = new MainWindow(loadWallpaper: false);
        window.Show();

        await window.LoadImageAsync(image);

        Assert.NotNull(window.Scheme);
        Assert.Equal(ThemeMode.Dark, window.Scheme.Mode);
        Assert.Equal(16, window.FindControl<UniformGrid>("SchemeGrid")!.Children.Count);
        Assert.True(window.FindControl<Button>("ApplyButton")!.IsEnabled);
        Capture(window, "dark");

        window.FindControl<RadioButton>("LightMode")!.IsChecked = true;

        Assert.Equal(ThemeMode.Light, window.Scheme!.Mode);
        Capture(window, "light");
        window.Close();
        return true;
    }, CancellationToken.None);

    [Fact]
    public Task A_file_that_is_not_an_image_is_reported() => Session.Dispatch(async () =>
    {
        string text = Path.Combine(_dir, "notes.txt");
        await File.WriteAllTextAsync(text, "hello");
        var window = new MainWindow(loadWallpaper: false);
        window.Show();

        await window.LoadImageAsync(text);

        Assert.Null(window.Scheme);
        Assert.StartsWith("Couldn't read it", window.FindControl<TextBlock>("Status")!.Text, StringComparison.Ordinal);
        window.Close();
        return true;
    }, CancellationToken.None);

    /// <summary>TINT_SCREENSHOTS=dir saves what the window looks like.</summary>
    private static void Capture(Window window, string name)
    {
        if (Environment.GetEnvironmentVariable("TINT_SCREENSHOTS") is { Length: > 0 } dir)
        {
            Directory.CreateDirectory(dir);
            WriteableBitmap? frame = window.CaptureRenderedFrame();
            Assert.NotNull(frame);
            frame.Save(Path.Combine(dir, $"app-{name}.png"), PngBitmapEncoderOptions.Default);
        }
    }

    /// <summary>A small made-up wallpaper: night sky over a warm horizon and green hills.</summary>
    private static string Sunset(string path)
    {
        using var image = new Image<Rgb24>(320, 200);
        image.ProcessPixelRows(rows =>
        {
            for (int y = 0; y < rows.Height; y++)
            {
                Span<Rgb24> row = rows.GetRowSpan(y);
                for (int x = 0; x < row.Length; x++)
                {
                    double t = y / (double)rows.Height;
                    bool hill = y > 150 + (int)(18 * Math.Sin(x / 30.0));
                    row[x] = hill ? new Rgb24(40, (byte)(90 + x / 8), 60)
                        : t < 0.5 ? new Rgb24((byte)(20 + 60 * t), (byte)(25 + 30 * t), (byte)(60 + 80 * t))
                        : new Rgb24((byte)(200 + 50 * (t - 0.5)), (byte)(110 + 60 * (t - 0.5)), (byte)(90 - 40 * t));
                }
            }
        });
        image.SaveAsPng(path);
        return path;
    }
}
