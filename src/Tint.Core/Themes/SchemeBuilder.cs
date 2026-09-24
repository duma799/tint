using Tint.Core.Colors;
using Tint.Core.Palettes;

namespace Tint.Core.Themes;

/// <summary>
/// Turns a palette into a <see cref="Scheme"/>. Two things pywal doesn't do:
/// accents are matched to their terminal role by hue (the reddest colour goes
/// in the red slot, and so on), and every colour is nudged until it is
/// readable against the background.
/// </summary>
public static class SchemeBuilder
{
    /// <summary>Hue each ANSI slot (1–6) aims for, in Lab degrees.</summary>
    private static readonly double[] SlotHues =
    [
        30, // red
        135, // green
        95, // yellow
        280, // blue
        330, // magenta
        200, // cyan
    ];

    /// <summary>Lowest and highest <c>saturation</c> accepted by <see cref="Build"/>.</summary>
    public const double MinSaturation = 0.5;

    public const double MaxSaturation = 1.5;

    /// <param name="saturation">
    /// Scales how colourful the accents are: 1 keeps the image's own colours,
    /// 0.5 is muted, 1.5 vivid. Contrast is still checked afterwards.
    /// </param>
    public static Scheme Build(Palette palette, ThemeMode mode, double saturation = 1)
    {
        if (saturation is < MinSaturation or > MaxSaturation || double.IsNaN(saturation))
        {
            throw new ArgumentOutOfRangeException(nameof(saturation), $"Saturation must be between {MinSaturation} and {MaxSaturation}.");
        }

        if (palette.Swatches.Count == 0)
        {
            throw new ArgumentException("The palette has no colours.", nameof(palette));
        }

        bool dark = mode == ThemeMode.Dark;
        Lab[] labs = [.. palette.Swatches.Select(s => s.Lab)];
        Lab darkest = labs.MinBy(l => l.L);
        Lab lightest = labs.MaxBy(l => l.L);

        // Background and foreground keep a hint of the image's tint, but only a
        // hint: strongly coloured backgrounds make every other colour muddy.
        Lab backgroundLab = dark
            ? (darkest with { L = Math.Min(darkest.L, 12) }).WithMaxChroma(12)
            : (lightest with { L = Math.Max(lightest.L, 94) }).WithMaxChroma(8);
        Rgb background = backgroundLab.ToRgb();

        Lab foregroundLab = dark
            ? (lightest with { L = Math.Max(lightest.L, 88) }).WithMaxChroma(10)
            : (darkest with { L = Math.Min(darkest.L, 22) }).WithMaxChroma(12);
        Rgb foreground = Readable(foregroundLab, background, Contrast.Enhanced, dark);

        // Accents stay in a mid-lightness band, so none reads as black (on a
        // light theme) or white (on a dark one) — a navy "blue" is still blue.
        Lab[] accents = [.. PickAccents(labs, backgroundLab, foregroundLab)
            .Select(a => a with
            {
                L = dark ? Math.Min(a.L, 78) : Math.Max(a.L, 40),
                A = a.A * saturation,
                B = a.B * saturation,
            })];

        var colors = new Rgb[16];
        colors[0] = background;
        for (int i = 0; i < 6; i++)
        {
            colors[i + 1] = Readable(accents[i], background, Contrast.Text, dark);
            Lab bright = accents[i] with { L = Math.Clamp(accents[i].L + (dark ? 8 : -8), 0, 100) };
            colors[i + 9] = Readable(bright, background, Contrast.Text, dark);
        }

        colors[7] = Readable(foregroundLab with { L = foregroundLab.L + (dark ? -12 : 12) }, background, Contrast.Text, dark);
        colors[8] = Readable(backgroundLab with { L = backgroundLab.L + (dark ? 18 : -18) }, background, Contrast.Large, dark);
        colors[15] = foreground;

        return new Scheme(background, foreground, foreground, colors, mode);
    }

    /// <summary>
    /// Six accent colours, one per ANSI slot. The image's most colourful,
    /// mutually distinct colours are matched to the slot whose hue they're
    /// closest to; any slot left over gets a colour made from the image's
    /// average tint at that slot's hue, so monochrome wallpapers still yield a
    /// usable scheme.
    /// </summary>
    private static Lab[] PickAccents(Lab[] labs, Lab background, Lab foreground)
    {
        const double MinChroma = 12;
        const double MinDistance = 12;

        // A colour this far from a slot's hue would change its meaning (a brown
        // "blue" makes `ls` folders brown), so that slot gets a made colour instead.
        const double MaxHueDistance = 70;

        var candidates = new List<Lab>();
        foreach (Lab lab in labs.OrderByDescending(l => l.Chroma))
        {
            if (lab.Chroma < MinChroma
                || lab.DistanceTo(background) < MinDistance
                || lab.DistanceTo(foreground) < MinDistance
                || candidates.Any(c => c.DistanceTo(lab) < MinDistance))
            {
                continue;
            }

            candidates.Add(lab);
        }

        // Greedy matching: the closest (slot, colour) pairs by hue go first.
        var accents = new Lab?[6];
        var used = new bool[candidates.Count];
        var pairs =
            from slot in Enumerable.Range(0, 6)
            from index in Enumerable.Range(0, candidates.Count)
            let distance = HueDistance(candidates[index].Hue, SlotHues[slot])
            where distance <= MaxHueDistance
            orderby distance, slot, index
            select (slot, index);

        foreach ((int slot, int index) in pairs)
        {
            if (accents[slot] is null && !used[index])
            {
                accents[slot] = candidates[index];
                used[index] = true;
            }
        }

        // Fill empty slots from the image's overall character: its typical
        // lightness and a modest chroma, at the slot's own hue.
        double lightness = candidates.Count > 0 ? candidates.Average(c => c.L) : 65;
        double chroma = Math.Clamp(candidates.Count > 0 ? candidates.Average(c => c.Chroma) : 25, 20, 45);

        Lab[] result = new Lab[6];
        for (int slot = 0; slot < 6; slot++)
        {
            result[slot] = accents[slot] ?? Lab.FromLch(lightness, chroma, SlotHues[slot]);
        }

        return result;
    }

    /// <summary>
    /// Moves <paramref name="color"/> lighter (dark themes) or darker (light
    /// themes) until it reaches <paramref name="minRatio"/> against the
    /// background. Hue and chroma are kept, so it's the same colour, just legible.
    /// </summary>
    private static Rgb Readable(Lab color, Rgb background, double minRatio, bool lighten)
    {
        Lab current = color with { L = Math.Clamp(color.L, 0, 100) };
        for (int step = 0; step <= 100; step++)
        {
            Rgb rgb = current.ToRgb();
            if (Contrast.Ratio(rgb, background) >= minRatio)
            {
                return rgb;
            }

            double l = current.L + (lighten ? 1 : -1);
            if (l is < 0 or > 100)
            {
                break;
            }

            current = current with { L = l };
        }

        // Out of room at the end of the lightness scale: fall back to plain white/black.
        return lighten ? new Rgb(255, 255, 255) : new Rgb(0, 0, 0);
    }

    private static double HueDistance(double a, double b)
    {
        double d = Math.Abs(a - b) % 360;
        return d > 180 ? 360 - d : d;
    }
}
