using System.Xml;
using System.Xml.Linq;

namespace Tint.Core.Wallpapers;

/// <summary>
/// Reads macOS's wallpaper store (<c>Index.plist</c>, converted to XML). Plain
/// parsing with no macOS calls, so it is unit-tested on every platform.
/// </summary>
/// <remarks>
/// Shape on macOS 26, per desktop "choice":
/// <code>
/// AllSpacesAndDisplays/Desktop/Content/Choices[0]/
///     Provider       "com.apple.wallpaper.choice.image"
///     Files          []            ← empty, even for a picture
///     Configuration  &lt;data&gt;  ← a second, nested binary plist holding the file URL
/// </code>
/// </remarks>
internal static class MacWallpaperStore
{
    /// <summary>
    /// The desktop wallpaper found in Index.plist: its image file if listed
    /// directly, its provider id, and the raw nested configuration plist.
    /// </summary>
    internal sealed record StoreChoice(string? File, string? Provider, byte[]? Configuration = null);

    /// <summary>
    /// One value in a plist with the key path leading to it. Strings are stored
    /// as-is; <c>&lt;data&gt;</c> as base64 with <see cref="IsData"/> set.
    /// </summary>
    internal sealed record PlistLeaf(string Path, string Key, string Value, bool IsData = false);

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

        PlistLeaf? provider = desktop.FirstOrDefault(l => l.Key == "Provider" && !l.IsData);
        if (provider is null)
        {
            return new StoreChoice(null, null);
        }

        // Everything else must come from the same choice as the provider.
        string choice = provider.Path[..provider.Path.LastIndexOf('/')] + "/";
        PlistLeaf[] own = [.. desktop.Where(l => l.Path.StartsWith(choice, StringComparison.Ordinal))];

        string? file = FindFileUrl(own.Where(l => l.Key == "relative"));
        PlistLeaf? configuration = own.FirstOrDefault(l => l.Key == "Configuration" && l.IsData && l.Value.Length > 0);

        return new StoreChoice(
            file,
            provider.Value,
            configuration is null ? null : Convert.FromBase64String(configuration.Value));
    }

    /// <summary>The first <c>file://</c> URL among the string values, as a local path.</summary>
    internal static string? FindFileUrl(IEnumerable<PlistLeaf> leaves) =>
        leaves
            .Where(l => !l.IsData && l.Value.StartsWith("file://", StringComparison.Ordinal))
            .Select(l => new Uri(l.Value).LocalPath)
            .FirstOrDefault();

    /// <summary>Flattens an XML plist into its values, e.g. <c>AllSpacesAndDisplays/Desktop/Content/Choices[0]/Provider</c>.</summary>
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

            case "data":
                // Base64, wrapped across lines by plutil.
                leaves.Add(new PlistLeaf(path, key, string.Concat(element.Value.Where(c => !char.IsWhiteSpace(c))), IsData: true));
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
