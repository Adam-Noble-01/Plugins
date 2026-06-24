# =============================================================================
# NA NOBLE3D MODELLING TOOLS - UNTAG SPECIFIC IN SELECTION - DIALOG MANAGER
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__UntagSpecificInSelection__DialogManager__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__UntagSpecificInSelection__DialogManager
# PURPOSE    : Manage the HtmlDialog lifecycle, selection observer, and live UI sync
# CREATED    : 2026
#
# =============================================================================

require 'json'

module Na__Noble3dModellingTools
    module Na__UntagSpecificInSelection__DialogManager

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_DIALOG_TITLE           = 'Untag Specific In Selection'.freeze
        NA_DIALOG_PREFERENCES_KEY = 'Na__Noble3dModellingTools__UntagSpecificInSelection'.freeze
        NA_DIALOG_WIDTH           = 460
        NA_DIALOG_HEIGHT          = 540
        NA_OPERATION_NAME         = 'Untag Specific In Selection'.freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Module State
# -----------------------------------------------------------------------------

        @na_dialog            = nil
        @na_selection_observer = nil

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Dialog Lifecycle
# -----------------------------------------------------------------------------

        # FUNCTION | Show the Tag Selection Dialog
        # ------------------------------------------------------------
        # Creates a new dialog or brings an existing visible one to
        # the front.  Attaches the selection observer on first open.
        #
        # @param tags_data [Hash] { tag_name => { layer:, count: } }
        # @param model     [Sketchup::Model] Active model at launch time
        # ------------------------------------------------------------
        def self.Na__UntagSpecificInSelection__DialogManager__ShowDialog(tags_data, model)
            if @na_dialog && @na_dialog.visible?
                @na_dialog.bring_to_front
                na_push_tags_update(@na_dialog, tags_data)
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

            @na_dialog.set_html(na_generate_html(tags_data))
            na_setup_dialog_callbacks(@na_dialog)
            @na_dialog.set_on_closed { na_on_dialog_closed }
            @na_dialog.show

            na_attach_selection_observer(model)
            @na_dialog
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

            @na_selection_observer = Na__UntagSpecificInSelection__SelectionObserver.new
            model.selection.add_observer(@na_selection_observer)
        rescue => error
            puts "[Na__Noble3dModellingTools] UntagSpecificInSelection: observer attach failed: #{error.class}: #{error.message}"
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
            puts "[Na__Noble3dModellingTools] UntagSpecificInSelection: observer detach warning: #{error.class}: #{error.message}"
        end
        # ------------------------------------------------------------

        # FUNCTION | Handle Incoming Selection Change from Observer
        # ------------------------------------------------------------
        # Triggered by Na__UntagSpecificInSelection__SelectionObserver.
        # Re-collects tags from the new selection and pushes a live
        # update to the open dialog.  No-ops if the dialog is closed.
        # ------------------------------------------------------------
        def self.Na__UntagSpecificInSelection__DialogManager__HandleSelectionChanged
            return unless @na_dialog && @na_dialog.visible?

            model = Sketchup.active_model
            return unless model

            selection = model.selection

            if selection.empty?
                na_push_empty_selection_state(@na_dialog)
                return
            end

            tags_data = Na__UntagSpecificInSelection__TagCollector.Na__UntagSpecificInSelection__TagCollector__CollectTagsRecursive(
                selection,
                model
            )

            if tags_data.empty?
                na_push_no_tags_state(@na_dialog)
            else
                na_push_tags_update(@na_dialog, tags_data)
            end
        rescue => error
            puts "[Na__Noble3dModellingTools] UntagSpecificInSelection: HandleSelectionChanged error: #{error.class}: #{error.message}"
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Live UI Push Helpers
# -----------------------------------------------------------------------------

        # FUNCTION | Push a Normal Tag List Update to the Dialog
        # ------------------------------------------------------------
        def self.na_push_tags_update(dialog, tags_data)
            tags_array = tags_data.map { |name, data| { name: name, count: data[:count] } }
            na_execute_receive_function(dialog, { state: 'normal', tags: tags_array })
        end
        # ------------------------------------------------------------

        # FUNCTION | Push Empty-Selection State to the Dialog
        # ------------------------------------------------------------
        def self.na_push_empty_selection_state(dialog)
            na_execute_receive_function(dialog, {
                state:   'empty_selection',
                tags:    [],
                message: 'No entities are currently selected. Select entities in the model to see their tags.'
            })
        end
        # ------------------------------------------------------------

        # FUNCTION | Push No-Tags-Found State to the Dialog
        # ------------------------------------------------------------
        def self.na_push_no_tags_state(dialog)
            na_execute_receive_function(dialog, {
                state:   'no_tags',
                tags:    [],
                message: 'No tags found in the current selection. All entities are already untagged.'
            })
        end
        # ------------------------------------------------------------

        # FUNCTION | Execute the JS ReceiveTagsData Function in the Dialog
        # ------------------------------------------------------------
        def self.na_execute_receive_function(dialog, payload_hash)
            return unless dialog && dialog.visible?

            script = <<~JS
                (function() {
                    if (typeof Na__UntagSpecificInSelection__ReceiveTagsData === 'function') {
                        Na__UntagSpecificInSelection__ReceiveTagsData(#{JSON.generate(payload_hash)});
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
            dialog.add_action_callback('untag') do |_context, tags_json|
                na_execute_untag_operation(dialog, tags_json)
            end

            dialog.add_action_callback('cancel') do |_context|
                dialog.close
            end
        end
        # ------------------------------------------------------------

        # FUNCTION | Execute the Untag Operation from Dialog Callback
        # ------------------------------------------------------------
        def self.na_execute_untag_operation(dialog, tags_json)
            model = Sketchup.active_model
            return unless model

            tag_names_to_remove = JSON.parse(tags_json)
            return if tag_names_to_remove.empty?

            selection = model.selection
            operation_started = false

            model.start_operation(NA_OPERATION_NAME, true)
            operation_started = true

            count = Na__UntagSpecificInSelection__Untagger.Na__UntagSpecificInSelection__Untagger__UntagEntitiesRecursive(
                selection,
                tag_names_to_remove,
                model
            )

            model.commit_operation
            operation_started = false

            dialog.close
            UI.messagebox(
                "Untagged #{count} #{count == 1 ? 'entity' : 'entities'} across " \
                "#{tag_names_to_remove.size} #{tag_names_to_remove.size == 1 ? 'tag' : 'tags'}."
            )
        rescue => error
            model.abort_operation if model && operation_started
            dialog.close
            UI.messagebox("Untag operation failed: #{error.class}: #{error.message}")
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | HTML Generation
# -----------------------------------------------------------------------------

        # FUNCTION | Generate the Initial Dialog HTML
        # ------------------------------------------------------------
        def self.na_generate_html(tags_data)
            tags_array = tags_data.map { |name, data| { name: name, count: data[:count] } }

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
                    <div class="naUntag__Header">
                        <h2 class="naUntag__Title">Untag Specific In Selection</h2>
                        <p class="naUntag__Subtitle">Select the tags to remove from the current selection.</p>
                        <div class="naUntag__StatusBanner naUntag__StatusBanner--hidden" id="naUntagStatusBanner"></div>
                    </div>

                    <div class="naUntag__TagList" id="naUntagTagList"></div>

                    <div class="naUntag__Footer">
                        <button class="naUntag__Btn naUntag__Btn--secondary" id="naUntagSelectAllBtn">Select All</button>
                        <div class="naUntag__FooterActions">
                            <button class="naUntag__Btn naUntag__Btn--muted" id="naUntagCancelBtn">Cancel</button>
                            <button class="naUntag__Btn naUntag__Btn--primary" id="naUntagConfirmBtn" disabled>Untag Selected</button>
                        </div>
                    </div>

                    <script>
                        #{na_dialog_js(JSON.generate(tags_array))}
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

                .naUntag__Header {
                    padding: 14px 18px 12px;
                    background: #fff;
                    border-bottom: 1px solid #e0e0e0;
                    flex-shrink: 0;
                }

                .naUntag__Title {
                    font-size: 15px;
                    font-weight: 600;
                    color: #111;
                    margin-bottom: 3px;
                }

                .naUntag__Subtitle {
                    font-size: 12px;
                    color: #666;
                }

                .naUntag__StatusBanner {
                    margin-top: 8px;
                    padding: 7px 10px;
                    border-radius: 4px;
                    font-size: 12px;
                    background: #fff8e1;
                    color: #795548;
                    border: 1px solid #ffe082;
                }

                .naUntag__StatusBanner--hidden { display: none; }

                .naUntag__StatusBanner--info {
                    background: #e3f2fd;
                    color: #1565c0;
                    border-color: #90caf9;
                }

                .naUntag__TagList {
                    flex: 1;
                    overflow-y: auto;
                    padding: 10px 12px;
                    display: flex;
                    flex-direction: column;
                    gap: 4px;
                }

                .naUntag__TagItem {
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

                .naUntag__TagItem:hover {
                    border-color: #aaa;
                    background: #fafafa;
                }

                .naUntag__TagItem--selected {
                    border-color: #2d7dd2;
                    background: #eef4fc;
                }

                .naUntag__TagItem input[type="checkbox"] {
                    width: 15px;
                    height: 15px;
                    flex-shrink: 0;
                    cursor: pointer;
                    accent-color: #2d7dd2;
                }

                .naUntag__TagName {
                    font-weight: 500;
                    flex: 1;
                    color: #222;
                }

                .naUntag__TagCount {
                    font-size: 11px;
                    color: #888;
                    white-space: nowrap;
                }

                .naUntag__Footer {
                    display: flex;
                    align-items: center;
                    justify-content: space-between;
                    padding: 12px 16px;
                    background: #fff;
                    border-top: 1px solid #e0e0e0;
                    gap: 8px;
                    flex-shrink: 0;
                }

                .naUntag__FooterActions {
                    display: flex;
                    gap: 8px;
                }

                .naUntag__Btn {
                    padding: 7px 16px;
                    border: none;
                    border-radius: 4px;
                    font-size: 13px;
                    font-weight: 500;
                    cursor: pointer;
                    transition: background 0.15s, opacity 0.15s;
                }

                .naUntag__Btn--primary {
                    background: #2d7dd2;
                    color: #fff;
                }

                .naUntag__Btn--primary:hover:not(:disabled) { background: #2268b8; }

                .naUntag__Btn--primary:disabled {
                    opacity: 0.45;
                    cursor: not-allowed;
                }

                .naUntag__Btn--muted {
                    background: #e8e8e8;
                    color: #444;
                }

                .naUntag__Btn--muted:hover { background: #d8d8d8; }

                .naUntag__Btn--secondary {
                    background: #f0f0f0;
                    color: #444;
                    border: 1px solid #ccc;
                }

                .naUntag__Btn--secondary:hover { background: #e4e4e4; }
            CSS
        end
        # ------------------------------------------------------------

        # FUNCTION | Dialog JavaScript
        # ------------------------------------------------------------
        def self.na_dialog_js(initial_tags_json)
            <<~JS
                'use strict';

                var na_select_all_state = false;

                function na_escape_html(text) {
                    var div = document.createElement('div');
                    div.textContent = text;
                    return div.innerHTML;
                }

                function na_build_tag_list(tags) {
                    var list = document.getElementById('naUntagTagList');
                    list.innerHTML = '';
                    na_select_all_state = false;
                    document.getElementById('naUntagSelectAllBtn').textContent = 'Select All';

                    tags.forEach(function(tag, index) {
                        var item = document.createElement('label');
                        item.className = 'naUntag__TagItem';
                        item.htmlFor = 'naUntagCb_' + index;

                        var cb = document.createElement('input');
                        cb.type = 'checkbox';
                        cb.id = 'naUntagCb_' + index;
                        cb.value = tag.name;

                        var nameSpan = document.createElement('span');
                        nameSpan.className = 'naUntag__TagName';
                        nameSpan.innerHTML = na_escape_html(tag.name);

                        var countSpan = document.createElement('span');
                        countSpan.className = 'naUntag__TagCount';
                        countSpan.textContent = tag.count + (tag.count === 1 ? ' entity' : ' entities');

                        cb.addEventListener('change', function() {
                            item.classList.toggle('naUntag__TagItem--selected', cb.checked);
                            na_update_confirm_state();
                        });

                        item.appendChild(cb);
                        item.appendChild(nameSpan);
                        item.appendChild(countSpan);
                        list.appendChild(item);
                    });

                    na_update_confirm_state();
                }

                function na_update_confirm_state() {
                    var any_checked = Array.from(
                        document.querySelectorAll('#naUntagTagList input[type="checkbox"]')
                    ).some(function(cb) { return cb.checked; });
                    document.getElementById('naUntagConfirmBtn').disabled = !any_checked;
                }

                function na_set_status_banner(message, variant) {
                    var banner = document.getElementById('naUntagStatusBanner');
                    if (!message) {
                        banner.className = 'naUntag__StatusBanner naUntag__StatusBanner--hidden';
                        banner.textContent = '';
                        return;
                    }
                    banner.className = 'naUntag__StatusBanner naUntag__StatusBanner--' + (variant || 'warn');
                    banner.textContent = message;
                }

                // Called by Ruby via execute_script when the selection changes
                function Na__UntagSpecificInSelection__ReceiveTagsData(payload) {
                    if (payload.state === 'normal') {
                        na_set_status_banner(null);
                        na_build_tag_list(payload.tags || []);
                        document.getElementById('naUntagSelectAllBtn').disabled = false;
                    } else {
                        na_build_tag_list([]);
                        na_set_status_banner(payload.message || 'No tags available.', 'info');
                        document.getElementById('naUntagSelectAllBtn').disabled = true;
                        document.getElementById('naUntagConfirmBtn').disabled = true;
                    }
                }

                document.getElementById('naUntagSelectAllBtn').addEventListener('click', function() {
                    na_select_all_state = !na_select_all_state;
                    document.querySelectorAll('#naUntagTagList input[type="checkbox"]').forEach(function(cb) {
                        cb.checked = na_select_all_state;
                        cb.closest('.naUntag__TagItem').classList.toggle('naUntag__TagItem--selected', na_select_all_state);
                    });
                    this.textContent = na_select_all_state ? 'Deselect All' : 'Select All';
                    na_update_confirm_state();
                });

                document.getElementById('naUntagConfirmBtn').addEventListener('click', function() {
                    var selected = Array.from(
                        document.querySelectorAll('#naUntagTagList input[type="checkbox"]:checked')
                    ).map(function(cb) { return cb.value; });
                    if (selected.length > 0) {
                        window.sketchup.untag(JSON.stringify(selected));
                    }
                });

                document.getElementById('naUntagCancelBtn').addEventListener('click', function() {
                    window.sketchup.cancel();
                });

                na_build_tag_list(#{initial_tags_json});
            JS
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__UntagSpecificInSelection__DialogManager
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
