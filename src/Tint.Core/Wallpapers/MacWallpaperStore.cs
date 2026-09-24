using System.Xml;
using System.Xml.Linq;

namespace Tint.Core.Wallpapers;

/// <summary>
/// Reads macOS's wallpaper store (<c>Index.plist</c>, converted to XML). Plain
/// parsing with no macOS calls, so it is unit-tested on every platform.
/// </summary>
internal static class MacWallpaperStore
{
    /// <summary>The desktop wallpaper found in Index.plist: its image file, if any, and its provider id.</summary>
    internal sealed record StoreChoice(string? File, string? Provider);

    /// <summary>One string value in a plist, with the key path leading to it.</summary>
    internal sealed record PlistLeaf(string Path, string Key, string Value);

    /// <summary>
    /// Picks the desktop (not screen saver) wallpaper. Settings applied to all
    /// displays and spaces win over per-display ones, then document order.
    /// </summary>
    internal static StoreChoice PickDesktopChoice(IReadOnlyList<PlistLeaf> leaves)
    {
        string[] sectionOrder = ["AllSpacesAndDisplays", "Displays", "Spaces", "SystemDefault"];

        PlistLeaf[] desktop =
        [
            .. leaves
                .Select((leaf, index) => (leaf, index))
                .Where(x => x.leaf.Path.Split('/').Contains("Desktop"))
                .OrderBy(x =>
                {
                    int rank = Array.IndexOf(sectionOrder, x.leaf.Path.Split('/')[0]);
                    return rank < 0 ? sectionOrder.Length : rank;
                })
                .ThenBy(x => x.index)
                .Select(x => x.leaf),
        ];

        string? file = desktop
            .Where(l => l.Key == "relative" && l.Value.StartsWith("file://", StringComparison.Ordinal))
            .Select(l => new Uri(l.Value).LocalPath)
            .FirstOrDefault();
        string? provider = desktop.FirstOrDefault(l => l.Key == "Provider")?.Value;

        return new StoreChoice(file, provider);
    }

    /// <summary>Flattens an XML plist into its string values, e.g. <c>AllSpacesAndDisplays/Desktop/Content/Choices[0]/Provider</c>.</summary>
    internal static IReadOnlyList<PlistLeaf> FlattenPlist(string xml)
    {
        // Plists start with a DOCTYPE; DTD processing is off by default for
        // safety, so ignore it explicitly rather than let parsing throw.
        var settings = new XmlReaderSettings { DtdProcessing = DtdProcessing.Ignore, XmlResolver = null };
        using var reader = XmlReader.Create(new StringReader(xml), settings);
        XElement? top = XDocument.Load(reader).Root?.Elements().FirstOrDefault();

        var leaves = new List<PlistLeaf>();
        if (top is not null)
        {
            Walk(top, path: string.Empty, key: string.Empty, leaves);
        }

        return leaves;
    }

    private static void Walk(XElement element, string path, string key, List<PlistLeaf> leaves)
    {
        switch (element.Name.LocalName)
        {
            case "string":
                leaves.Add(new PlistLeaf(path, key, element.Value));
                break;

            case "dict":
                string? pendingKey = null;
                foreach (XElement child in element.Elements())
                {
                    if (child.Name.LocalName == "key")
                    {
                        pendingKey = child.Value;
                        continue;
                    }

                    string childKey = pendingKey ?? string.Empty;
                    Walk(child, path.Length == 0 ? childKey : $"{path}/{childKey}", childKey, leaves);
                    pendingKey = null;
                }

                break;

            case "array":
                int i = 0;
                foreach (XElement child in element.Elements())
                {
                    Walk(child, $"{path}[{i++}]", key, leaves);
                }

                break;
        }
    }
}
