# =============================================================================
# ValeDesignSuite - Notes App Module
# =============================================================================
#
# NAMESPACE : ValeDesignSuite::Utils
# MODULE    : NotesApp
# AUTHOR    : Adam Noble - Vale Garden Houses
# TYPE      : SketchUp 2026 Plugin Utility
# PURPOSE   : In-built notes app for storing notes within SketchUp models
# CREATED   : 2025
#
# DESCRIPTION:
# - This module provides a notes app that stores notes directly within the SketchUp model
# - Notes are automatically saved with the model and persist across sessions
# - Features auto-save functionality (every 5 minutes) and manual save
# - Adapted from Noble Architecture Toolbox NotebookPlugin
#
# USAGE NOTES: 
# - Notes are stored in the model's attribute dictionary "vds_notes_dictionary"
# - Access via: ValeDesignSuite::Utils::NotesApp.show_notes_app
#
# -----------------------------------------------------------------------------
#
# DEVELOPMENT LOG:
# 2025 - Version 1.0.0 - INITIAL CREATION
# - Created Notes App module adapted from NotebookPlugin
# - Styled with Vale Design Suite CSS conventions
# - Integrated into main VDS UI
#
# =============================================================================

module ValeDesignSuite
    module Utils
        module NotesApp
            extend self

            class NotesModelObserver < Sketchup::ModelObserver
                def onSaveModel(_model)
                    NotesApp.save_current_notes
                end
            end

            def create_dialog
                @dialog = UI::HtmlDialog.new(
                    dialog_title:    "Vale Design Suite | Notes",
                    preferences_key: "com.vale-design-suite.notes",
                    scrollable:      true,
                    resizable:       true,
                    width:           900,
                    height:          1200,
                    style:           UI::HtmlDialog::STYLE_DIALOG
                )

                html_content = <<-HTML
                    <!DOCTYPE html>
                    <html lang="en">
                    <head>
                        <meta charset="UTF-8">
                        <title>Vale Design Suite | Notes</title>
                        <style>
                        :root {
                            --FontCol_ValeTitleTextColour      : #172b3a;
                            --FontCol_ValeTitleHeadingColour   : #172b3a;
                            --FontCol_ValeStandardTextColour   : #1e1e1e;
                            --FontType_ValeStandardText        : 'Open Sans Regular', sans-serif;
                            --FontType_ValeTitleHeading02      : 'Open Sans Semibold', sans-serif;
                            --ValeBackgroundColor              : #f0f0f0;
                            --ValeContentBackground            : #ffffff;
                            --ValeBorderColor                  : #dddddd;
                            --ValePrimaryButtonBg              : #006600;
                            --ValePrimaryButtonHoverBg         : #008800;
                            --ValePrimaryButtonText            : #ffffff;
                            --ValeSecondaryButtonBg            : #172b3a;
                            --ValeSecondaryButtonHoverBg       : #2a4a63;
                            --ValeSecondaryButtonText          : #ffffff;
                        }
                        
                        html, body {
                            margin: 0;
                            padding: 0;
                            font-family: var(--FontType_ValeStandardText);
                            font-size: 16px;
                            color: var(--FontCol_ValeStandardTextColour);
                            background-color: var(--ValeBackgroundColor);
                        }
                        
                        body {
                            padding: 20px;
                        }
                        
                        h2 {
                            font-family: var(--FontType_ValeTitleHeading02);
                            font-size: 1.25rem;
                            color: var(--FontCol_ValeTitleHeadingColour);
                            margin-bottom: 15px;
                            margin-top: 0;
                        }
                        
                        p {
                            font-family: var(--FontType_ValeStandardText);
                            font-size: 1rem;
                            color: var(--FontCol_ValeStandardTextColour);
                            margin-bottom: 15px;
                            line-height: 1.5;
                        }
                        
                        #VDS_Notes_notepad {
                            width: calc(100% - 32px);
                            padding: 15px;
                            margin-top: 10px;
                            font-family: var(--FontType_ValeStandardText);
                            font-size: 1rem;
                            border: 1px solid var(--ValeBorderColor);
                            border-radius: 4px;
                            background: var(--ValeContentBackground);
                            color: var(--FontCol_ValeStandardTextColour);
                            min-height: 450px;
                            resize: vertical;
                            box-sizing: border-box;
                        }
                        
                        #VDS_Notes_status {
                            font-size: 10pt;
                            color: #666666;
                            margin-top: 10px;
                            text-align: right;
                            font-style: italic;
                        }
                        
                        .VDS_Notes_autosave_status {
                            font-size: 9pt;
                            color: var(--ValePrimaryButtonBg);
                            margin-top: 5px;
                        }
                        
                        .VDS_Notes_button_container {
                            display: flex;
                            justify-content: space-between;
                            margin-top: 15px;
                        }
                        
                        button {
                            background-color: var(--ValePrimaryButtonBg);
                            color: var(--ValePrimaryButtonText);
                            border: none;
                            padding: 10px 20px;
                            border-radius: 4px;
                            cursor: pointer;
                            font-family: var(--FontType_ValeStandardText);
                            font-size: 0.9rem;
                            transition: background-color 0.3s ease;
                        }
                        
                        button:hover {
                            background-color: var(--ValePrimaryButtonHoverBg);
                        }
                        
                        button.secondary {
                            background-color: var(--ValeSecondaryButtonBg);
                            color: var(--ValeSecondaryButtonText);
                        }
                        
                        button.secondary:hover {
                            background-color: var(--ValeSecondaryButtonHoverBg);
                        }
                        </style>
                    </head>
                    <body>
                        <h2>Model Notes</h2>
                        <p>Notes are automatically saved with this model:</p>
                        <textarea id="VDS_Notes_notepad" placeholder="Enter your notes here..."></textarea>
                        <div id="VDS_Notes_status">Last saved: -</div>
                        <div class="VDS_Notes_autosave_status">Autosave enabled (every 5 minutes)</div>
                        <div class="VDS_Notes_button_container">
                            <button class="secondary" onclick="clearNotes()">Clear Notes</button>
                            <button onclick="saveNotes()">Save Notes</button>
                        </div>

                        <script>
                        let saveTimer = null;
                        let autoSaveTimer = null;
                        let lastSavedContent = '';
                        let hasUnsavedChanges = false;

                        window.onload = function() {
                            sketchup.getNotes();
                            document.getElementById('VDS_Notes_notepad')
                                .addEventListener('input', function() {
                                    hasUnsavedChanges = true;
                                    if (saveTimer) clearTimeout(saveTimer);
                                    saveTimer = setTimeout(function() {
                                        saveNotes();
                                    }, 1000);
                                });
                            setAutoSaveTimer();
                            window.addEventListener('beforeunload', function(e) {
                                if (hasUnsavedChanges) {
                                    sketchup.checkForUnsavedChanges();
                                    e.preventDefault();
                                    e.returnValue = '';
                                }
                            });
                        };

                        function setAutoSaveTimer() {
                            if (autoSaveTimer) clearTimeout(autoSaveTimer);
                            autoSaveTimer = setTimeout(function() {
                                if (hasUnsavedChanges) {
                                    saveNotes();
                                }
                                setAutoSaveTimer();
                            }, 5 * 60 * 1000);
                        }

                        function saveNotes() {
                            const notes = document.getElementById('VDS_Notes_notepad').value;
                            sketchup.saveNotes(notes);
                            lastSavedContent = notes;
                            hasUnsavedChanges = false;
                            updateSaveStatus();
                        }
                        
                        function clearNotes() {
                            if (confirm('Are you sure you want to clear all notes?')) {
                                document.getElementById('VDS_Notes_notepad').value = '';
                                saveNotes();
                            }
                        }
                        
                        function setNotes(content) {
                            document.getElementById('VDS_Notes_notepad').value = content;
                            lastSavedContent = content;
                            hasUnsavedChanges = false;
                            updateSaveStatus();
                        }
                        
                        function updateSaveStatus() {
                            const now = new Date();
                            const timeStr = now.toLocaleTimeString();
                            document.getElementById('VDS_Notes_status').textContent = 'Last saved: ' + timeStr;
                        }
                        
                        function checkForUnsavedChanges() {
                            const result = confirm("You have unsaved changes. Click OK to save before closing, or Cancel to continue without saving.");
                            if(result) {
                                saveNotes();
                            }
                        }
                        </script>
                    </body>
                    </html>
                HTML

                @dialog.set_html(html_content)

                @dialog.add_action_callback('saveNotes') do |_dlg, notes|
                    save_notes_to_model(notes)
                end
                @dialog.add_action_callback('getNotes') do |_dlg|
                    notes = get_notes_from_model
                    @dialog.execute_script("setNotes('#{escape_js(notes)}');")
                end
                @dialog.add_action_callback('checkForUnsavedChanges') do |_dlg|
                    # Handled in JS
                end

                add_model_observers
                @dialog
            end

            def add_model_observers
                return if @observer_added
                @model_observer = NotesModelObserver.new
                Sketchup.active_model.add_observer(@model_observer)
                @observer_added = true
            end

            def save_current_notes
                return unless @dialog && @dialog.visible?
                @dialog.execute_script("saveNotes();")
            end

            def escape_js(string)
                return '' if string.nil?
                string.to_s.gsub(/\\/, '\\\\\\').gsub(/\n/, '\\n').gsub(/\r/, '\\r').gsub(/['"]/) { |m| "\\#{m}" }
            end

            def save_notes_to_model(notes)
                model = Sketchup.active_model
                return if model.nil?
                model.start_operation("Save Notes", true)
                dict = model.attribute_dictionary("vds_notes_dictionary")
                if dict.nil?
                    model.set_attribute("vds_notes_dictionary", "notes", notes)
                else
                    model.set_attribute("vds_notes_dictionary", "notes", notes)
                end
                model.commit_operation
            end

            def get_notes_from_model
                model = Sketchup.active_model
                return '' if model.nil?
                dict = model.attribute_dictionary("vds_notes_dictionary")
                return '' if dict.nil?
                dict["notes"] || ''
            end

            def show_notes_app
                if @dialog && @dialog.visible?
                    @dialog.bring_to_front
                else
                    @dialog = create_dialog
                    @dialog.show
                end
            end
        end
    end
end

# =============================================================================
# END OF FILE
# =============================================================================

