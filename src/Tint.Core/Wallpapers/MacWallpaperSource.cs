using System.Runtime.Versioning;
using Tint.Core.Util;
using static Tint.Core.Wallpapers.MacWallpaperStore;

namespace Tint.Core.Wallpapers;

/// <summary>
/// macOS. Changing the wallpaper rewrites
/// <c>~/Library/Application Support/com.apple.wallpaper/Store/Index.plist</c>,
/// which is the signal to look again. The image comes from, in order:
/// System Events; the file URL inside Index.plist; and, for wallpapers with no
/// file (built-in extension wallpapers), the snapshot macOS rendered of it.
/// </summary>
/// <remarks>
/// The first run may ask for permission for your terminal to control
/// "System Events", and to access data from other apps (the snapshot cache
/// belongs to the wallpaper service).
/// </remarks>
[SupportedOSPlatform("macos")]
public sealed class MacWallpaperSource(TimeProvider? timeProvider = null) : WatchedWallpaperSource(timeProvider)
{
    /// <summary>What AppleScript prints for "nothing" — not a path.</summary>
    private const string AppleScriptNull = "missing value";

    private static readonly string StoreDirectory = Path.Combine(
        TintPaths.Home,
        "Library", "Application Support", "com.apple.wallpaper");

    /// <summary>
    /// Where the wallpaper service keeps rendered snapshots of each wallpaper,
    /// one folder per provider (<c>extension-&lt;provider id&gt;</c>).
    /// </summary>
    private static readonly string SnapshotCacheDirectory = Path.Combine(
        TintPaths.Home,
        "Library", "Containers", "com.apple.wallpaper.agent", "Data", "Library", "Caches", "com.apple.wallpaper.caches");

    public override string Name => "macOS";

    protected override string WatchDirectory => StoreDirectory;

    // A snapshot can land a moment after Index.plist changes; watching the cache
    // too means that late render still triggers a re-check.
    protected override IEnumerable<string> ExtraWatchDirectories => [SnapshotCacheDirectory];

    public override string? Current()
    {
        string? fromSystemEvents = QuerySystemEvents();
        if (fromSystemEvents is not null && File.Exists(fromSystemEvents))
        {
            return fromSystemEvents;
        }

        OnTrace("System Events has no file path for this wallpaper; reading Index.plist");
        StoreChoice store = ReadStore();
        if (store.File is not null && File.Exists(store.File))
        {
            return store.File;
        }

        // No image file at all (e.g. macOS 26 extension wallpapers like Neptune,
        // which are drawn by code): use the snapshot macOS rendered of it.
        if (store.Provider is not null)
        {
            foreach (string folder in SnapshotFolderNames(store.Provider))
            {
                string? snapshot = NewestSnapshot(Path.Combine(SnapshotCacheDirectory, folder));
                if (snapshot is not null)
                {
                    OnTrace($"using macOS's rendered snapshot: {snapshot}");
                    return snapshot;
                }
            }
        }

        OnNotice(store.Provider is null
            ? "couldn't find an image file for the current wallpaper."
            : $"the current wallpaper is {Describe(store.Provider)}, and macOS hasn't saved a snapshot of it yet — " +
              "there's nothing to take colours from. Choose a photo or picture as the wallpaper and tint will pick it up.");
        return null;
    }

    private string? QuerySystemEvents()
    {
        ProcessResult result = ProcessRunner.Run(
            "osascript",
            ["-e", "tell application \"System Events\" to get picture of current desktop"]);

        if (!result.Succeeded)
        {
            OnTrace($"osascript failed ({result.ExitCode}): {result.StdErr}");
            return null;
        }

        string output = result.StdOut;
        return output.Length == 0 || output == AppleScriptNull ? null : output;
    }

    private StoreChoice ReadStore()
    {
        string index = Path.Combine(StoreDirectory, "Store", "Index.plist");
        if (!File.Exists(index))
        {
            OnTrace($"{index} not found");
            return new StoreChoice(null, null);
        }

        string? xml = PlistToXml(index);
        if (xml is null)
        {
            return new StoreChoice(null, null);
        }

        StoreChoice choice = PickDesktopChoice(FlattenPlist(xml));

        // A picture's path isn't in "Files" but in "Configuration": a second
        // binary plist nested inside the first. Unpack that one too.
        if (choice.File is null && choice.Configuration is { Length: > 0 } configuration)
        {
            string temp = Path.Combine(Path.GetTempPath(), $"tint-{Guid.NewGuid():N}.plist");
            try
            {
                File.WriteAllBytes(temp, configuration);
                string? nested = PlistToXml(temp);
                if (nested is not null)
                {
                    choice = choice with { File = FindFileUrl(FlattenPlist(nested)) };
                }
            }
            finally
            {
                File.Delete(temp);
            }
        }

        OnTrace($"Index.plist → file: {choice.File ?? "none"}, provider: {choice.Provider ?? "none"}");
        return choice;
    }

    /// <summary>Binary plist → XML, via plutil (built into macOS).</summary>
    private string? PlistToXml(string path)
    {
        ProcessResult result = ProcessRunner.Run("plutil", ["-convert", "xml1", "-o", "-", path]);
        if (!result.Succeeded)
        {
            OnTrace($"plutil failed on {Path.GetFileName(path)}: {result.StdErr}");
            return null;
        }

        return result.StdOut;
    }

    private static string Describe(string provider) => provider switch
    {
        _ when provider.Contains("aerial", StringComparison.OrdinalIgnoreCase) => "an aerial video",
        _ when provider.Contains("color", StringComparison.OrdinalIgnoreCase) => "a solid colour",
        _ when provider.Contains("image", StringComparison.OrdinalIgnoreCase) => "a picture tint couldn't locate",
        _ => $"a built-in dynamic wallpaper ({provider})",
    };
}
