# =============================================================================
# NA NOBLE3D MODELLING TOOLS - SELECT SIMILAR FILTER - DIALOG MANAGER
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__SelectSimilarFilter__DialogManager__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__SelectSimilarFilter__DialogManager
# PURPOSE    : Manage the HtmlDialog lifecycle, selection observer, and live reference readout
# CREATED    : 2026
#
# =============================================================================

require 'json'

module Na__Noble3dModellingTools
    module Na__SelectSimilarFilter__DialogManager

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_DIALOG_TITLE              = 'Select Similar Filter'.freeze
        NA_DIALOG_PREFERENCES_KEY    = 'Na__Noble3dModellingTools__SelectSimilarFilter'.freeze
        NA_DIALOG_WIDTH              = 400
        NA_DIALOG_HEIGHT             = 480
        NA_DEFAULT_THRESHOLD_MM      = 10
        NA_DEFAULT_BBOX_THRESHOLD_MM = 0

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Module State
# -----------------------------------------------------------------------------

        @na_dialog             = nil
        @na_selection_observer = nil

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Dialog Lifecycle
# -----------------------------------------------------------------------------

        # FUNCTION | Show the Select Similar Filter Dialog
        # ------------------------------------------------------------
        # Creates a new dialog or brings an existing visible one to
        # the front. Attaches the selection observer on first open.
        #
        # @param model [Sketchup::Model] Active model at launch time
        # ------------------------------------------------------------
        def self.Na__SelectSimilarFilter__DialogManager__ShowDialog(model)
            if @na_dialog && @na_dialog.visible?
                @na_dialog.bring_to_front
                na_push_reference_summary(@na_dialog, model.selection)
                return @na_dialog
            end

            @na_dialog = UI::HtmlDialog.new(
                dialog_title:    NA_DIALOG_TITLE,
                preferences_key: NA_DIALOG_PREFERENCES_KEY,
                scrollable:      false,
                resizable:       true,
                width:           NA_DIALOG_WIDTH,
                height:          NA_DIALOG_HEIGHT,
                style:           UI::HtmlDialog::STYLE_DIALOG
            )

            @na_dialog.set_html(na_generate_html(model.selection))
            na_setup_dialog_callbacks(@na_dialog)
            @na_dialog.set_on_closed { na_on_dialog_closed }
            @na_dialog.show

            na_attach_selection_observer(model)
            @na_dialog
        end
        # ------------------------------------------------------------

        # FUNCTION | Reset the Dialog State (used by the plugin reload manager)
        # ------------------------------------------------------------
        # Closes any open dialog and detaches the selection observer so a
        # "Reload Plugin Data" click always leaves a clean slate rather than
        # a stale dialog window bound to superseded Ruby closures.
        # ------------------------------------------------------------
        def self.Na__SelectSimilarFilter__DialogManager__ResetDialog
            @na_dialog.close if @na_dialog && @na_dialog.visible?
            na_detach_selection_observer
            @na_dialog = nil
        end
        # ------------------------------------------------------------

        # FUNCTION | Handle Dialog Close Cleanup
        # ------------------------------------------------------------
        def self.na_on_dialog_closed
            na_detach_selection_observer
            @na_dialog = nil
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Selection Observer Management
# -----------------------------------------------------------------------------

        # FUNCTION | Attach Selection Observer to the Active Model Selection
        # ------------------------------------------------------------
        def self.na_attach_selection_observer(model)
            return if @na_selection_observer

            @na_selection_observer = Na__SelectSimilarFilter__SelectionObserver.new
            model.selection.add_observer(@na_selection_observer)
        rescue => error
            puts "[Na__Noble3dModellingTools] SelectSimilarFilter: observer attach failed: #{error.class}: #{error.message}"
        end
        # ------------------------------------------------------------

        # FUNCTION | Detach and Discard the Selection Observer
        # ------------------------------------------------------------
        def self.na_detach_selection_observer
            return unless @na_selection_observer

            model = Sketchup.active_model
            model.selection.remove_observer(@na_selection_observer) if model
            @na_selection_observer = nil
        rescue => error
            puts "[Na__Noble3dModellingTools] SelectSimilarFilter: observer detach warning: #{error.class}: #{error.message}"
        end
        # ------------------------------------------------------------

        # FUNCTION | Handle Incoming Selection Change from Observer
        # ------------------------------------------------------------
        # Triggered by Na__SelectSimilarFilter__SelectionObserver. Pushes a
        # live "N face(s), M edge(s) selected" readout to the open dialog.
        # No-ops if the dialog is closed.
        # ------------------------------------------------------------
        def self.Na__SelectSimilarFilter__DialogManager__HandleSelectionChanged
            return unless @na_dialog && @na_dialog.visible?

            model = Sketchup.active_model
            return unless model

            na_push_reference_summary(@na_dialog, model.selection)
        rescue => error
            puts "[Na__Noble3dModellingTools] SelectSimilarFilter: HandleSelectionChanged error: #{error.class}: #{error.message}"
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Live UI Push Helpers
# -----------------------------------------------------------------------------

        # FUNCTION | Push the Current Reference Selection Summary to the Dialog
        # ------------------------------------------------------------
        def self.na_push_reference_summary(dialog, selection)
            na_execute_json_function(dialog, 'Na__SelectSimilarFilter__ReceiveReferenceSummary', na_build_reference_summary(selection))
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Build the Combined Geometry + Container Reference Summary
        # ------------------------------------------------------------
        # Both modes' counts are always pushed together so the dialog's JS
        # can switch which line it displays purely on the client side when
        # the user toggles mode, without waiting on a fresh selection event.
        # ------------------------------------------------------------
        def self.na_build_reference_summary(selection)
            geometry_summary  = Na__SelectSimilarFilter__SimilarityMatcher.Na__SelectSimilarFilter__SimilarityMatcher__ReferenceSummary(selection)
            container_summary = Na__SelectSimilarFilter__ContainerMatcher.Na__SelectSimilarFilter__ContainerMatcher__ReferenceSummary(selection)
            geometry_summary.merge(container_summary)
        end
        # ------------------------------------------------------------

        # FUNCTION | Push a Result Status Message to the Dialog
        # ------------------------------------------------------------
        def self.na_push_result(dialog, message_text, variant)
            na_execute_json_function(dialog, 'Na__SelectSimilarFilter__ReceiveResult', { message: message_text, variant: variant })
        end
        # ------------------------------------------------------------

        # FUNCTION | Execute a Named JS Function in the Dialog with a JSON Payload
        # ------------------------------------------------------------
        def self.na_execute_json_function(dialog, js_function_name, payload_hash)
            return unless dialog && dialog.visible?

            script = <<~JS
                (function() {
                    if (typeof #{js_function_name} === 'function') {
                        #{js_function_name}(#{JSON.generate(payload_hash)});
                    }
                })();
            JS
            dialog.execute_script(script)
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Dialog Callbacks
# -----------------------------------------------------------------------------

        # FUNCTION | Register Dialog Action Callbacks
        # ------------------------------------------------------------
        def self.na_setup_dialog_callbacks(dialog)
            dialog.add_action_callback('select_similar') do |_context, options_json|
                na_execute_similar_selection(dialog, options_json)
            end

            dialog.add_action_callback('select_similar_containers') do |_context, options_json|
                na_execute_similar_containers_selection(dialog, options_json)
            end

            dialog.add_action_callback('close') do |_context|
                dialog.close
            end
        end
        # ------------------------------------------------------------

        # FUNCTION | Execute the Select Similar Operation from Dialog Callback
        # ------------------------------------------------------------
        def self.na_execute_similar_selection(dialog, options_json)
            model = Sketchup.active_model
            return na_push_result(dialog, 'No active model available.', 'error') unless model

            options      = JSON.parse(options_json)
            match_faces  = !!options['match_faces']
            match_edges  = !!options['match_edges']
            threshold_mm = options.fetch('threshold_mm', NA_DEFAULT_THRESHOLD_MM).to_f

            return na_push_result(dialog, 'Enable Faces and/or Edges before running Select Similar.', 'warn') unless match_faces || match_edges

            selection = model.selection
            reference_entities = selection.to_a
            return na_push_result(dialog, 'Select one or more faces/edges first, then click Select Similar.', 'warn') if reference_entities.empty?

            threshold_internal = threshold_mm.abs.mm
            matches = Na__SelectSimilarFilter__SimilarityMatcher.Na__SelectSimilarFilter__SimilarityMatcher__FindMatches(
                model.active_entities,
                reference_entities,
                match_faces,
                match_edges,
                threshold_internal
            )

            all_matches = matches[:faces] + matches[:edges]
            return na_push_result(dialog, 'No similar entities found within the current threshold and selection type(s).', 'warn') if all_matches.empty?

            selection.clear
            selection.add(all_matches)

            na_push_result(
                dialog,
                "Selected #{all_matches.length} #{all_matches.length == 1 ? 'entity' : 'entities'} " \
                "(#{matches[:faces].length} face(s), #{matches[:edges].length} edge(s)) within #{na_format_mm(threshold_mm)}mm.",
                'success'
            )
        rescue => error
            na_push_result(dialog, "Select Similar failed: #{error.class}: #{error.message}", 'error')
        end
        # ------------------------------------------------------------

        # FUNCTION | Execute the Select Similar Containers Operation from Dialog Callback
        # ------------------------------------------------------------
        def self.na_execute_similar_containers_selection(dialog, options_json)
            model = Sketchup.active_model
            return na_push_result(dialog, 'No active model available.', 'error') unless model

            options           = JSON.parse(options_json)
            match_definition  = !!options['match_definition']
            match_bbox        = !!options['match_bbox']
            bbox_threshold_mm = options.fetch('bbox_threshold_mm', NA_DEFAULT_BBOX_THRESHOLD_MM).to_f
            deep_nested       = !!options['deep_nested']

            return na_push_result(dialog, 'Enable Same Definition and/or Bounding Box before running Select Similar.', 'warn') unless match_definition || match_bbox

            selection = model.selection
            reference_entities = selection.to_a
            return na_push_result(dialog, 'Select one or more groups/components first, then click Select Similar.', 'warn') if reference_entities.empty?

            bbox_threshold_internal = bbox_threshold_mm.abs.mm
            result = Na__SelectSimilarFilter__ContainerMatcher.Na__SelectSimilarFilter__ContainerMatcher__FindMatches(
                model,
                reference_entities,
                match_definition,
                match_bbox,
                bbox_threshold_internal,
                deep_nested
            )

            return na_push_result(dialog, 'No similar groups/components found within the current threshold and match type(s).', 'warn') if result[:matches].empty?

            selection.clear
            selection.add(result[:matches])

            na_push_result(dialog, na_containers_result_message(result, match_bbox, bbox_threshold_mm), 'success')
        rescue => error
            na_push_result(dialog, "Select Similar Containers failed: #{error.class}: #{error.message}", 'error')
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Build the Result Message for a Select Similar Containers Run
        # ------------------------------------------------------------
        def self.na_containers_result_message(result, match_bbox, bbox_threshold_mm)
            total  = result[:matches].length
            detail = result[:promoted_count] > 0 ? " (#{result[:shallow_count]} at current level, #{result[:promoted_count]} promoted from nested)" : ''
            scope  = match_bbox ? " Bounding-box tolerance: #{na_format_mm(bbox_threshold_mm)}mm." : ''

            message = "Selected #{total} #{total == 1 ? 'entity' : 'entities'}#{detail}.#{scope}"

            if result[:shared_definition_promotion_count] > 0
                plural = result[:shared_definition_promotion_count] == 1 ? 'instance' : 'instances'
                message += " Note: #{result[:shared_definition_promotion_count]} promoted #{plural} came from a component used elsewhere in the model — the change applies to every placement of that component, as with any edit made inside it."
            end

            message
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Format an mm Value Without Trailing Zeros
        # ------------------------------------------------------------
        def self.na_format_mm(value_mm)
            formatted = format('%.3f', value_mm.to_f)
            formatted.sub(/0+$/, '').sub(/\.$/, '')
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | HTML Generation
# -----------------------------------------------------------------------------

        # FUNCTION | Generate the Initial Dialog HTML
        # ------------------------------------------------------------
        def self.na_generate_html(selection)
            initial_summary = na_build_reference_summary(selection)

            <<~HTML
                <!DOCTYPE html>
                <html lang="en">
                <head>
                    <meta charset="UTF-8">
                    <meta name="viewport" content="width=device-width, initial-scale=1.0">
                    <style>
                        #{na_load_stylesheet}
                    </style>
                </head>
                <body>
                    <div class="naSelSim__Shell">
                        <div class="naSelSim__Header">
                            <h2 class="naSelSim__Title">Select Similar Filter</h2>
                            <p class="naSelSim__Subtitle" id="naSelectSimilarSubtitle">Select one or more faces/edges as a reference, then click Select Similar.</p>
                            <p class="naSelSim__ReferenceLine" id="naSelectSimilarReferenceLine"></p>
                        </div>

                        <div class="naSelSim__ModeRow">
                            <button class="naSelSim__ModeBtn naSelSim__ModeBtn--active" id="naSelectSimilarModeGeometry" data-mode="geometry" type="button">Geometry</button>
                            <button class="naSelSim__ModeBtn" id="naSelectSimilarModeContainers" data-mode="containers" type="button">Groups &amp; Components</button>
                        </div>

                        <div class="naSelSim__Body">
                            <div class="naSelSim__Panel" id="naSelSimGeometryPanel">
                                <div class="naSelSim__OptionRow">
                                    <label class="naSelSim__CheckboxLabel">
                                        <input type="checkbox" id="naSelectSimilarMatchFaces" checked>
                                        <span>Faces</span>
                                    </label>
                                    <label class="naSelSim__CheckboxLabel">
                                        <input type="checkbox" id="naSelectSimilarMatchEdges" checked>
                                        <span>Edges</span>
                                    </label>
                                </div>

                                <div class="naSelSim__ThresholdRow">
                                    <label class="naSelSim__ThresholdLabel" for="naSelectSimilarThreshold">Similarity Threshold (mm)</label>
                                    <input type="number" id="naSelectSimilarThreshold" class="naSelSim__ThresholdInput" value="#{NA_DEFAULT_THRESHOLD_MM}" min="0" step="0.5">
                                </div>

                                <p class="naSelSim__HelpText">Faces are matched by shape (same vertex/hole count and edge lengths); edges are matched by length. Search is limited to the entities at the current editing level (inside the open group/component, or the model root).</p>
                            </div>

                            <div class="naSelSim__Panel naSelSim__Panel--hidden" id="naSelSimContainersPanel">
                                <div class="naSelSim__OptionRow">
                                    <label class="naSelSim__CheckboxLabel">
                                        <input type="checkbox" id="naSelectSimilarMatchDefinition" checked>
                                        <span>Same definition</span>
                                    </label>
                                    <label class="naSelSim__CheckboxLabel">
                                        <input type="checkbox" id="naSelectSimilarMatchBbox">
                                        <span>Bounding box</span>
                                    </label>
                                </div>

                                <div class="naSelSim__ThresholdRow">
                                    <label class="naSelSim__ThresholdLabel" for="naSelectSimilarBboxThreshold">Bounding-Box Threshold (mm)</label>
                                    <input type="number" id="naSelectSimilarBboxThreshold" class="naSelSim__ThresholdInput" value="#{NA_DEFAULT_BBOX_THRESHOLD_MM}" min="0" step="0.5" disabled>
                                </div>

                                <label class="naSelSim__CheckboxLabel naSelSim__DeepNestedRow">
                                    <input type="checkbox" id="naSelectSimilarDeepNested">
                                    <span>Deep Nested</span>
                                </label>

                                <p class="naSelSim__HelpText">Same definition matches repeated placements of the same component (or copies of the same group). Bounding box additionally matches differently-defined groups/components whose size is within the threshold above — 0mm requires an exact size match; raise it to be more forgiving. Deep Nested reaches into nested groups/components below the current level and promotes any match up to the current level in place before selecting it, so entities nested at different depths can be grabbed cumulatively in one pass — something manual SketchUp selection cannot do.</p>
                            </div>

                            <div class="naSelSim__StatusBanner naSelSim__StatusBanner--hidden" id="naSelectSimilarStatusBanner"></div>
                        </div>

                        <div class="naSelSim__Footer">
                            <button class="naSelSim__Btn naSelSim__Btn--muted" id="naSelectSimilarCloseBtn">Close</button>
                            <button class="naSelSim__Btn naSelSim__Btn--primary" id="naSelectSimilarRunBtn">Select Similar</button>
                        </div>
                    </div>

                    <script>
                        #{na_dialog_js(JSON.generate(initial_summary))}
                    </script>
                </body>
                </html>
            HTML
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Load the Dialog Stylesheet from Co-Located CSS File
        # ------------------------------------------------------------
        def self.na_load_stylesheet
            File.read(na_stylesheet_file_path)
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Resolve the Co-Located Stylesheet Path
        # ------------------------------------------------------------
        def self.na_stylesheet_file_path
            File.join(__dir__, 'Na__Noble3dModellingTools__SelectSimilarFilter__Styles__.css')
        end
        # ------------------------------------------------------------

        # FUNCTION | Dialog JavaScript
        # ------------------------------------------------------------
        def self.na_dialog_js(initial_summary_json)
            <<~JS
                'use strict';

                var naSelSimCurrentMode = 'geometry';
                var naSelSimLastSummary = #{initial_summary_json};

                function na_set_reference_line(summary) {
                    naSelSimLastSummary = summary || naSelSimLastSummary;
                    var line = document.getElementById('naSelectSimilarReferenceLine');

                    if (naSelSimCurrentMode === 'containers') {
                        var groupCount = naSelSimLastSummary.group_count || 0;
                        var componentCount = naSelSimLastSummary.component_count || 0;
                        line.textContent = 'Reference: ' + groupCount + (groupCount === 1 ? ' group' : ' groups') +
                            ', ' + componentCount + (componentCount === 1 ? ' component' : ' components') + ' selected.';
                        return;
                    }

                    var faceCount = naSelSimLastSummary.face_count || 0;
                    var edgeCount = naSelSimLastSummary.edge_count || 0;
                    line.textContent = 'Reference: ' + faceCount + (faceCount === 1 ? ' face' : ' faces') +
                        ', ' + edgeCount + (edgeCount === 1 ? ' edge' : ' edges') + ' selected.';
                }

                function na_set_status_banner(message, variant) {
                    var banner = document.getElementById('naSelectSimilarStatusBanner');
                    if (!message) {
                        banner.className = 'naSelSim__StatusBanner naSelSim__StatusBanner--hidden';
                        banner.textContent = '';
                        return;
                    }
                    banner.className = 'naSelSim__StatusBanner naSelSim__StatusBanner--' + (variant || 'warn');
                    banner.textContent = message;
                }

                function na_set_mode(mode) {
                    naSelSimCurrentMode = mode;
                    var isContainers = mode === 'containers';

                    document.getElementById('naSelSimGeometryPanel').classList.toggle('naSelSim__Panel--hidden', isContainers);
                    document.getElementById('naSelSimContainersPanel').classList.toggle('naSelSim__Panel--hidden', !isContainers);
                    document.getElementById('naSelectSimilarModeGeometry').classList.toggle('naSelSim__ModeBtn--active', !isContainers);
                    document.getElementById('naSelectSimilarModeContainers').classList.toggle('naSelSim__ModeBtn--active', isContainers);

                    document.getElementById('naSelectSimilarSubtitle').textContent = isContainers ?
                        'Select one or more groups/components as a reference, then click Select Similar.' :
                        'Select one or more faces/edges as a reference, then click Select Similar.';
                    document.getElementById('naSelectSimilarRunBtn').textContent = isContainers ?
                        'Select Similar Containers' : 'Select Similar';

                    na_set_status_banner(null);
                    na_set_reference_line(naSelSimLastSummary);
                }

                document.getElementById('naSelectSimilarModeGeometry').addEventListener('click', function() {
                    na_set_mode('geometry');
                });
                document.getElementById('naSelectSimilarModeContainers').addEventListener('click', function() {
                    na_set_mode('containers');
                });

                document.getElementById('naSelectSimilarMatchBbox').addEventListener('change', function() {
                    document.getElementById('naSelectSimilarBboxThreshold').disabled = !this.checked;
                });

                // Called by Ruby via execute_script when the selection changes
                function Na__SelectSimilarFilter__ReceiveReferenceSummary(summary) {
                    na_set_reference_line(summary);
                }

                // Called by Ruby via execute_script after a Select Similar run
                function Na__SelectSimilarFilter__ReceiveResult(payload) {
                    na_set_status_banner(payload.message || '', payload.variant || 'warn');
                }

                function na_run_geometry_mode() {
                    var matchFaces = document.getElementById('naSelectSimilarMatchFaces').checked;
                    var matchEdges = document.getElementById('naSelectSimilarMatchEdges').checked;
                    var thresholdInput = document.getElementById('naSelectSimilarThreshold');
                    var thresholdMm = parseFloat(thresholdInput.value);
                    if (isNaN(thresholdMm) || thresholdMm < 0) {
                        thresholdMm = 0;
                    }

                    if (!matchFaces && !matchEdges) {
                        na_set_status_banner('Enable Faces and/or Edges before running Select Similar.', 'warn');
                        return;
                    }

                    na_set_status_banner('Searching for similar entities...', 'warn');
                    window.sketchup.select_similar(JSON.stringify({
                        match_faces: matchFaces,
                        match_edges: matchEdges,
                        threshold_mm: thresholdMm
                    }));
                }

                function na_run_containers_mode() {
                    var matchDefinition = document.getElementById('naSelectSimilarMatchDefinition').checked;
                    var matchBbox = document.getElementById('naSelectSimilarMatchBbox').checked;
                    var bboxThresholdInput = document.getElementById('naSelectSimilarBboxThreshold');
                    var bboxThresholdMm = parseFloat(bboxThresholdInput.value);
                    if (isNaN(bboxThresholdMm) || bboxThresholdMm < 0) {
                        bboxThresholdMm = 0;
                    }
                    var deepNested = document.getElementById('naSelectSimilarDeepNested').checked;

                    if (!matchDefinition && !matchBbox) {
                        na_set_status_banner('Enable Same Definition and/or Bounding Box before running Select Similar.', 'warn');
                        return;
                    }

                    na_set_status_banner('Searching for similar groups/components...', 'warn');
                    window.sketchup.select_similar_containers(JSON.stringify({
                        match_definition: matchDefinition,
                        match_bbox: matchBbox,
                        bbox_threshold_mm: bboxThresholdMm,
                        deep_nested: deepNested
                    }));
                }

                document.getElementById('naSelectSimilarRunBtn').addEventListener('click', function() {
                    if (naSelSimCurrentMode === 'containers') {
                        na_run_containers_mode();
                    } else {
                        na_run_geometry_mode();
                    }
                });

                document.getElementById('naSelectSimilarCloseBtn').addEventListener('click', function() {
                    window.sketchup.close();
                });

                na_set_reference_line(naSelSimLastSummary);
            JS
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__SelectSimilarFilter__DialogManager
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
