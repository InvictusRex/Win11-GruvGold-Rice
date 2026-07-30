using System.Collections.Generic;

namespace Flow.Launcher.Plugin.PluginIndicator
{
    public class Settings
    {
        // Action keyword -> absolute path of an icon file. When present and the
        // file exists, the "?" keyword-indicator list shows this icon for that
        // keyword instead of the owning plugin's single default icon. Not part
        // of upstream Flow Launcher - a local patch (see Windows Rice repo).
        public Dictionary<string, string> KeywordIcons { get; set; } = new();

        // Fixed, ordered contents of the empty-query home page (local patch).
        // Empty list = upstream behaviour (every keyword, in load order).
        public List<HomeEntry> HomeEntries { get; set; } = new();
    }

    public class HomeEntry
    {
        public string Title { get; set; } = "";
        public string SubTitle { get; set; } = "";
        public string Icon { get; set; } = "";
        // Exactly one of these: Keyword fills the query box, Url opens in the browser.
        public string Keyword { get; set; } = "";
        public string Url { get; set; } = "";
        // Or run a program directly (Command + Args).
        public string Command { get; set; } = "";
        public string Args { get; set; } = "";
    }
}


