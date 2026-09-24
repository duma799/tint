using System.CommandLine;
using Tint.Core.Diagnostics;

namespace Tint.Cli.Commands;

/// <summary><c>tint doctor</c> — check the setup and say what to fix.</summary>
internal static class DoctorCommand
{
    public static Command Create()
    {
        var command = new Command("doctor", "Check tint's setup: wallpaper access, apps it reloads, the service.");
        command.SetAction(_ =>
        {
            IReadOnlyList<Check> checks = Doctor.Run();
            foreach (Check check in checks)
            {
                string mark = check.Status switch
                {
                    CheckStatus.Ok => "✓",
                    CheckStatus.Warning => "!",
                    CheckStatus.Problem => "✗",
                    _ => "·",
                };
                Console.WriteLine($"  {mark} {check.Name,-13} {check.Detail}");
            }

            return checks.Any(c => c.Status == CheckStatus.Problem) ? 1 : 0;
        });

        return command;
    }
}
