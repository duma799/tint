using System.Diagnostics;

namespace Tint.Core.Util;

/// <summary>The outcome of running an external program.</summary>
public sealed record ProcessResult(int ExitCode, string StdOut, string StdErr)
{
    public bool Succeeded => ExitCode == 0;
}

/// <summary>Runs small helper programs (osascript, sips…) and captures their output.</summary>
public static class ProcessRunner
{
    public static ProcessResult Run(string fileName, IEnumerable<string> arguments, TimeSpan? timeout = null)
    {
        var info = new ProcessStartInfo(fileName)
        {
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
        };
        // ArgumentList quotes each argument itself, so paths with spaces are safe.
        foreach (string argument in arguments)
        {
            info.ArgumentList.Add(argument);
        }

        using Process process = Process.Start(info)
            ?? throw new InvalidOperationException($"Could not start {fileName}.");

        // Read both streams concurrently, or a chatty stderr can fill its pipe and deadlock.
        Task<string> stdout = process.StandardOutput.ReadToEndAsync();
        Task<string> stderr = process.StandardError.ReadToEndAsync();

        if (!process.WaitForExit(timeout ?? TimeSpan.FromSeconds(10)))
        {
            process.Kill(entireProcessTree: true);
            throw new TimeoutException($"{fileName} did not finish in time.");
        }

        return new ProcessResult(process.ExitCode, stdout.Result.Trim(), stderr.Result.Trim());
    }
}
