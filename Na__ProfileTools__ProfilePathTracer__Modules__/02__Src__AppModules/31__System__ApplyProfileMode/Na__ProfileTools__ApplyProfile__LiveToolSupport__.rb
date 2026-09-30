# =============================================================================
# NA PROFILE TOOLS - APPLY PROFILE - LIVE TOOL SUPPORT
# =============================================================================
#
# FILE       : Na__ProfileTools__ApplyProfile__LiveToolSupport__.rb
# NAMESPACE  : Na__ProfileTools__ProfilePathTracer::Na__LiveToolRegistry
#              Na__ProfileTools__ProfilePathTracer::Na__LiveToolPlacementMixin
# PURPOSE    : Lets the dialog reach whichever preview tool is running — the
#              Interactive path tool or the Selection preview — and change its
#              placement settings in place.
#
# WHY
#   Both tools draw a live preview from settings the dialog holds: profile,
#   rotation, mirrors, insert point, Reverse and the path offsets. Only
#   Reverse ever reached the running tool; everything else was read once at
#   Generate and then frozen, so picking another profile mid-preview changed
#   the dialog and not the preview. The registry finds the running tool, and
#   the mixin gives both tools one way to take new settings.
#
# =============================================================================

module Na__ProfileTools__ProfilePathTracer

    # -------------------------------------------------------------------------
    # REGION | Live Tool Registry
    # -------------------------------------------------------------------------

    module Na__LiveToolRegistry

        # SketchUp exposes no way to fetch the active Ruby tool object back from
        # the model, so the registry keeps its own reference. Guarded so a hot
        # reload mid-preview cannot orphan the tool that is running.
        @na_active_tool = nil unless defined?(@na_active_tool)

        def self.Na__LiveTool__Register(tool)
            @na_active_tool = tool
        end

        # Clears only when the tool asking is the one registered, so a late
        # deactivate can never unregister the tool that replaced it.
        def self.Na__LiveTool__Clear(tool)
            @na_active_tool = nil if @na_active_tool.equal?(tool)
        end

        def self.Na__LiveTool__Active
            @na_active_tool
        end

    end

    # -------------------------------------------------------------------------
    # REGION | Placement Mixin (shared by both preview tools)
    # -------------------------------------------------------------------------

    # The including tool keeps its settings in the ivars below and implements
    # Na__LiveTool__OnPlacementChanged to redraw from them.
    module Na__LiveToolPlacementMixin

        NA_LIVE_SOURCE_LIBRARY = 'library'.freeze
        NA_LIVE_SOURCE_SCENE   = 'scene'.freeze

        # The library is re-read from disk on every key lookup, so the dialog
        # resolves a profile only when it has actually changed. A scene profile
        # is held in memory, and re-picking one does not change the dialog's
        # key, so scene mode always re-resolves.
        def Na__LiveTool__ProfileChanged?(profile_key, profile_source_mode)
            source_mode = profile_source_mode.to_s.empty? ? NA_LIVE_SOURCE_LIBRARY : profile_source_mode.to_s
            return true if source_mode == NA_LIVE_SOURCE_SCENE
            return true if (@na_profile_source_mode || NA_LIVE_SOURCE_LIBRARY).to_s != source_mode
            @na_profile_key.to_s != profile_key.to_s
        end

        # Every key is optional; only those present change.
        #   :profile_key, :profile_data, :profile_source_mode   (a set)
        #   :rotation_step, :toggle_states, :reverse_direction,
        #   :origin_offset, :path_offsets (draw order, as typed)
        def Na__LiveTool__ApplyPlacement(settings)
            settings = {} unless settings.is_a?(Hash)

            if settings[:profile_data].is_a?(Hash)
                @na_profile_key         = settings[:profile_key]
                @na_profile_data        = settings[:profile_data]
                @na_profile_source_mode = settings[:profile_source_mode] || NA_LIVE_SOURCE_LIBRARY
            end
            @na_rotation_step     = settings[:rotation_step].to_i % 4    if settings.key?(:rotation_step)
            @na_toggle_states     = settings[:toggle_states] || {}       if settings.key?(:toggle_states)
            @na_reverse_direction = settings[:reverse_direction] == true if settings.key?(:reverse_direction)
            @na_origin_offset     = settings[:origin_offset]             if settings.key?(:origin_offset)
            @na_path_offsets      = settings[:path_offsets]              if settings.key?(:path_offsets)

            self.Na__LiveTool__OnPlacementChanged
            true
        end

    end

end

# =============================================================================
# END OF FILE
# =============================================================================
