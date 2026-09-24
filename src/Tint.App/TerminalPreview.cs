using Avalonia.Controls;
using Avalonia.Controls.Documents;
using Avalonia.Media;
using Tint.Core.Themes;

namespace Tint.App;

/// <summary>A few lines of a pretend terminal session, coloured the way a shell and git would colour them.</summary>
internal static class TerminalPreview
{
    public static void Fill(SelectableTextBlock text, Scheme s)
    {
        var inlines = new InlineCollection();

        void Add(string value, int? color = null, bool bold = false)
        {
            var run = new Run(value) { Foreground = MainWindow.Brush(color is { } i ? s[i] : s.Foreground) };
            if (bold)
            {
                run.FontWeight = FontWeight.Bold;
            }

            inlines.Add(run);
        }

        void Prompt(string command)
        {
            Add("~/tint", 6);
            Add(" main", 5);
            Add(" ❯ ", 2);
            Add(command + "\n");
        }

        Prompt("ls");
        Add("src", 4, bold: true);
        Add("  ");
        Add("tests", 4, bold: true);
        Add("  ");
        Add("build.sh", 2, bold: true);
        Add("  README.md  ");
        Add("wall.heic", 5);
        Add("\n");

        Prompt("git status --short");
        Add(" M", 1);
        Add(" src/Themes/SchemeBuilder.cs\n");
        Add("A ", 2);
        Add(" src/Tint.App/MainWindow.axaml\n");

        Prompt("dotnet test");
        Add("warning", 3, bold: true);
        Add(" CA1416: macOS-only call\n");
        Add("error", 1, bold: true);
        Add(" CS1002: ; expected\n");
        Add("Passed!", 2, bold: true);
        Add(" 75 tests  ");
        Add("# all readable", 8);

        text.Inlines = inlines;
    }
}
