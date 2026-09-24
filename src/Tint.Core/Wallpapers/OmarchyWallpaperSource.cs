namespace Tint.Core.Wallpapers;

/// <summary>
/// Omarchy (Arch + Hyprland). Omarchy points
/// <c>~/.local/state/omarchy/current/background</c> at the current wallpaper;
/// changing the background re-points it, which is the signal to look again.
/// </summary>
public sealed class OmarchyWallpaperSource(string? stateDirectory = null, TimeProvider? timeProvider = null)
    : WatchedWallpaperSource(timeProvider)
{
    private readonly string _currentDirectory = Path.Combine(stateDirectory ?? DefaultStateDirectory, "current");

    /// <summary><c>~/.local/state/omarchy</c>, or under <c>$XDG_STATE_HOME</c> when that's set.</summary>
    public static string DefaultStateDirectory
    {
        get
        {
            string? xdg = Environment.GetEnvironmentVariable("XDG_STATE_HOME");
            string state = string.IsNullOrEmpty(xdg)
                ? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".local", "state")
                : xdg;
            return Path.Combine(state, "omarchy");
        }
    }

    public override string Name => "Omarchy";

    protected override string WatchDirectory => _currentDirectory;

    public override string? Current()
    {
        var link = new FileInfo(Path.Combine(_currentDirectory, "background"));

        // Usually a symlink: follow it so each wallpaper has its own path, and a
        // change of wallpaper is a change of path.
        FileSystemInfo? target = link.LinkTarget is null ? null : link.ResolveLinkTarget(returnFinalTarget: true);
        if (target is not null)
        {
            if (target.Exists)
            {
                return target.FullName;
            }

            OnTrace($"{link.FullName} points at {target.FullName}, which doesn't exist");
            return null;
        }

        return link.Exists ? link.FullName : null;
    }
}
