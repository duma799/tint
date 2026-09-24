using System.Runtime.Versioning;
using Tint.Core.Util;

namespace Tint.Core.Wallpapers;

/// <summary>
/// macOS. Recent versions keep wallpaper settings under
/// <c>~/Library/Application Support/com.apple.wallpaper</c>; changing the
/// wallpaper rewrites files there, which is the signal to look again. The path
/// itself comes from System Events via <c>osascript</c>.
/// </summary>
/// <remarks>
/// The first run asks for permission for your terminal to control
/// "System Events" (System Settings → Privacy &amp; Security → Automation).
/// </remarks>
[SupportedOSPlatform("macos")]
public sealed class MacWallpaperSource(TimeProvider? timeProvider = null) : WatchedWallpaperSource(timeProvider)
{
    public override string Name => "macOS";

    protected override string WatchDirectory => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
        "Library", "Application Support", "com.apple.wallpaper");

    public override string? Current()
    {
        ProcessResult result = ProcessRunner.Run(
            "osascript",
            ["-e", "tell application \"System Events\" to get picture of current desktop"]);

        if (!result.Succeeded)
        {
            OnTrace($"osascript failed ({result.ExitCode}): {result.StdErr}");
            return null;
        }

        return string.IsNullOrWhiteSpace(result.StdOut) ? null : result.StdOut;
    }
}
