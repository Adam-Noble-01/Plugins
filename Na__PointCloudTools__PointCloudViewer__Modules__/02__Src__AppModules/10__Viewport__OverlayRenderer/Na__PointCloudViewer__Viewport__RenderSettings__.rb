# =============================================================================
# NA POINT CLOUD VIEWER - VIEWPORT - RENDER SETTINGS
# =============================================================================
#
# FILE       : Na__PointCloudViewer__Viewport__RenderSettings__.rb
# NAMESPACE  : Na__PointCloudViewer::Na__RenderSettings
# PURPOSE    : Defaults, limits and validation for the display settings. Each
#              one changes what is DRAWN, never what is STORED: none of them
#              touches the cache or the source LAS.
#
# KEYS:
#   pointBudget     Integer  approx. maximum points drawn per frame, SHARED by
#                            every cloud on show (one per model)
#   pointSizePx     Integer  logical pixels          } each cloud's own look
#   opacityPercent  Integer  100 = opaque            } (v0.10.0): its slot's
#   colourMode      String   'rgb' | 'black' | 'cloud' } display
#
# 'cloud' (v0.10.0) draws every point in the cloud's own colour, the one that
#   marks it in the dialog: with two scans of one building on show, each can
#   be told apart at a glance while they are aligned.
#
# =============================================================================

module Na__PointCloudViewer
    module Na__RenderSettings

    # -------------------------------------------------------------------------
    # REGION | Defaults + Limits
    # -------------------------------------------------------------------------

        NA_COLOUR_MODES = %w[rgb black cloud].freeze
        NA_SHARED_KEYS  = %w[pointBudget].freeze
        NA_DISPLAY_KEYS = %w[pointSizePx opacityPercent colourMode].freeze

        NA_FALLBACK_DEFAULTS = {
            'pointBudget'    => 1_000_000,
            'pointSizePx'    => 2,
            'opacityPercent' => 100,
            'colourMode'     => 'rgb'
        }.freeze

        NA_FALLBACK_LIMITS = {
            'pointBudgetMin' => 10_000,
            'pointBudgetMax' => 50_000_000,
            'pointSizeMinPx' => 1,
            'pointSizeMaxPx' => 10,
            'opacityMinPct'  => 5,
            'opacityMaxPct'  => 100
        }.freeze

        def self.Na__Settings__Defaults
            from_config = Na__ConfigLoader.Na__Config__GetOr({}, 'render', 'defaults')
            self.Na__Settings__Merge(NA_FALLBACK_DEFAULTS.dup, from_config.is_a?(Hash) ? from_config : {})
        end

        # What a new session starts with: the plugin defaults, then the display
        # settings this user last chose (user config), so a budget raised
        # yesterday is still raised today.
        def self.Na__Settings__Initial
            last = Na__UserConfigStore.Na__UserConfig__Get('render', 'lastSettings', {})
            self.Na__Settings__Merge(self.Na__Settings__Defaults, last.is_a?(Hash) ? last : {})
        end

        def self.Na__Settings__Limits
            from_config = Na__ConfigLoader.Na__Config__GetOr({}, 'render', 'limits')
            NA_FALLBACK_LIMITS.merge(from_config.is_a?(Hash) ? from_config : {})
        end

        # Just the look of one cloud, from a full settings hash.
        def self.Na__Settings__DisplayPart(settings)
            NA_DISPLAY_KEYS.each_with_object({}) { |key, part| part[key] = settings[key] }
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Merge + Validate
    # -------------------------------------------------------------------------

        # Returns a NEW, valid settings hash. Unknown keys are dropped; invalid
        # values keep the current value rather than raising (they come from
        # slider drags).
        def self.Na__Settings__Merge(current, partial)
            limits  = self.Na__Settings__Limits
            result  = current.select { |key, _| NA_FALLBACK_DEFAULTS.key?(key) }
            partial = {} unless partial.is_a?(Hash)

            if partial.key?('pointBudget')
                result['pointBudget'] = self.na_clamp_int(partial['pointBudget'], limits['pointBudgetMin'], limits['pointBudgetMax'], current['pointBudget'])
            end
            if partial.key?('pointSizePx')
                result['pointSizePx'] = self.na_clamp_int(partial['pointSizePx'], limits['pointSizeMinPx'], limits['pointSizeMaxPx'], current['pointSizePx'])
            end
            if partial.key?('opacityPercent')
                result['opacityPercent'] = self.na_clamp_int(partial['opacityPercent'], limits['opacityMinPct'], limits['opacityMaxPct'], current['opacityPercent'])
            end
            result['colourMode'] = partial['colourMode'].to_s if NA_COLOUR_MODES.include?(partial['colourMode'].to_s)
            result
        end

        # A valid look for one cloud: the three display keys only.
        def self.Na__Settings__MergeDisplay(current, partial)
            base = self.Na__Settings__Defaults.merge(current.is_a?(Hash) ? current.select { |key, _| NA_DISPLAY_KEYS.include?(key) } : {})
            only = partial.is_a?(Hash) ? partial.select { |key, _| NA_DISPLAY_KEYS.include?(key) } : {}
            self.Na__Settings__DisplayPart(self.Na__Settings__Merge(base, only))
        end

        def self.Na__Settings__ChangedKeys(before, after)
            after.keys.select { |key| before[key] != after[key] }
        end

        def self.na_clamp_int(raw, min, max, fallback)
            value = Integer(raw.is_a?(Float) ? raw.round : raw)
            [[value, min.to_i].max, max.to_i].min
        rescue ArgumentError, TypeError, FloatDomainError
            fallback
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
