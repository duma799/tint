using System.Globalization;
using System.Text;
using Tint.Core.Colors;
using Tint.Core.Themes;

namespace Tint.Core.Output;

/// <summary>
/// Renders pywal-style templates, so existing <c>~/.config/wal/templates</c>
/// keep working unchanged.
/// </summary>
/// <remarks>
/// Syntax (Python <c>str.format</c>, as pywal uses):
/// <list type="bullet">
/// <item><c>{color4}</c> → <c>#1b2233</c>; also <c>background</c>, <c>foreground</c>, <c>cursor</c>, <c>color0</c>–<c>color15</c></item>
/// <item><c>{color4.strip}</c> → <c>1b2233</c>, <c>.rgb</c> → <c>27,34,51</c>, <c>.rgba</c> → <c>27,34,51,1.0</c>,
/// <c>.xrgba</c> → <c>1b/22/33/ff</c>, <c>.red</c>/<c>.green</c>/<c>.blue</c> → <c>0.106</c></item>
/// <item><c>{wallpaper}</c>, <c>{alpha}</c> (<c>100</c>), <c>{alpha.decimal}</c> (<c>1.0</c>)</item>
/// <item><c>{{</c> and <c>}}</c> → literal braces</item>
/// </list>
/// Anything unrecognised is left exactly as written and reported.
/// </remarks>
public static class TemplateRenderer
{
    public sealed record Result(string Text, IReadOnlyList<string> Unknown);

    public static Result Render(string template, Scheme scheme, string wallpaper)
    {
        var output = new StringBuilder(template.Length + 256);
        var unknown = new List<string>();

        for (int i = 0; i < template.Length; i++)
        {
            char c = template[i];
            bool next(char expected) => i + 1 < template.Length && template[i + 1] == expected;

            if (c == '{' && next('{'))
            {
                output.Append('{');
                i++;
            }
            else if (c == '}' && next('}'))
            {
                output.Append('}');
                i++;
            }
            else if (c == '{')
            {
                int close = template.IndexOf('}', i + 1);
                string token = close < 0 ? string.Empty : template[(i + 1)..close];
                string? value = close < 0 ? null : Resolve(token, scheme, wallpaper);
                if (value is null)
                {
                    // Not ours: keep it verbatim, so nothing is silently mangled.
                    unknown.Add(close < 0 ? template[i..Math.Min(template.Length, i + 20)] : $"{{{token}}}");
                    output.Append(c);
                    continue;
                }

                output.Append(value);
                i = close;
            }
            else
            {
                output.Append(c);
            }
        }

        return new Result(output.ToString(), unknown);
    }

    private static string? Resolve(string token, Scheme scheme, string wallpaper)
    {
        int dot = token.IndexOf('.');
        string name = dot < 0 ? token : token[..dot];
        string? modifier = dot < 0 ? null : token[(dot + 1)..];

        switch (name)
        {
            case "wallpaper" when modifier is null:
                return wallpaper;
            case "alpha" when modifier is null:
                return "100";
            case "alpha" when modifier == "decimal":
                return "1.0";
        }

        Rgb? color = name switch
        {
            "background" => scheme.Background,
            "foreground" => scheme.Foreground,
            "cursor" => scheme.Cursor,
            _ when name.StartsWith("color", StringComparison.Ordinal)
                && int.TryParse(name.AsSpan(5), NumberStyles.None, CultureInfo.InvariantCulture, out int n)
                && n is >= 0 and < 16 => scheme[n],
            _ => null,
        };

        return color is { } rgb ? Format(rgb, modifier) : null;
    }

    private static string? Format(Rgb c, string? modifier) => modifier switch
    {
        null => c.Hex,
        "strip" => c.Hex[1..],
        "rgb" => $"{c.R},{c.G},{c.B}",
        "rgba" => $"{c.R},{c.G},{c.B},1.0",
        "xrgba" => $"{c.R:x2}/{c.G:x2}/{c.B:x2}/ff",
        "red" => Unit(c.R),
        "green" => Unit(c.G),
        "blue" => Unit(c.B),
        _ => null,
    };

    private static string Unit(byte channel) => (channel / 255.0).ToString("0.000", CultureInfo.InvariantCulture);
}
