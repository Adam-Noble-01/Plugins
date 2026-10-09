# =============================================================================
# NA PROFILE TOOLS - DRAW PROFILE MODE - DIALOG HANDLERS
# =============================================================================
#
# FILE       : Na__ProfileTools__DrawProfile__DialogHandlers__.rb
# NAMESPACE  : Na__ProfileTools__ProfilePathTracer::Na__DrawProfile__DialogHandlers
# PURPOSE    : The Draw Profile tab's JS -> Ruby callbacks. Kept with the tab
#              rather than in the dialog manager, which binds them with one
#              line (Na__Dialog__BindCallbacks).
#
# CALLBACKS
#   na_profilepathtracer_draw_resolve_selection -> ReceiveDrawSelection
#   na_profilepathtracer_draw_save              -> ReceiveDrawSaveResult
#   na_profilepathtracer_draw_apply_local       -> ReceiveDrawLocalResult
#   na_profilepathtracer_draw_revert_local      -> ReceiveDrawLocalResult
#   na_profilepathtracer_draw_count_usage       -> ReceiveDrawKeyUsage
#   na_profilepathtracer_draw_edge_palette      -> ReceiveDrawPalette
#
# Every callback answers, failure included, so the tab never waits on a
# result that is not coming.
#
# =============================================================================

require 'json'

module Na__ProfileTools__ProfilePathTracer
    module Na__DrawProfile__DialogHandlers

    # -------------------------------------------------------------------------
    # REGION | Callback Binding
    # -------------------------------------------------------------------------

        def self.Na__DrawProfile__BindCallbacks(dialog)
            dialog.add_action_callback('na_profilepathtracer_draw_resolve_selection') do |_context|
                payload = Na__DrawProfile__TraceBridge.Na__TraceBridge__ResolveSelection(Sketchup.active_model)
                self.Na__DrawProfile__Send('Na__ProfilePathTracer__ReceiveDrawSelection', payload)
            rescue => error
                Na__DebugTools.Na__Debug__Error('Draw Profile resolve selection callback failed.', error)
                self.Na__DrawProfile__Send(
                    'Na__ProfilePathTracer__ReceiveDrawSelection',
                    { 'isResolved' => false, 'reason' => error.message, 'statusMessage' => "Selection could not be read: #{error.message}" }
                )
            end

            dialog.add_action_callback('na_profilepathtracer_draw_save') do |_context, json_payload|
                params = JSON.parse(json_payload.to_s)
                result = Na__DrawProfile__TraceBridge.Na__TraceBridge__SaveAndApply(params)
                self.Na__DrawProfile__Send('Na__ProfilePathTracer__ReceiveDrawSaveResult', result)
            rescue => error
                Na__DebugTools.Na__Debug__Error('Draw Profile save callback failed.', error)
                self.Na__DrawProfile__Send(
                    'Na__ProfilePathTracer__ReceiveDrawSaveResult',
                    { 'isSaved' => false, 'isApplied' => false, 'reason' => error.message, 'statusMessage' => "Save failed: #{error.message}" }
                )
            end

            # This trace only: the drawing goes onto the bound trace as its own
            # local profile (Update This Trace, and every Live update).
            dialog.add_action_callback('na_profilepathtracer_draw_apply_local') do |_context, json_payload|
                params = JSON.parse(json_payload.to_s)
                result = Na__DrawProfile__TraceBridge.Na__TraceBridge__ApplyLocal(params)
                self.Na__DrawProfile__Send('Na__ProfilePathTracer__ReceiveDrawLocalResult', result.merge('isLive' => params['live'] == true))
            rescue => error
                Na__DebugTools.Na__Debug__Error('Draw Profile local update callback failed.', error)
                self.Na__DrawProfile__Send(
                    'Na__ProfilePathTracer__ReceiveDrawLocalResult',
                    { 'isApplied' => false, 'reason' => error.message, 'statusMessage' => "Update failed: #{error.message}" }
                )
            end

            dialog.add_action_callback('na_profilepathtracer_draw_revert_local') do |_context, json_payload|
                params = JSON.parse(json_payload.to_s)
                result = Na__DrawProfile__TraceBridge.Na__TraceBridge__RevertLocal(params)
                self.Na__DrawProfile__Send('Na__ProfilePathTracer__ReceiveDrawLocalResult', result)
            rescue => error
                Na__DebugTools.Na__Debug__Error('Draw Profile revert callback failed.', error)
                self.Na__DrawProfile__Send(
                    'Na__ProfilePathTracer__ReceiveDrawLocalResult',
                    { 'isApplied' => false, 'isReverted' => true, 'reason' => error.message, 'statusMessage' => "Revert failed: #{error.message}" }
                )
            end

            # Edge Paint: the SSOT edge colours (refresh: true fetches them
            # again first, as Settings > Refresh does).
            dialog.add_action_callback('na_profilepathtracer_draw_edge_palette') do |_context, json_payload|
                params = json_payload.to_s.strip.empty? ? {} : JSON.parse(json_payload.to_s)
                Na__EdgeColourManager.Na__EdgeColours__ForceRefreshFromUrl if params.is_a?(Hash) && params['refresh'] == true
                self.Na__DrawProfile__Send('Na__ProfilePathTracer__ReceiveDrawPalette', self.Na__DrawProfile__PalettePayload)
            rescue => error
                Na__DebugTools.Na__Debug__Warn("Draw Profile palette failed: #{error.message}")
                self.Na__DrawProfile__Send(
                    'Na__ProfilePathTracer__ReceiveDrawPalette',
                    { 'status' => 'failed', 'entries' => [], 'statusMessage' => "Edge colours could not be read: #{error.message}" }
                )
            end

            dialog.add_action_callback('na_profilepathtracer_draw_count_usage') do |_context, json_payload|
                params = JSON.parse(json_payload.to_s)
                key    = params.is_a?(Hash) ? params['profileKey'].to_s : ''
                self.Na__DrawProfile__Send(
                    'Na__ProfilePathTracer__ReceiveDrawKeyUsage',
                    { 'profileKey' => key, 'count' => Na__DrawProfile__TraceBridge.Na__TraceBridge__CountTracesUsing(key) }
                )
            rescue => error
                Na__DebugTools.Na__Debug__Warn("Draw Profile usage count failed: #{error.message}")
                self.Na__DrawProfile__Send('Na__ProfilePathTracer__ReceiveDrawKeyUsage', { 'profileKey' => '', 'count' => 0 })
            end
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Ruby -> JS
    # -------------------------------------------------------------------------

        # @delegate: ../01__AppCore/Na__ProfileTools__AppCore__DialogManager__
        def self.Na__DrawProfile__Send(function_name, payload)
            Na__DialogManager.Na__Dialog__SendToJs(function_name, payload)
        end

        # @delegate: ../02__AppData/Na__ProfileTools__AppData__EdgeColourManager__
        def self.Na__DrawProfile__PalettePayload
            entries = Na__EdgeColourManager.Na__EdgeColours__Palette.map do |entry|
                {
                    'id'          => entry['MteKey'].to_s,
                    'name'        => (entry['SwatchName'] || entry['SketchUpName']).to_s,
                    'material'    => entry['SketchUpName'].to_s,
                    'hex'         => entry['HexValue'].to_s,
                    'series'      => entry['Series'].to_s,
                    'description' => entry['Description'].to_s
                }
            end
            { 'status' => Na__EdgeColourManager.Na__EdgeColours__LoadStatus.to_s, 'entries' => entries }
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
