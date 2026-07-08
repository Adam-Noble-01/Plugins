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

        NA_DIALOG_TITLE           = 'Select Similar Filter'.freeze
        NA_DIALOG_PREFERENCES_KEY = 'Na__Noble3dModellingTools__SelectSimilarFilter'.freeze
        NA_DIALOG_WIDTH           = 380
        NA_DIALOG_HEIGHT          = 420
        NA_DEFAULT_THRESHOLD_MM   = 10

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
            summary = Na__SelectSimilarFilter__SimilarityMatcher.Na__SelectSimilarFilter__SimilarityMatcher__ReferenceSummary(selection)
            na_execute_json_function(dialog, 'Na__SelectSimilarFilter__ReceiveReferenceSummary', summary)
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
            initial_summary = Na__SelectSimilarFilter__SimilarityMatcher.Na__SelectSimilarFilter__SimilarityMatcher__ReferenceSummary(selection)

            <<~HTML
                <!DOCTYPE html>
                <html lang="en">
                <head>
                    <meta charset="UTF-8">
                    <meta name="viewport" content="width=device-width, initial-scale=1.0">
                    <style>
                        #{na_dialog_css}
                    </style>
                </head>
                <body>
                    <div class="naSelectSimilar__Header">
                        <h2 class="naSelectSimilar__Title">Select Similar Filter</h2>
                        <p class="naSelectSimilar__Subtitle">Select one or more faces/edges as a reference, then click Select Similar.</p>
                        <p class="naSelectSimilar__ReferenceLine" id="naSelectSimilarReferenceLine"></p>
                    </div>

                    <div class="naSelectSimilar__Body">
                        <div class="naSelectSimilar__OptionRow">
                            <label class="naSelectSimilar__CheckboxLabel">
                                <input type="checkbox" id="naSelectSimilarMatchFaces" checked>
                                <span>Faces</span>
                            </label>
                            <label class="naSelectSimilar__CheckboxLabel">
                                <input type="checkbox" id="naSelectSimilarMatchEdges" checked>
                                <span>Edges</span>
                            </label>
                        </div>

                        <div class="naSelectSimilar__ThresholdRow">
                            <label class="naSelectSimilar__ThresholdLabel" for="naSelectSimilarThreshold">Similarity Threshold (mm)</label>
                            <input type="number" id="naSelectSimilarThreshold" class="naSelectSimilar__ThresholdInput" value="#{NA_DEFAULT_THRESHOLD_MM}" min="0" step="0.5">
                        </div>

                        <p class="naSelectSimilar__HelpText">Faces are matched by shape (same vertex/hole count and edge lengths); edges are matched by length. Search is limited to the entities at the current editing level (inside the open group/component, or the model root).</p>

                        <div class="naSelectSimilar__StatusBanner naSelectSimilar__StatusBanner--hidden" id="naSelectSimilarStatusBanner"></div>
                    </div>

                    <div class="naSelectSimilar__Footer">
                        <button class="naSelectSimilar__Btn naSelectSimilar__Btn--muted" id="naSelectSimilarCloseBtn">Close</button>
                        <button class="naSelectSimilar__Btn naSelectSimilar__Btn--primary" id="naSelectSimilarRunBtn">Select Similar</button>
                    </div>

                    <script>
                        #{na_dialog_js(JSON.generate(initial_summary))}
                    </script>
                </body>
                </html>
            HTML
        end
        # ------------------------------------------------------------

        # FUNCTION | Dialog CSS
        # ------------------------------------------------------------
        def self.na_dialog_css
            <<~CSS
                *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

                body {
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Arial, sans-serif;
                    font-size: 13px;
                    background: #f4f4f6;
                    color: #222;
                    display: flex;
                    flex-direction: column;
                    height: 100vh;
                    overflow: hidden;
                }

                .naSelectSimilar__Header {
                    padding: 14px 18px 12px;
                    background: #fff;
                    border-bottom: 1px solid #e0e0e0;
                    flex-shrink: 0;
                }

                .naSelectSimilar__Title {
                    font-size: 15px;
                    font-weight: 600;
                    color: #111;
                    margin-bottom: 3px;
                }

                .naSelectSimilar__Subtitle {
                    font-size: 12px;
                    color: #666;
                    margin-bottom: 8px;
                }

                .naSelectSimilar__ReferenceLine {
                    font-size: 12px;
                    font-weight: 600;
                    color: #2d7dd2;
                }

                .naSelectSimilar__Body {
                    flex: 1;
                    overflow-y: auto;
                    padding: 14px 18px;
                    display: flex;
                    flex-direction: column;
                    gap: 14px;
                }

                .naSelectSimilar__OptionRow {
                    display: flex;
                    gap: 20px;
                }

                .naSelectSimilar__CheckboxLabel {
                    display: flex;
                    align-items: center;
                    gap: 7px;
                    font-weight: 500;
                    cursor: pointer;
                }

                .naSelectSimilar__CheckboxLabel input[type="checkbox"] {
                    width: 15px;
                    height: 15px;
                    cursor: pointer;
                    accent-color: #2d7dd2;
                }

                .naSelectSimilar__ThresholdRow {
                    display: flex;
                    flex-direction: column;
                    gap: 6px;
                }

                .naSelectSimilar__ThresholdLabel {
                    font-weight: 500;
                    color: #333;
                }

                .naSelectSimilar__ThresholdInput {
                    padding: 7px 9px;
                    border: 1px solid #ccc;
                    border-radius: 4px;
                    font-size: 13px;
                    width: 120px;
                }

                .naSelectSimilar__ThresholdInput:focus {
                    outline: none;
                    border-color: #2d7dd2;
                }

                .naSelectSimilar__HelpText {
                    font-size: 11px;
                    color: #888;
                    line-height: 1.5;
                }

                .naSelectSimilar__StatusBanner {
                    padding: 9px 11px;
                    border-radius: 4px;
                    font-size: 12px;
                    line-height: 1.4;
                    background: #fff8e1;
                    color: #795548;
                    border: 1px solid #ffe082;
                }

                .naSelectSimilar__StatusBanner--hidden { display: none; }

                .naSelectSimilar__StatusBanner--success {
                    background: #e8f5e9;
                    color: #2e7d32;
                    border-color: #a5d6a7;
                }

                .naSelectSimilar__StatusBanner--warn {
                    background: #fff8e1;
                    color: #795548;
                    border-color: #ffe082;
                }

                .naSelectSimilar__StatusBanner--error {
                    background: #ffebee;
                    color: #c62828;
                    border-color: #ef9a9a;
                }

                .naSelectSimilar__Footer {
                    display: flex;
                    align-items: center;
                    justify-content: flex-end;
                    padding: 12px 16px;
                    background: #fff;
                    border-top: 1px solid #e0e0e0;
                    gap: 8px;
                    flex-shrink: 0;
                }

                .naSelectSimilar__Btn {
                    padding: 7px 16px;
                    border: none;
                    border-radius: 4px;
                    font-size: 13px;
                    font-weight: 500;
                    cursor: pointer;
                    transition: background 0.15s, opacity 0.15s;
                }

                .naSelectSimilar__Btn--primary {
                    background: #2d7dd2;
                    color: #fff;
                }

                .naSelectSimilar__Btn--primary:hover { background: #2268b8; }

                .naSelectSimilar__Btn--muted {
                    background: #e8e8e8;
                    color: #444;
                }

                .naSelectSimilar__Btn--muted:hover { background: #d8d8d8; }
            CSS
        end
        # ------------------------------------------------------------

        # FUNCTION | Dialog JavaScript
        # ------------------------------------------------------------
        def self.na_dialog_js(initial_summary_json)
            <<~JS
                'use strict';

                function na_set_reference_line(summary) {
                    var line = document.getElementById('naSelectSimilarReferenceLine');
                    var faceCount = summary.face_count || 0;
                    var edgeCount = summary.edge_count || 0;
                    line.textContent = 'Reference: ' + faceCount + (faceCount === 1 ? ' face' : ' faces') +
                        ', ' + edgeCount + (edgeCount === 1 ? ' edge' : ' edges') + ' selected.';
                }

                function na_set_status_banner(message, variant) {
                    var banner = document.getElementById('naSelectSimilarStatusBanner');
                    if (!message) {
                        banner.className = 'naSelectSimilar__StatusBanner naSelectSimilar__StatusBanner--hidden';
                        banner.textContent = '';
                        return;
                    }
                    banner.className = 'naSelectSimilar__StatusBanner naSelectSimilar__StatusBanner--' + (variant || 'warn');
                    banner.textContent = message;
                }

                // Called by Ruby via execute_script when the selection changes
                function Na__SelectSimilarFilter__ReceiveReferenceSummary(summary) {
                    na_set_reference_line(summary);
                }

                // Called by Ruby via execute_script after a Select Similar run
                function Na__SelectSimilarFilter__ReceiveResult(payload) {
                    na_set_status_banner(payload.message || '', payload.variant || 'warn');
                }

                document.getElementById('naSelectSimilarRunBtn').addEventListener('click', function() {
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
                });

                document.getElementById('naSelectSimilarCloseBtn').addEventListener('click', function() {
                    window.sketchup.close();
                });

                na_set_reference_line(#{initial_summary_json});
            JS
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__SelectSimilarFilter__DialogManager
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
