using System.Diagnostics;

namespace Tint.Core.Util;

/// <summary>Questions about other running programs.</summary>
public static class Processes
{
    /// <summary>True if a process with exactly this name is running (<c>pgrep -x</c>).</summary>
    public static bool IsRunning(string name)
    {
        try
        {
            return ProcessRunner.Run("pgrep", ["-x", name]).Succeeded;
        }
        catch (Exception ex) when (ex is TimeoutException or InvalidOperationException or System.ComponentModel.Win32Exception)
        {
            return false;
        }
    }

    /// <summary>
    /// Runs a program without capturing its output and waits for it. For
    /// scripts that may start background processes: a captured pipe would stay
    /// open as long as they run and hang tint.
    /// </summary>
    /// <returns>The exit code, or null if it was still running at the timeout.</returns>
    public static int? RunDetached(string fileName, IEnumerable<string> arguments, TimeSpan timeout, IDictionary<string, string>? environment = null)
    {
        var info = new ProcessStartInfo(fileName) { UseShellExecute = false };
        foreach (string argument in arguments)
        {
            info.ArgumentList.Add(argument);
        }

        foreach ((string key, string value) in environment ?? new Dictionary<string, string>())
        {
            info.Environment[key] = value;
        }

        using Process process = Process.Start(info) ?? throw new InvalidOperationException($"Could not start {fileName}.");
        return process.WaitForExit(timeout) ? process.ExitCode : null;
    }
}
