# =============================================================================
# NA PAINTERLYNPR ASSETS - APP CORE - STATE PAYLOAD
# =============================================================================
#
# FILE       : Na__PainterlyAssets__AppCore__StatePayload__.rb
# NAMESPACE  : Na__PainterlyAssets::Na__StatePayload
# PURPOSE    : The whole state the dialog draws from, as one JSON-ready Hash:
#              the library folder, the catalogue, what a new asset may be, the
#              Author defaults, the Python in use, this PC's preferences and
#              the last validation report.
# CREATED    : 30-Oct-2026
#
# DESCRIPTION:
# - Built on the page's ready handshake and after Refresh, and nothing model
#   or library specific is ever baked into the HTML, so a rescan repaints the
#   page without reloading it.
# - Numbers only through JSON.generate (DialogManager): a SketchUp Length
#   interpolated into a script is a syntax error the page cannot catch.
#
# =============================================================================

module Na__PainterlyAssets
    module Na__StatePayload

    # -------------------------------------------------------------------------
    # REGION | Public Surface
    # -------------------------------------------------------------------------

        # FUNCTION | The Whole State (rescans the library unless asked not to)
        # ------------------------------------------------------------
        def self.Na__State__Build(rescan = true)
            resolution = Na__PathResolver.Na__Paths__RootResolution
            catalogue  = rescan ? Na__Catalogue.Na__Catalogue__Scan : Na__Catalogue.Na__Catalogue__Last
            options    = resolution['root'] ? Na__Register.Na__Register__Options(resolution['root']) : nil
            {
                'plugin'         => {
                    'name'    => Na__ConfigLoader.Na__Config__GetOr('Na PainterlyNPR Assets', 'plugin', 'name'),
                    'version' => Na__PainterlyAssets.Na__PublicApi__Version
                },
                'library'        => {
                    'found'   => !resolution['root'].nil?,
                    'root'    => resolution['root'],
                    'source'  => resolution['source'],
                    'tried'   => resolution['tried'],
                    'library' => Na__PathResolver.Na__Paths__Library(resolution['root'])
                },
                'catalogue'      => catalogue,
                'options'        => options,
                'authorDefaults' => Na__ConfigLoader.Na__Config__GetOr({}, 'author', 'defaults'),
                'author'         => {
                    'defaultStatus'     => Na__ConfigLoader.Na__Config__GetOr('Active', 'author', 'defaultStatus'),
                    'originToleranceMm' => Na__ConfigLoader.Na__Config__GetOr(1.0, 'author', 'originToleranceMm')
                },
                'materials'      => Na__MaterialPalette.Na__Palette__Build(resolution['root']),
                'python'         => Na__BuildUtil.Na__BuildUtil__Describe,
                'prefs'          => self.Na__State__Prefs,
                'validation'     => Na__ValidateRunner.Na__Validate__Last,
                'busy'           => Na__BuildUtil.Na__BuildUtil__Busy?,
                'log'            => Na__DebugTools.Na__Debug__RecentEntries(30)
            }
        end
        # ---------------------------------------------------------------

        def self.Na__State__Prefs
            {
                'thumbs' => Na__UserConfigStore.Na__UserConfig__Get('ui', 'thumbs', 'RND'),
                'tab'    => Na__UserConfigStore.Na__UserConfig__Get('ui', 'tab', 'catalogue')
            }
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
