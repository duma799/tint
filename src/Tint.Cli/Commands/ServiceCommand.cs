using System.CommandLine;
using Tint.Core.Service;
using Tint.Core.Util;

namespace Tint.Cli.Commands;

/// <summary><c>tint service install|uninstall|restart|status</c> — run <c>tint watch</c> from login.</summary>
internal static class ServiceCommand
{
    public static Command Create()
    {
        var command = new Command("service", "Run `tint watch` in the background from login (a launchd agent).");

        var install = new Command("install", "Start watching now and at every login.");
        install.SetAction(_ => Guard(() =>
        {
            IReadOnlyList<string> program = [.. LaunchAgent.TintCommand(), "watch"];
            LaunchAgent.Install(program);
            Console.WriteLine($"  ✓ installed {LaunchAgent.PlistPath}");
            Console.WriteLine($"    runs: {string.Join(' ', program)}");
            Console.WriteLine($"    log:  {TintPaths.Log}");
            Console.WriteLine("  macOS may ask to let tint control System Events and read other apps' data — allow both.");
        }));

        var uninstall = new Command("uninstall", "Stop watching and remove the agent.");
        uninstall.SetAction(_ => Guard(() =>
            Console.WriteLine(LaunchAgent.Uninstall() ? "  ✓ removed; tint no longer runs at login" : "  · wasn't installed")));

        var restart = new Command("restart", "Restart the background watcher (e.g. after updating tint).");
        restart.SetAction(_ => Guard(() =>
        {
            LaunchAgent.Restart();
            Console.WriteLine("  ✓ restarted");
        }));

        var status = new Command("status", "Is the background watcher running?");
        status.SetAction(_ => Guard(() =>
        {
            ServiceStatus s = LaunchAgent.Status();
            string state = !s.Installed ? "not installed" : s.Running ? $"running (pid {s.Pid})" : s.Loaded ? "loaded, not running" : "installed, not loaded";
            Console.WriteLine($"  {state}");
            if (s.Installed)
            {
                Console.WriteLine($"  runs: {string.Join(' ', s.ProgramArguments)}");
                Console.WriteLine($"  log:  {TintPaths.Log}");
            }
        }));

        command.Subcommands.Add(install);
        command.Subcommands.Add(uninstall);
        command.Subcommands.Add(restart);
        command.Subcommands.Add(status);
        return command;
    }

    private static int Guard(Action action)
    {
        if (!OperatingSystem.IsMacOS())
        {
            return Terminal.Error("the service is a macOS launchd agent.");
        }

        try
        {
            action();
            return 0;
        }
        catch (Exception ex) when (ex is InvalidOperationException or IOException or UnauthorizedAccessException or TimeoutException)
        {
            return Terminal.Error(ex.Message);
        }
    }
}
