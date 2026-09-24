using System.Diagnostics;
using Tint.Core.Themes;
using Tint.Core.Util;

namespace Tint.Core.Reload;

public sealed record ReloadContext(Scheme Scheme, string Wallpaper, string CacheDirectory);

/// <summary>What happened to one app. <see cref="Skipped"/> means "not installed / not running" — not an error.</summary>
public sealed record ReloadResult(string Name, bool Ok, bool Skipped, string Detail);

/// <summary>Tells one app to pick up the new colours.</summary>
public interface IReloader
{
    string Name { get; }

    ReloadResult Reload(ReloadContext context);
}

public static class Reloaders
{
    /// <summary>
    /// The reload steps, in order. Built-in macOS app reloads (SketchyBar,
    /// JankyBorders, Ghostty) are still to come; until then the user's hook
    /// covers them.
    /// </summary>
    public static IReadOnlyList<IReloader> ForCurrentPlatform() => [new HookReloader()];
}

/// <summary>Runs one command, if it's installed.</summary>
public sealed class CommandReloader(
    string name,
    string command,
    string[] arguments,
    Func<bool>? requires = null,
    string? whyNot = null,
    int? notRunningExitCode = null) : IReloader
{
    public string Name => name;

    public ReloadResult Reload(ReloadContext context)
    {
        if (!TintPaths.OnPath(command))
        {
            return new ReloadResult(name, Ok: true, Skipped: true, $"{command} not installed");
        }

        if (requires is not null && !requires())
        {
            return new ReloadResult(name, Ok: true, Skipped: true, whyNot ?? "not applicable");
        }

        try
        {
            ProcessResult result = ProcessRunner.Run(command, arguments);
            if (notRunningExitCode is { } code && result.ExitCode == code)
            {
                return new ReloadResult(name, Ok: true, Skipped: true, "not running");
            }

            return result.Succeeded
                ? new ReloadResult(name, Ok: true, Skipped: false, "reloaded")
                : new ReloadResult(name, Ok: false, Skipped: false, $"{command} exited {result.ExitCode}: {result.StdErr}");
        }
        catch (Exception ex) when (ex is TimeoutException or InvalidOperationException or System.ComponentModel.Win32Exception)
        {
            return new ReloadResult(name, Ok: false, Skipped: false, ex.Message);
        }
    }
}

/// <summary>
/// Runs <c>~/.config/tint/hooks/post-apply</c> if it exists and is executable —
/// the place for setup-specific steps (restarting a shell, copying a scheme
/// file somewhere). It gets TINT_WALLPAPER, TINT_MODE and TINT_CACHE.
/// </summary>
public sealed class HookReloader(string? hooksDirectory = null) : IReloader
{
    private static readonly TimeSpan Timeout = TimeSpan.FromSeconds(30);

    public string Name => "post-apply hook";

    public ReloadResult Reload(ReloadContext context)
    {
        string hook = Path.Combine(hooksDirectory ?? TintPaths.Hooks, "post-apply");
        if (!File.Exists(hook))
        {
            return new ReloadResult(Name, Ok: true, Skipped: true, $"no {hook}");
        }

        if (!OperatingSystem.IsWindows() && (File.GetUnixFileMode(hook) & UnixFileMode.UserExecute) == 0)
        {
            return new ReloadResult(Name, Ok: false, Skipped: false, $"{hook} is not executable (chmod +x it)");
        }

        // Output is NOT captured: hooks often start background processes (a
        // shell, a bar), which would keep a captured pipe open and hang tint.
        var info = new ProcessStartInfo(hook) { UseShellExecute = false };
        info.Environment["TINT_WALLPAPER"] = context.Wallpaper;
        info.Environment["TINT_MODE"] = context.Scheme.Mode == ThemeMode.Dark ? "dark" : "light";
        info.Environment["TINT_CACHE"] = context.CacheDirectory;

        try
        {
            using Process process = Process.Start(info) ?? throw new InvalidOperationException("could not start the hook");
            if (!process.WaitForExit(Timeout))
            {
                return new ReloadResult(Name, Ok: false, Skipped: false, $"still running after {Timeout.TotalSeconds:0} s; left it running");
            }

            return process.ExitCode == 0
                ? new ReloadResult(Name, Ok: true, Skipped: false, "ran")
                : new ReloadResult(Name, Ok: false, Skipped: false, $"exited {process.ExitCode}");
        }
        catch (Exception ex) when (ex is InvalidOperationException or System.ComponentModel.Win32Exception)
        {
            return new ReloadResult(Name, Ok: false, Skipped: false, ex.Message);
        }
    }
}
