using Tint.Core.Wallpapers;

namespace Tint.Core.Tests;

/// <summary>
/// The XML here mirrors the shape of macOS's
/// <c>com.apple.wallpaper/Store/Index.plist</c> after <c>plutil -convert xml1</c>.
/// </summary>
public class MacWallpaperStoreTests
{
    private const string Header = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        """;

    private static string Choice(string provider, string? file) => $"""
        <dict>
          <key>Configuration</key><data>YnBsaXN0MDA=</data>
          <key>Files</key>
          <array>{(file is null ? "" : $"<dict><key>relative</key><string>{file}</string></dict>")}</array>
          <key>Provider</key><string>{provider}</string>
        </dict>
        """;

    private static string Slot(string choice) => $"""
        <dict>
          <key>Content</key>
          <dict>
            <key>Choices</key><array>{choice}</array>
            <key>Shuffle</key><string>$null</string>
          </dict>
          <key>LastSet</key><date>2026-09-24T12:00:00Z</date>
        </dict>
        """;

    private static MacWallpaperStore.StoreChoice Pick(string body) =>
        MacWallpaperStore.PickDesktopChoice(MacWallpaperStore.FlattenPlist($"{Header}<dict>{body}</dict></plist>"));

    [Fact]
    public void Reads_the_desktop_picture_and_decodes_the_file_url()
    {
        string body = $"""
            <key>AllSpacesAndDisplays</key>
            <dict>
              <key>Desktop</key>{Slot(Choice("com.apple.wallpaper.choice.image", "file:///Users/duma/Pictures/City%20Night.jpg"))}
              <key>Type</key><string>individual</string>
            </dict>
            """;

        MacWallpaperStore.StoreChoice choice = Pick(body);

        Assert.Equal("/Users/duma/Pictures/City Night.jpg", choice.File);
        Assert.Equal("com.apple.wallpaper.choice.image", choice.Provider);
    }

    [Fact]
    public void Ignores_the_screen_saver_even_when_it_comes_first()
    {
        string body = $"""
            <key>AllSpacesAndDisplays</key>
            <dict>
              <key>Idle</key>{Slot(Choice("com.apple.wallpaper.choice.image", "file:///Users/duma/Pictures/saver.jpg"))}
              <key>Desktop</key>{Slot(Choice("com.apple.wallpaper.choice.image", "file:///Users/duma/Pictures/desk.jpg"))}
            </dict>
            """;

        Assert.Equal("/Users/duma/Pictures/desk.jpg", Pick(body).File);
    }

    [Fact]
    public void Prefers_the_all_displays_setting_over_a_per_display_one()
    {
        string body = $"""
            <key>Displays</key>
            <dict>
              <key>A1B2</key>
              <dict><key>Desktop</key>{Slot(Choice("com.apple.wallpaper.choice.image", "file:///old.jpg"))}</dict>
            </dict>
            <key>AllSpacesAndDisplays</key>
            <dict>
              <key>Desktop</key>{Slot(Choice("com.apple.wallpaper.choice.image", "file:///new.jpg"))}
            </dict>
            """;

        Assert.Equal("/new.jpg", Pick(body).File);
    }

    [Fact]
    public void An_aerial_wallpaper_has_a_provider_but_no_file()
    {
        string body = $"""
            <key>AllSpacesAndDisplays</key>
            <dict>
              <key>Desktop</key>{Slot(Choice("com.apple.wallpaper.choice.aerials", file: null))}
            </dict>
            """;

        MacWallpaperStore.StoreChoice choice = Pick(body);

        Assert.Null(choice.File);
        Assert.Equal("com.apple.wallpaper.choice.aerials", choice.Provider);
    }

    [Fact]
    public void Real_macOS_26_layout_yields_the_nested_configuration()
    {
        // Trimmed from a real Index.plist: a picture wallpaper has an EMPTY
        // "Files" array; its path lives inside "Configuration", a nested plist.
        byte[] nested = [0x62, 0x70, 0x6c, 0x69, 0x73, 0x74, 0x30, 0x30]; // "bplist00"
        string data = Convert.ToBase64String(nested);
        string body = $"""
            <key>AllSpacesAndDisplays</key>
            <dict>
              <key>Desktop</key>
              <dict>
                <key>Content</key>
                <dict>
                  <key>Choices</key>
                  <array>
                    <dict>
                      <key>Configuration</key>
                      <data>
                      {data}
                      </data>
                      <key>Files</key><array/>
                      <key>Provider</key><string>com.apple.wallpaper.choice.image</string>
                    </dict>
                  </array>
                  <key>EncodedOptionValues</key><data>YnBsaXN0MDDRAQI=</data>
                  <key>Shuffle</key><string>$null</string>
                </dict>
              </dict>
              <key>Idle</key>{Slot(Choice("com.apple.wallpaper.choice.macintosh", file: null))}
              <key>Type</key><string>individual</string>
            </dict>
            <key>Displays</key><dict/>
            <key>Spaces</key><dict/>
            """;

        MacWallpaperStore.StoreChoice choice = Pick(body);

        Assert.Null(choice.File);
        Assert.Equal("com.apple.wallpaper.choice.image", choice.Provider);
        Assert.Equal(nested, choice.Configuration);
    }

    [Fact]
    public void Finds_the_file_url_inside_the_nested_configuration()
    {
        // The nested plist after plutil -convert xml1.
        const string nested = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
              <key>type</key><string>imageFile</string>
              <key>url</key>
              <dict><key>relative</key><string>file:///Users/duma/Downloads/Codex%20Image.jpg</string></dict>
            </dict>
            </plist>
            """;

        Assert.Equal(
            "/Users/duma/Downloads/Codex Image.jpg",
            MacWallpaperStore.FindFileUrl(MacWallpaperStore.FlattenPlist(nested)));
    }

    [Fact]
    public void An_empty_store_yields_nothing()
    {
        MacWallpaperStore.StoreChoice choice = Pick(string.Empty);

        Assert.Null(choice.File);
        Assert.Null(choice.Provider);
    }
}
