using System.Globalization;
using System.Text;
using System.Text.Json;
using Tint.Core.Themes;
using Tint.Core.Util;

namespace Tint.Core;

/// <summary>
/// The defaults <c>tint apply</c> and <c>tint watch</c> use when no option is
/// given, saved in <c>~/.config/tint/settings.json</c>. The desktop app writes
/// them, so a mode picked there sticks for the login service too.
/// </summary>
public sealed record TintSettings
{
    /// <summary>Dark or light; null picks from the image's brightness ("auto").</summary>
    public ThemeMode? Mode { get; init; } = ThemeMode.Dark;

    /// <summary>Accent saturation, see <see cref="SchemeBuilder.Build"/>.</summary>
    public double Saturation { get; init; } = 1;

    public static string DefaultPath => Path.Combine(TintPaths.Config, "settings.json");

    /// <summary>"dark", "light" or "auto".</summary>
    public static string ModeName(ThemeMode? mode) => mode switch
    {
        ThemeMode.Dark => "dark",
        ThemeMode.Light => "light",
        _ => "auto",
    };

    /// <summary>The reverse of <see cref="ModeName"/>; anything unknown is dark.</summary>
    public static ThemeMode? ParseMode(string? name) => name switch
    {
        "light" => ThemeMode.Light,
        "auto" => null,
        _ => ThemeMode.Dark,
    };

    /// <summary>Reads the settings. A missing or broken file gives the defaults: settings must never stop a theme.</summary>
    public static TintSettings Load(string? path = null)
    {
        path ??= DefaultPath;
        var settings = new TintSettings();
        if (!File.Exists(path))
        {
            return settings;
        }

        try
        {
            using JsonDocument json = JsonDocument.Parse(File.ReadAllText(path));
            JsonElement root = json.RootElement;
            if (root.TryGetProperty("mode", out JsonElement mode) && mode.ValueKind == JsonValueKind.String)
            {
                settings = settings with { Mode = ParseMode(mode.GetString()) };
            }

            if (root.TryGetProperty("saturation", out JsonElement saturation) && saturation.TryGetDouble(out double value))
            {
                settings = settings with { Saturation = Math.Clamp(value, SchemeBuilder.MinSaturation, SchemeBuilder.MaxSaturation) };
            }
        }
        catch (Exception ex) when (ex is JsonException or IOException or UnauthorizedAccessException or InvalidOperationException)
        {
            // Fall back to the defaults.
        }

        return settings;
    }

    public void Save(string? path = null)
    {
        path ??= DefaultPath;
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);

        using var stream = new MemoryStream();
        using (var json = new Utf8JsonWriter(stream, new JsonWriterOptions { Indented = true }))
        {
            json.WriteStartObject();
            json.WriteString("mode", ModeName(Mode));
            json.WriteNumber("saturation", Math.Round(Saturation, 2));
            json.WriteEndObject();
        }

        File.WriteAllText(path, Encoding.UTF8.GetString(stream.ToArray()) + "\n");
    }

    public override string ToString() =>
        $"{ModeName(Mode)}, saturation {Saturation.ToString("0.##", CultureInfo.InvariantCulture)}";
}
