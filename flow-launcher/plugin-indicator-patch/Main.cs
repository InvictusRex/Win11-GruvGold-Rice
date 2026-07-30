using System.Collections.Generic;
using System.IO;
using System.Linq;

namespace Flow.Launcher.Plugin.PluginIndicator
{
    public class Main : IPlugin, IPluginI18n, IHomeQuery
    {
        internal static PluginInitContext Context { get; private set; }

        private static Settings _settings;

        public void Init(PluginInitContext context)
        {
            Context = context;
            _settings = context.API.LoadSettingJsonStorage<Settings>();
        }

        public List<Result> Query(Query query)
        {
            // Registered as a global plugin too (apply.ps1): typed text that is not
            // the ? keyword just surfaces the matching home shortcuts.
            if (query.ActionKeyword != "?") return MatchHomeEntries(query.Search);
            return QueryResults(query);
        }

        private static Result ToResult(HomeEntry e, int score) => new Result
        {
            Title = e.Title,
            SubTitle = e.SubTitle,
            Score = score,
            IcoPath = e.Icon,
            Action = c =>
            {
                if (!string.IsNullOrEmpty(e.Command))
                {
                    System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(e.Command, e.Args) { UseShellExecute = true });
                    return true;
                }
                if (!string.IsNullOrEmpty(e.Url))
                {
                    Context.API.OpenUrl(e.Url);
                    return true;
                }
                Context.API.ChangeQuery($"{e.Keyword}{Plugin.Query.TermSeparator}");
                return false;
            }
        };

        // Huge gaps: Flow adds a per-result usage boost to Score, which must never
        // be able to reorder the list.
        private const int OrderStep = 1_000_000;

        private static List<Result> MatchHomeEntries(string search)
        {
            if (string.IsNullOrWhiteSpace(search)) return new();
            // Entries that are themselves a colon keyword/shell prefix are handled by their plugin.
            return _settings.HomeEntries
                .Where(e => !e.Keyword.EndsWith(":") && e.Keyword != ">")
                .Select(e => (e, match: Context.API.FuzzySearch(search, e.Title)))
                .Where(x => x.match.IsSearchPrecisionScoreMet())
                .Select(x => ToResult(x.e, OrderStep * 100 + x.match.Score))
                .ToList();
        }

        private static List<Result> QueryResults(Query query = null)
        {
            var nonGlobalPlugins = GetNonGlobalPlugins();
            var querySearch = query?.Search ?? string.Empty;

            var results =
                from keyword in nonGlobalPlugins.Keys
                let plugin = nonGlobalPlugins[keyword].Metadata
                let keywordSearchResult = Context.API.FuzzySearch(querySearch, keyword)
                let searchResult = keywordSearchResult.IsSearchPrecisionScoreMet() ? keywordSearchResult : Context.API.FuzzySearch(querySearch, plugin.Name)
                let score = searchResult.Score
                // Per-keyword icon override (local patch) - falls back to the
                // plugin's own single default icon when there is no override,
                // or the override file no longer exists.
                let icoPath = _settings.KeywordIcons.TryGetValue(keyword, out var customIcon) && File.Exists(customIcon)
                    ? customIcon
                    : plugin.IcoPath
                where (searchResult.IsSearchPrecisionScoreMet()
                        || string.IsNullOrEmpty(querySearch)) // To list all available action keywords
                    && !plugin.Disabled
                select new Result
                {
                    Title = keyword,
                    SubTitle = Localize.flowlauncher_plugin_pluginindicator_result_subtitle(plugin.Name),
                    Score = score,
                    IcoPath = icoPath,
                    AutoCompleteText = $"{keyword}{Plugin.Query.TermSeparator}",
                    Action = c =>
                    {
                        Context.API.ChangeQuery($"{keyword}{Plugin.Query.TermSeparator}");
                        return false;
                    }
                };
            return [.. results];
        }

        private static Dictionary<string, PluginPair> GetNonGlobalPlugins()
        {
            var nonGlobalPlugins = new Dictionary<string, PluginPair>();
            foreach (var plugin in Context.API.GetAllPlugins())
            {
                foreach (var actionKeyword in plugin.Metadata.ActionKeywords)
                {
                    // Skip global keywords
                    if (actionKeyword == Plugin.Query.GlobalPluginWildcardSign) continue;

                    // Skip dulpicated keywords
                    if (nonGlobalPlugins.ContainsKey(actionKeyword)) continue;

                    nonGlobalPlugins.Add(actionKeyword, plugin);
                }
            }
            return nonGlobalPlugins;
        }

        public string GetTranslatedPluginTitle()
        {
            return Localize.flowlauncher_plugin_pluginindicator_plugin_name();
        }

        public string GetTranslatedPluginDescription()
        {
            return Localize.flowlauncher_plugin_pluginindicator_plugin_description();
        }

        public List<Result> HomeQuery()
        {
if (_settings.HomeEntries.Count == 0) return QueryResults();

            var count = _settings.HomeEntries.Count;
            return _settings.HomeEntries.Select((e, i) => ToResult(e, (count - i) * OrderStep)).ToList();
        }
    }
}




