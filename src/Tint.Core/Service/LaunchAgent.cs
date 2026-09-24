using System.Security;
using System.Text;
using Tint.Core.Util;

namespace Tint.Core.Service;

public sealed record ServiceStatus(bool Installed, bool Loaded, int? Pid, IReadOnlyList<string> ProgramArguments)
{
    public bool Running => Pid is not null;
}

/// <summary>
/// Runs <c>tint watch</c> at login, as a launchd user agent: a plist in
/// <c>~/Library/LaunchAgents</c> that launchd starts when you log in and
/// restarts if it crashes. Output goes to <c>~/Library/Logs/tint.log</c>.
/// </summary>
public static class LaunchAgent
{
    public const string Label = "io.github.duma799.tint";

    public static string PlistPath => Path.Combine(
        TintPaths.Home, "Library", "LaunchAgents", $"{Label}.plist");

    /// <summary>
    /// launchd starts agents with a bare PATH (/usr/bin:/bin:/usr/sbin:/sbin),
    /// where sketchybar, borders and most hooks' tools aren't. So the agent
    /// gets the PATH of the shell that installed it, plus Homebrew's folders.
    /// </summary>
    public static string ServicePath(string? currentPath)
    {
        string[] wanted = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"];
        string[] current = (currentPath ?? string.Empty).Split(':', StringSplitOptions.RemoveEmptyEntries);
        return string.Join(':', current.Concat(wanted).Distinct(StringComparer.Ordinal));
    }

    /// <summary>The agent's plist. Pure, so it can be tested anywhere.</summary>
    public static string Plist(IReadOnlyList<string> programArguments, IReadOnlyDictionary<string, string> environment, string logPath)
    {
        static string S(string value) => $"<string>{SecurityElement.Escape(value)}</string>";

        var sb = new StringBuilder();
        sb.Append("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
        sb.Append("<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n");
        sb.Append("<plist version=\"1.0\">\n<dict>\n");
        sb.Append($"  <key>Label</key>\n  {S(Label)}\n");
        sb.Append("  <key>ProgramArguments</key>\n  <array>\n");
        foreach (string argument in programArguments)
        {
            sb.Append($"    {S(argument)}\n");
        }

        sb.Append("  </array>\n");
        sb.Append("  <key>EnvironmentVariables</key>\n  <dict>\n");
        foreach ((string key, string value) in environment.OrderBy(e => e.Key, StringComparer.Ordinal))
        {
            sb.Append($"    <key>{SecurityElement.Escape(key)}</key>\n    {S(value)}\n");
        }

        sb.Append("  </dict>\n");
        sb.Append("  <key>RunAtLoad</key>\n  <true/>\n");
        // Restart after a crash, but not after a clean exit (e.g. `tint service uninstall`).
        sb.Append("  <key>KeepAlive</key>\n  <dict>\n    <key>SuccessfulExit</key>\n    <false/>\n  </dict>\n");
        sb.Append($"  <key>StandardOutPath</key>\n  {S(logPath)}\n");
        sb.Append($"  <key>StandardErrorPath</key>\n  {S(logPath)}\n");
        sb.Append("</dict>\n</plist>\n");
        return sb.ToString();
    }

    /// <summary>
    /// How to start this tint: the <c>tint</c> on the PATH if it is this same
    /// program (a Homebrew or dotnet-tool link survives upgrades; the file it
    /// points to doesn't), else this program's own path.
    /// </summary>
    public static IReadOnlyList<string> TintCommand()
    {
        string self = Environment.ProcessPath ?? throw new InvalidOperationException("can't tell where tint is installed.");
        if (Path.GetFileNameWithoutExtension(self) == "dotnet")
        {
            // `dotnet tint.dll` / `dotnet run`: the entry assembly is the program.
            return [self, Path.Combine(AppContext.BaseDirectory, "tint.dll")];
        }

        string? onPath = TintPaths.FindOnPath("tint");
        if (onPath is not null && SameFile(onPath, self))
        {
            return [onPath];
        }

        return [self];
    }

    public static void Install(IReadOnlyList<string> programArguments)
    {
        var environment = new Dictionary<string, string>
        {
            ["PATH"] = ServicePath(Environment.GetEnvironmentVariable("PATH")),
        };
        if (Environment.GetEnvironmentVariable("DOTNET_ROOT") is { Length: > 0 } dotnetRoot)
        {
            environment["DOTNET_ROOT"] = dotnetRoot;
        }

        Directory.CreateDirectory(Path.GetDirectoryName(PlistPath)!);
        Directory.CreateDirectory(Path.GetDirectoryName(TintPaths.Log)!);
        File.WriteAllText(PlistPath, Plist(programArguments, environment, TintPaths.Log));

        // Unload any older copy first; "not loaded" is fine.
        Launchctl("bootout", Target);
        ProcessResult load = Launchctl("bootstrap", Domain, PlistPath);
        if (!load.Succeeded)
        {
            throw new InvalidOperationException($"launchctl bootstrap failed: {load.StdErr}");
        }
    }

    public static bool Uninstall()
    {
        bool existed = File.Exists(PlistPath);
        Launchctl("bootout", Target);
        File.Delete(PlistPath);
        return existed;
    }

    public static void Restart()
    {
        ProcessResult result = Launchctl("kickstart", "-k", Target);
        if (!result.Succeeded)
        {
            throw new InvalidOperationException($"launchctl kickstart failed: {result.StdErr}");
        }
    }

    public static ServiceStatus Status()
    {
        bool installed = File.Exists(PlistPath);
        IReadOnlyList<string> program = installed ? ReadProgramArguments(File.ReadAllText(PlistPath)) : [];

        ProcessResult print = Launchctl("print", Target);
        if (!print.Succeeded)
        {
            return new ServiceStatus(installed, Loaded: false, Pid: null, program);
        }

        return new ServiceStatus(installed, Loaded: true, ParsePid(print.StdOut), program);
    }

    /// <summary>The <c>pid = 123</c> line of <c>launchctl print</c>; absent when it isn't running.</summary>
    internal static int? ParsePid(string launchctlPrint)
    {
        foreach (string line in launchctlPrint.Split('\n'))
        {
            string[] parts = line.Trim().Split(" = ", 2);
            if (parts is ["pid", string value] && int.TryParse(value, out int pid))
            {
                return pid;
            }
        }

        return null;
    }

    internal static IReadOnlyList<string> ReadProgramArguments(string plist)
    {
        var document = System.Xml.Linq.XDocument.Parse(plist);
        System.Xml.Linq.XElement? array = document.Descendants("key")
            .FirstOrDefault(k => k.Value == "ProgramArguments")?
            .ElementsAfterSelf().FirstOrDefault();
        return array is null ? [] : [.. array.Elements("string").Select(e => e.Value)];
    }

    private static string Domain => $"gui/{UserId()}";

    private static string Target => $"{Domain}/{Label}";

    private static string UserId() => ProcessRunner.Run("id", ["-u"]).StdOut;

    private static ProcessResult Launchctl(params string[] arguments) => ProcessRunner.Run("launchctl", arguments);

    private static bool SameFile(string a, string b) =>
        string.Equals(RealPath(a), RealPath(b), StringComparison.Ordinal);

    private static string RealPath(string path)
    {
        FileSystemInfo? target = File.ResolveLinkTarget(path, returnFinalTarget: true);
        return Path.GetFullPath(target?.FullName ?? path);
    }
}
