# =============================================================================
# NA NOBLE3D MODELLING TOOLS - MATERIAL SWAP IN SELECTION - DIALOG MANAGER
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__MaterialSwapInSelection__DialogManager__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__MaterialSwapInSelection__DialogManager
# PURPOSE    : Manage the two-step wizard HtmlDialog, observer lifecycle, and live UI sync
# CREATED    : 2026
#
# =============================================================================

require 'json'
require 'set'

module Na__Noble3dModellingTools
    module Na__MaterialSwapInSelection__DialogManager

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_DIALOG_TITLE           = 'Material Swap In Selection'.freeze
        NA_DIALOG_PREFERENCES_KEY = 'Na__Noble3dModellingTools__MaterialSwapInSelection'.freeze
        NA_DIALOG_WIDTH           = 520
        NA_DIALOG_HEIGHT          = 680
        NA_OPERATION_NAME         = 'Material Swap In Selection'.freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Module State
# -----------------------------------------------------------------------------

        @na_dialog                   = nil
        @na_selection_observer       = nil
        @na_step                     = :step1
        @na_current_model            = nil
        @na_selected_material_names  = []

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Dialog Lifecycle
# -----------------------------------------------------------------------------

        # FUNCTION | Show the Material Swap Wizard Dialog
        # ------------------------------------------------------------
        # Creates a single HtmlDialog containing both Step 1 and Step 2
        # panels.  Panels are switched client-side via execute_script —
        # eliminating the close/reopen flash of the original two-dialog design.
        #
        # @param materials_data [Hash] { name => { material:, count: } }
        # @param model          [Sketchup::Model] Active model at launch time
        # ------------------------------------------------------------
        def self.Na__MaterialSwapInSelection__DialogManager__ShowDialog(materials_data, model)
            if @na_dialog && @na_dialog.visible?
                @na_dialog.bring_to_front
                na_push_step1_update(@na_dialog, materials_data)
                return @na_dialog
            end

            @na_current_model   = model
            @na_step            = :step1
            @na_selected_material_names = []

            @na_dialog = UI::HtmlDialog.new(
                dialog_title:    NA_DIALOG_TITLE,
                preferences_key: NA_DIALOG_PREFERENCES_KEY,
                scrollable:      false,
                resizable:       true,
                width:           NA_DIALOG_WIDTH,
                height:          NA_DIALOG_HEIGHT,
                style:           UI::HtmlDialog::STYLE_DIALOG
            )

            @na_dialog.set_html(na_generate_html(materials_data))
            na_setup_dialog_callbacks(@na_dialog)
            @na_dialog.set_on_closed { na_on_dialog_closed }
            @na_dialog.show

            na_attach_selection_observer(model)
            @na_dialog
        end
        # ------------------------------------------------------------

        # FUNCTION | Handle Dialog Close and Clean Up State
        # ------------------------------------------------------------
        def self.na_on_dialog_closed
            na_detach_selection_observer
            @na_dialog                  = nil
            @na_step                    = :step1
            @na_current_model           = nil
            @na_selected_material_names = []
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

            @na_selection_observer = Na__MaterialSwapInSelection__SelectionObserver.new
            model.selection.add_observer(@na_selection_observer)
        rescue => error
            puts "[Na__Noble3dModellingTools] MaterialSwapInSelection: observer attach failed: #{error.class}: #{error.message}"
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
            puts "[Na__Noble3dModellingTools] MaterialSwapInSelection: observer detach warning: #{error.class}: #{error.message}"
        end
        # ------------------------------------------------------------

        # FUNCTION | Handle Incoming Selection Change from Observer
        # ------------------------------------------------------------
        # Only acts on Step 1 — Step 2 is a committed state. Selection
        # changes while on Step 2 are silently deferred; pressing Back
        # will re-collect from the current (now updated) selection.
        # ------------------------------------------------------------
        def self.Na__MaterialSwapInSelection__DialogManager__HandleSelectionChanged
            return unless @na_dialog && @na_dialog.visible?
            return unless @na_step == :step1

            model = Sketchup.active_model
            return unless model

            selection = model.selection

            if selection.empty?
                na_push_empty_selection_state(@na_dialog)
                return
            end

            materials_data = Na__MaterialSwapInSelection__MaterialCollector.Na__MaterialSwapInSelection__MaterialCollector__CollectMaterialsRecursive(
                selection,
                {}
            )

            if materials_data.empty?
                na_push_no_materials_state(@na_dialog)
            else
                na_push_step1_update(@na_dialog, materials_data)
            end
        rescue => error
            puts "[Na__Noble3dModellingTools] MaterialSwapInSelection: HandleSelectionChanged error: #{error.class}: #{error.message}"
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Dialog Callbacks
# -----------------------------------------------------------------------------

        # FUNCTION | Register All Dialog Action Callbacks
        # ------------------------------------------------------------
        def self.na_setup_dialog_callbacks(dialog)
            dialog.add_action_callback('materials_selected') do |_context, names_json|
                na_handle_materials_selected(dialog, names_json)
            end

            dialog.add_action_callback('swap') do |_context, replacement_json|
                na_handle_swap(dialog, replacement_json)
            end

            dialog.add_action_callback('back') do |_context|
                na_handle_back(dialog)
            end

            dialog.add_action_callback('cancel') do |_context|
                dialog.close
            end
        end
        # ------------------------------------------------------------

        # FUNCTION | Handle Step 1 Confirmation — Transition to Step 2
        # ------------------------------------------------------------
        def self.na_handle_materials_selected(dialog, names_json)
            @na_selected_material_names = JSON.parse(names_json)
            return if @na_selected_material_names.empty?

            @na_step = :step2
            model = @na_current_model || Sketchup.active_model
            return unless model

            all_materials = model.materials.to_a.sort_by(&:name)
            na_push_step2_update(dialog, all_materials, @na_selected_material_names.size)
        rescue => error
            puts "[Na__Noble3dModellingTools] MaterialSwapInSelection: materials_selected error: #{error.class}: #{error.message}"
        end
        # ------------------------------------------------------------

        # FUNCTION | Handle Step 2 Confirmation — Execute the Swap
        # ------------------------------------------------------------
        def self.na_handle_swap(dialog, replacement_json)
            replacement_name = JSON.parse(replacement_json)
            model = @na_current_model || Sketchup.active_model
            return unless model

            old_materials_set = Set.new(
                model.materials.select { |m| @na_selected_material_names.include?(m.name) }
            )
            new_material = model.materials[replacement_name]

            unless new_material
                UI.messagebox("Replacement material not found: #{replacement_name}")
                dialog.close
                return
            end

            selection = model.selection
            operation_started = false

            model.start_operation(NA_OPERATION_NAME, true)
            operation_started = true

            count = Na__MaterialSwapInSelection__Swapper.Na__MaterialSwapInSelection__Swapper__SwapMaterialsRecursive(
                selection,
                old_materials_set,
                new_material
            )

            model.commit_operation
            operation_started = false

            dialog.close

            replaced_names = @na_selected_material_names.join(', ')
            UI.messagebox(
                "Swapped #{count} #{count == 1 ? 'application' : 'applications'}.\n\n" \
                "Replaced: #{replaced_names}\nWith: #{replacement_name}"
            )
        rescue => error
            model.abort_operation if model && operation_started
            dialog.close
            UI.messagebox("Material swap failed: #{error.class}: #{error.message}")
        end
        # ------------------------------------------------------------

        # FUNCTION | Handle Back — Return to Step 1 with Refreshed Selection Data
        # ------------------------------------------------------------
        def self.na_handle_back(dialog)
            @na_step = :step1
            @na_selected_material_names = []

            model = @na_current_model || Sketchup.active_model
            return unless model

            selection = model.selection

            if selection.empty?
                na_push_empty_selection_state(dialog)
                return
            end

            materials_data = Na__MaterialSwapInSelection__MaterialCollector.Na__MaterialSwapInSelection__MaterialCollector__CollectMaterialsRecursive(
                selection,
                {}
            )

            if materials_data.empty?
                na_push_no_materials_state(dialog)
            else
                na_push_step1_update(dialog, materials_data)
            end
        rescue => error
            puts "[Na__Noble3dModellingTools] MaterialSwapInSelection: back error: #{error.class}: #{error.message}"
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Live UI Push Helpers
# -----------------------------------------------------------------------------

        # FUNCTION | Push a Normal Step 1 Materials Checklist to the Dialog
        # ------------------------------------------------------------
        def self.na_push_step1_update(dialog, materials_data)
            materials_array = materials_data.map { |name, data| { name: name, count: data[:count] } }
            na_execute_js_function(dialog, 'Na__MaterialSwapInSelection__ShowStep1', {
                state:     'normal',
                materials: materials_array,
                message:   nil
            })
        end
        # ------------------------------------------------------------

        # FUNCTION | Push Empty-Selection State to the Step 1 Panel
        # ------------------------------------------------------------
        def self.na_push_empty_selection_state(dialog)
            na_execute_js_function(dialog, 'Na__MaterialSwapInSelection__ShowStep1', {
                state:     'empty_selection',
                materials: [],
                message:   'No entities are currently selected. Select entities in the model to see their materials.'
            })
        end
        # ------------------------------------------------------------

        # FUNCTION | Push No-Materials-Found State to the Step 1 Panel
        # ------------------------------------------------------------
        def self.na_push_no_materials_state(dialog)
            na_execute_js_function(dialog, 'Na__MaterialSwapInSelection__ShowStep1', {
                state:     'no_materials',
                materials: [],
                message:   'No materials found in the current selection. All entities are unpainted.'
            })
        end
        # ------------------------------------------------------------

        # FUNCTION | Push Step 2 Replacement Picker to the Dialog
        # ------------------------------------------------------------
        def self.na_push_step2_update(dialog, all_materials, selected_count)
            materials_array = all_materials.map { |mat| { name: mat.name } }
            na_execute_js_function(dialog, 'Na__MaterialSwapInSelection__ShowStep2', {
                materials:      materials_array,
                selected_count: selected_count
            })
        end
        # ------------------------------------------------------------

        # FUNCTION | Execute a Named JS Function with a JSON Payload in the Dialog
        # ------------------------------------------------------------
        def self.na_execute_js_function(dialog, function_name, payload_hash)
            return unless dialog && dialog.visible?

            script = <<~JS
                (function() {
                    if (typeof #{function_name} === 'function') {
                        #{function_name}(#{JSON.generate(payload_hash)});
                    }
                })();
            JS
            dialog.execute_script(script)
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | HTML Generation
# -----------------------------------------------------------------------------

        # FUNCTION | Generate the Full Dialog HTML (Both Panels Inline)
        # ------------------------------------------------------------
        def self.na_generate_html(initial_materials_data)
            materials_array = initial_materials_data.map { |name, data| { name: name, count: data[:count] } }

            <<~HTML
                <!DOCTYPE html>
                <html lang="en">
                <head>
                    <meta charset="UTF-8">
                    <meta name="viewport" content="width=device-width, initial-scale=1.0">
                    <style>
                        #{na_generate_css}
                    </style>
                </head>
                <body>

                    <!-- ======================================================
                         STEP 1 PANEL — Select materials to replace
                    ======================================================= -->
                    <div id="naMswap__Step1Panel" class="naMswap__Panel">
                        <div class="naMswap__Header">
                            <h2 class="naMswap__Title">Material Swap — Step 1 of 2</h2>
                            <p class="naMswap__Subtitle">Select the materials to replace from the current selection.</p>
                            <div class="naMswap__StatusBanner naMswap__StatusBanner--hidden" id="naMswap__Step1Banner"></div>
                        </div>

                        <div class="naMswap__ScrollArea" id="naMswap__Step1List"></div>

                        <div class="naMswap__Footer">
                            <button class="naMswap__Btn naMswap__Btn--secondary" id="naMswap__SelectAllBtn">Select All</button>
                            <div class="naMswap__FooterActions">
                                <button class="naMswap__Btn naMswap__Btn--muted" id="naMswap__Step1CancelBtn">Cancel</button>
                                <button class="naMswap__Btn naMswap__Btn--primary" id="naMswap__NextBtn" disabled>Next</button>
                            </div>
                        </div>
                    </div>

                    <!-- ======================================================
                         STEP 2 PANEL — Choose replacement material
                    ======================================================= -->
                    <div id="naMswap__Step2Panel" class="naMswap__Panel" style="display:none">
                        <div class="naMswap__Header">
                            <h2 class="naMswap__Title">Material Swap — Step 2 of 2</h2>
                            <p class="naMswap__Subtitle" id="naMswap__Step2Subtitle">Select replacement material.</p>
                            <div class="naMswap__SearchWrap">
                                <input class="naMswap__SearchInput" type="search" id="naMswap__SearchInput" placeholder="Search materials…">
                            </div>
                        </div>

                        <div class="naMswap__ScrollArea" id="naMswap__Step2List"></div>
                        <p class="naMswap__NoResults naMswap__NoResults--hidden" id="naMswap__NoResults">No materials match your search.</p>

                        <div class="naMswap__Footer">
                            <button class="naMswap__Btn naMswap__Btn--secondary" id="naMswap__BackBtn">Back</button>
                            <div class="naMswap__FooterActions">
                                <button class="naMswap__Btn naMswap__Btn--muted" id="naMswap__Step2CancelBtn">Cancel</button>
                                <button class="naMswap__Btn naMswap__Btn--primary" id="naMswap__SwapBtn" disabled>Swap Materials</button>
                            </div>
                        </div>
                    </div>

                    <script>
                        #{na_generate_js(JSON.generate(materials_array))}
                    </script>
                </body>
                </html>
            HTML
        end
        # ------------------------------------------------------------

        # FUNCTION | Dialog CSS
        # ------------------------------------------------------------
        def self.na_generate_css
            <<~CSS
                *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

                html, body { height: 100%; }

                body {
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Arial, sans-serif;
                    font-size: 13px;
                    background: #f4f4f6;
                    color: #222;
                    overflow: hidden;
                }

                .naMswap__Panel {
                    display: flex;
                    flex-direction: column;
                    height: 100vh;
                    overflow: hidden;
                }

                .naMswap__Header {
                    padding: 14px 18px 12px;
                    background: #fff;
                    border-bottom: 1px solid #e0e0e0;
                    flex-shrink: 0;
                }

                .naMswap__Title {
                    font-size: 15px;
                    font-weight: 600;
                    color: #111;
                    margin-bottom: 3px;
                }

                .naMswap__Subtitle {
                    font-size: 12px;
                    color: #666;
                }

                .naMswap__StatusBanner {
                    margin-top: 8px;
                    padding: 7px 10px;
                    border-radius: 4px;
                    font-size: 12px;
                    background: #e3f2fd;
                    color: #1565c0;
                    border: 1px solid #90caf9;
                }

                .naMswap__StatusBanner--hidden { display: none; }

                .naMswap__SearchWrap {
                    margin-top: 8px;
                }

                .naMswap__SearchInput {
                    width: 100%;
                    padding: 7px 10px;
                    border: 1px solid #d0d0d0;
                    border-radius: 4px;
                    font-size: 13px;
                    background: #fafafa;
                    color: #222;
                    outline: none;
                }

                .naMswap__SearchInput:focus {
                    border-color: #2d7dd2;
                    background: #fff;
                }

                .naMswap__ScrollArea {
                    flex: 1;
                    overflow-y: auto;
                    padding: 10px 12px;
                    display: flex;
                    flex-direction: column;
                    gap: 4px;
                }

                .naMswap__Item {
                    display: flex;
                    align-items: center;
                    gap: 10px;
                    padding: 9px 12px;
                    background: #fff;
                    border: 1px solid #e0e0e0;
                    border-radius: 5px;
                    cursor: pointer;
                    transition: border-color 0.15s, background 0.15s;
                }

                .naMswap__Item:hover {
                    border-color: #aaa;
                    background: #fafafa;
                }

                .naMswap__Item--selected {
                    border-color: #2d7dd2;
                    background: #eef4fc;
                }

                .naMswap__Item input[type="checkbox"],
                .naMswap__Item input[type="radio"] {
                    width: 15px;
                    height: 15px;
                    flex-shrink: 0;
                    cursor: pointer;
                    accent-color: #2d7dd2;
                }

                .naMswap__ItemName {
                    font-weight: 500;
                    flex: 1;
                    color: #222;
                }

                .naMswap__ItemCount {
                    font-size: 11px;
                    color: #888;
                    white-space: nowrap;
                }

                .naMswap__NoResults {
                    text-align: center;
                    padding: 12px;
                    color: #999;
                    font-size: 12px;
                    flex-shrink: 0;
                }

                .naMswap__NoResults--hidden { display: none; }

                .naMswap__Footer {
                    display: flex;
                    align-items: center;
                    justify-content: space-between;
                    padding: 12px 16px;
                    background: #fff;
                    border-top: 1px solid #e0e0e0;
                    gap: 8px;
                    flex-shrink: 0;
                }

                .naMswap__FooterActions {
                    display: flex;
                    gap: 8px;
                }

                .naMswap__Btn {
                    padding: 7px 16px;
                    border: none;
                    border-radius: 4px;
                    font-size: 13px;
                    font-weight: 500;
                    cursor: pointer;
                    transition: background 0.15s, opacity 0.15s;
                }

                .naMswap__Btn--primary {
                    background: #2d7dd2;
                    color: #fff;
                }

                .naMswap__Btn--primary:hover:not(:disabled) { background: #2268b8; }

                .naMswap__Btn--primary:disabled {
                    opacity: 0.45;
                    cursor: not-allowed;
                }

                .naMswap__Btn--muted {
                    background: #e8e8e8;
                    color: #444;
                }

                .naMswap__Btn--muted:hover { background: #d8d8d8; }

                .naMswap__Btn--secondary {
                    background: #f0f0f0;
                    color: #444;
                    border: 1px solid #ccc;
                }

                .naMswap__Btn--secondary:hover { background: #e4e4e4; }
            CSS
        end
        # ------------------------------------------------------------

        # FUNCTION | Dialog JavaScript
        # ------------------------------------------------------------
        def self.na_generate_js(initial_materials_json)
            <<~JS
                'use strict';

                var na_select_all_state = false;
                var na_step2_selected_count = 0;

                // -------------------------------------------------------
                // Utility
                // -------------------------------------------------------

                function na_escape_html(text) {
                    var div = document.createElement('div');
                    div.textContent = text;
                    return div.innerHTML;
                }

                // -------------------------------------------------------
                // Step 1 — Material selection checklist
                // -------------------------------------------------------

                function na_build_step1_list(materials) {
                    var list = document.getElementById('naMswap__Step1List');
                    list.innerHTML = '';
                    na_select_all_state = false;
                    document.getElementById('naMswap__SelectAllBtn').textContent = 'Select All';

                    materials.forEach(function(mat, index) {
                        var item = document.createElement('label');
                        item.className = 'naMswap__Item';
                        item.htmlFor = 'naMswapCb_' + index;

                        var cb = document.createElement('input');
                        cb.type = 'checkbox';
                        cb.id = 'naMswapCb_' + index;
                        cb.value = mat.name;
                        cb.addEventListener('change', function() {
                            item.classList.toggle('naMswap__Item--selected', cb.checked);
                            na_update_next_btn();
                        });

                        var nameSpan = document.createElement('span');
                        nameSpan.className = 'naMswap__ItemName';
                        nameSpan.innerHTML = na_escape_html(mat.name);

                        var countSpan = document.createElement('span');
                        countSpan.className = 'naMswap__ItemCount';
                        countSpan.textContent = mat.count + (mat.count === 1 ? ' use' : ' uses');

                        item.appendChild(cb);
                        item.appendChild(nameSpan);
                        item.appendChild(countSpan);
                        list.appendChild(item);
                    });

                    na_update_next_btn();
                }

                function na_update_next_btn() {
                    var any = Array.from(
                        document.querySelectorAll('#naMswap__Step1List input[type="checkbox"]')
                    ).some(function(cb) { return cb.checked; });
                    document.getElementById('naMswap__NextBtn').disabled = !any;
                }

                function na_show_step1_banner(message, hide) {
                    var banner = document.getElementById('naMswap__Step1Banner');
                    if (hide) {
                        banner.className = 'naMswap__StatusBanner naMswap__StatusBanner--hidden';
                        banner.textContent = '';
                    } else {
                        banner.className = 'naMswap__StatusBanner';
                        banner.textContent = message || '';
                    }
                }

                // Called by Ruby — switches to / refreshes Step 1 view
                function Na__MaterialSwapInSelection__ShowStep1(payload) {
                    document.getElementById('naMswap__Step1Panel').style.display = 'flex';
                    document.getElementById('naMswap__Step2Panel').style.display = 'none';

                    if (payload.state !== 'normal') {
                        na_show_step1_banner(payload.message, false);
                        na_build_step1_list([]);
                        document.getElementById('naMswap__SelectAllBtn').disabled = true;
                        document.getElementById('naMswap__NextBtn').disabled = true;
                        return;
                    }

                    na_show_step1_banner(null, true);
                    na_build_step1_list(payload.materials || []);
                    document.getElementById('naMswap__SelectAllBtn').disabled = false;
                }

                // -------------------------------------------------------
                // Step 2 — Replacement material radio list
                // -------------------------------------------------------

                function na_build_step2_list(materials) {
                    var list = document.getElementById('naMswap__Step2List');
                    list.innerHTML = '';

                    materials.forEach(function(mat, index) {
                        var item = document.createElement('label');
                        item.className = 'naMswap__Item';
                        item.htmlFor = 'naMswapRb_' + index;
                        item.setAttribute('data-name-lc', mat.name.toLowerCase());

                        var rb = document.createElement('input');
                        rb.type = 'radio';
                        rb.name = 'naMswap__replacement';
                        rb.id = 'naMswapRb_' + index;
                        rb.value = mat.name;
                        rb.addEventListener('change', function() {
                            document.querySelectorAll('#naMswap__Step2List .naMswap__Item').forEach(function(el) {
                                el.classList.remove('naMswap__Item--selected');
                            });
                            item.classList.add('naMswap__Item--selected');
                            na_update_swap_btn();
                        });

                        var nameSpan = document.createElement('span');
                        nameSpan.className = 'naMswap__ItemName';
                        nameSpan.innerHTML = na_escape_html(mat.name);

                        item.appendChild(rb);
                        item.appendChild(nameSpan);
                        list.appendChild(item);
                    });

                    na_update_swap_btn();
                }

                function na_update_swap_btn() {
                    var any = !!document.querySelector('#naMswap__Step2List input[type="radio"]:checked');
                    document.getElementById('naMswap__SwapBtn').disabled = !any;
                }

                function na_filter_step2_list(query) {
                    var lc = query.toLowerCase();
                    var items = document.querySelectorAll('#naMswap__Step2List .naMswap__Item');
                    var visible = 0;

                    items.forEach(function(item) {
                        var name = item.getAttribute('data-name-lc') || '';
                        var show = lc === '' || name.includes(lc);
                        item.style.display = show ? '' : 'none';
                        if (show) visible++;
                    });

                    var noResults = document.getElementById('naMswap__NoResults');
                    noResults.className = (visible === 0 && lc !== '')
                        ? 'naMswap__NoResults'
                        : 'naMswap__NoResults naMswap__NoResults--hidden';
                }

                // Called by Ruby — switches to Step 2 view
                function Na__MaterialSwapInSelection__ShowStep2(payload) {
                    document.getElementById('naMswap__Step1Panel').style.display = 'none';
                    document.getElementById('naMswap__Step2Panel').style.display = 'flex';

                    na_step2_selected_count = payload.selected_count || 0;
                    document.getElementById('naMswap__Step2Subtitle').textContent =
                        'Replacing ' + na_step2_selected_count +
                        (na_step2_selected_count === 1 ? ' material' : ' materials') +
                        '. Select the replacement material.';

                    na_build_step2_list(payload.materials || []);
                    document.getElementById('naMswap__SearchInput').value = '';
                    document.getElementById('naMswap__NoResults').className =
                        'naMswap__NoResults naMswap__NoResults--hidden';
                    document.getElementById('naMswap__SwapBtn').disabled = true;
                }

                // -------------------------------------------------------
                // Event listeners — Step 1
                // -------------------------------------------------------

                document.getElementById('naMswap__SelectAllBtn').addEventListener('click', function() {
                    na_select_all_state = !na_select_all_state;
                    document.querySelectorAll('#naMswap__Step1List input[type="checkbox"]').forEach(function(cb) {
                        cb.checked = na_select_all_state;
                        cb.closest('.naMswap__Item').classList.toggle('naMswap__Item--selected', na_select_all_state);
                    });
                    this.textContent = na_select_all_state ? 'Deselect All' : 'Select All';
                    na_update_next_btn();
                });

                document.getElementById('naMswap__NextBtn').addEventListener('click', function() {
                    var selected = Array.from(
                        document.querySelectorAll('#naMswap__Step1List input[type="checkbox"]:checked')
                    ).map(function(cb) { return cb.value; });

                    if (selected.length > 0) {
                        window.sketchup.materials_selected(JSON.stringify(selected));
                    }
                });

                document.getElementById('naMswap__Step1CancelBtn').addEventListener('click', function() {
                    window.sketchup.cancel();
                });

                // -------------------------------------------------------
                // Event listeners — Step 2
                // -------------------------------------------------------

                document.getElementById('naMswap__SearchInput').addEventListener('input', function() {
                    na_filter_step2_list(this.value);
                });

                document.getElementById('naMswap__SwapBtn').addEventListener('click', function() {
                    var selected = document.querySelector('#naMswap__Step2List input[type="radio"]:checked');
                    if (selected) {
                        window.sketchup.swap(JSON.stringify(selected.value));
                    }
                });

                document.getElementById('naMswap__BackBtn').addEventListener('click', function() {
                    window.sketchup.back();
                });

                document.getElementById('naMswap__Step2CancelBtn').addEventListener('click', function() {
                    window.sketchup.cancel();
                });

                // -------------------------------------------------------
                // Initial render (Step 1 on first open)
                // -------------------------------------------------------

                Na__MaterialSwapInSelection__ShowStep1({
                    state: 'normal',
                    materials: #{initial_materials_json},
                    message: null
                });
            JS
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__MaterialSwapInSelection__DialogManager
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
