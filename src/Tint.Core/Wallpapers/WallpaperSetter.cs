using Tint.Core.Util;

namespace Tint.Core.Wallpapers;

/// <summary>Sets the desktop picture on every display, through System Events.</summary>
public static class WallpaperSetter
{
    // The path goes in as an argument, not spliced into the script, so no
    // filename can break out of the AppleScript string.
    private static readonly string[] Script =
    [
        "-e", "on run argv",
        "-e", "tell application \"System Events\" to tell every desktop to set picture to (item 1 of argv)",
        "-e", "end run",
    ];

    public static void Set(string imagePath)
    {
        if (!OperatingSystem.IsMacOS())
        {
            throw new PlatformNotSupportedException("Setting the wallpaper works on macOS only.");
        }

        string path = Path.GetFullPath(imagePath);
        if (!File.Exists(path))
        {
            throw new FileNotFoundException($"No such image: {path}", path);
        }

        ProcessResult result = ProcessRunner.Run("osascript", [.. Script, path], TimeSpan.FromSeconds(20));
        if (!result.Succeeded)
        {
            throw new InvalidOperationException($"couldn't set the wallpaper: {result.StdErr}");
        }
    }
}
