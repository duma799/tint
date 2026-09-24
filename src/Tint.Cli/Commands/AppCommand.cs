using System.CommandLine;
using Tint.Core.Util;

namespace Tint.Cli.Commands;

/// <summary><c>tint app</c> — open the desktop app.</summary>
internal static class AppCommand
{
    public static Command Create()
    {
        var command = new Command("app", "Open the tint desktop app: pick an image, preview, tweak, apply.");
        command.SetAction(_ =>
        {
            string? app = Find();
            if (app is null)
            {
                return Terminal.Error("couldn't find Tint.app. Install tint with Homebrew, or run it from the source: dotnet run --project src/Tint.App");
            }

            ProcessResult result = ProcessRunner.Run("open", [app]);
            return result.Succeeded ? 0 : Terminal.Error($"open failed: {result.StdErr}");
        });

        return command;
    }

    /// <summary>Next to this tint (Homebrew puts both in one folder), else in Applications.</summary>
    private static string? Find()
    {
        var candidates = new List<string>();
        if (Environment.ProcessPath is { } self)
        {
            FileSystemInfo? target = File.ResolveLinkTarget(self, returnFinalTarget: true);
            string dir = Path.GetDirectoryName(target?.FullName ?? self)!;
            candidates.Add(Path.GetFullPath(Path.Combine(dir, "..", "Tint.app")));
            candidates.Add(Path.Combine(dir, "Tint.app"));
        }

        string home = TintPaths.Home;
        candidates.Add("/Applications/Tint.app");
        candidates.Add(Path.Combine(home, "Applications", "Tint.app"));
        return candidates.FirstOrDefault(Directory.Exists);
    }
}
