# -----------------------------------------------------------------------------
# SketchUp Plugin | Model-Persistent Notepad Tool
# -----------------------------------------------------------------------------
# Standalone notepad that saves notes directly to the SketchUp model dictionary
# Notes persist with the model file and support autosave functionality
# Extracted from Noble Architecture Toolbox Plugin UI v1.9.7
#
# Version 1.0.0 - 30-Dec-2025
#  - Refactored as standalone plugin with Noble Architecture styling
#  - Added hotkey support for quick access
#  - Updated UI to match Noble Architecture design system
# -----------------------------------------------------------------------------

require 'sketchup.rb'

module NotepadPlugin
    extend self

    # -----------------------------------------------------------------------------
    # REGION | Model Observer
    # -----------------------------------------------------------------------------

    # CLASS | Model Observer for Auto-Save on Model Save
    # ------------------------------------------------------------
    class NotepadModelObserver < Sketchup::ModelObserver
        # ON SAVE MODEL | Trigger note save when model is saved
        # ------------------------------------------------------------
        def onSaveModel(_model)
            NotepadPlugin.save_current_notes                                 # <-- Save notes when model saves
        end
        # ---------------------------------------------------------------
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------



    # -----------------------------------------------------------------------------
    # REGION | Stylesheet
    # -----------------------------------------------------------------------------

    # FUNCTION | Generate Stylesheet
    # ------------------------------------------------------------
    def stylesheet
        <<-CSS
        /* ========================== STYLE VARIABLES ========================== */
        :root {
            --na-text-color: #333333;
            --na-text-secondary: #444444;
            --na-text-muted: #666666;
            --na-background: #f8f8f8;
            --na-primary: #787369;
            --na-primary-hover: #555041;
            --na-border-color: #d0d0d0;
            --na-border-radius: 4px;
        }

        /* ========================== GLOBAL NORMALISATION ========================== */
        body, html {
            margin: 0;
            padding: 0;
            font-family: 'Open Sans', sans-serif;
        }

        /* ========================== BODY STYLES ========================== */
        body {
            margin: 20px;
            color: var(--na-text-color);
            background: var(--na-background);
            line-height: 1.4;
        }

        /* ========================== HEADER STYLES ========================== */
        .NA_header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding-bottom: 15px;
            border-bottom: 1px solid #e0e0e0;
            margin-bottom: 15px;
        }

        .NA_header h2 {
            font-weight: 600;
            font-size: 18pt;
            color: var(--na-text-color);
            margin: 0;
        }

        .NA_logo {
            height: 40px;
            width: auto;
        }

        /* ========================== INFO BOX STYLES ========================== */
        .NA_Notepad_info {
            background: #f0f0f0;
            padding: 15px;
            border-radius: var(--na-border-radius);
            margin-bottom: 25px;
            border-left: 3px solid var(--na-primary);
        }

        .NA_Notepad_info p {
            font-size: 10.5pt;
            color: var(--na-text-secondary);
            line-height: 1.5;
            margin: 0;
        }

        /* ========================== TEXTAREA STYLES ========================== */
        #Notepad_textarea {
            width: 100%;
            padding: 15px;
            box-sizing: border-box;
            font-family: 'Open Sans', sans-serif;
            font-size: 10.5pt;
            border: 1px solid var(--na-border-color);
            border-radius: var(--na-border-radius);
            background: #ffffff;
            color: var(--na-text-secondary);
            min-height: 450px;
            resize: vertical;
        }

        /* ========================== STATUS STYLES ========================== */
        #Notepad_status {
            font-size: 10pt;
            color: var(--na-text-muted);
            margin-top: 10px;
            text-align: right;
            font-style: italic;
        }

        .Notepad_autosave_status {
            font-size: 9pt;
            color: var(--na-primary);
            margin-top: 5px;
        }

        /* ========================== BUTTON STYLES ========================== */
        .NA_Notepad_button {
            background: var(--na-primary);
            color: #ffffff;
            border: none;
            padding: 12px 20px;
            border-radius: var(--na-border-radius);
            font-weight: 600;
            font-size: 11pt;
            cursor: pointer;
            margin-top: 10px;
            transition: all 0.2s ease;
        }

        .NA_Notepad_button:hover {
            background: var(--na-primary-hover);
            box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);
        }

        .Notepad_button_container {
            display: flex;
            justify-content: space-between;
            margin-top: 15px;
        }
        CSS
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------



    # -----------------------------------------------------------------------------
    # REGION | Dialog Creation
    # -----------------------------------------------------------------------------

    # FUNCTION | Create HTML Dialog
    # ------------------------------------------------------------
    def create_dialog
        @dialog = UI::HtmlDialog.new(
            dialog_title:    "Noble Architecture | Notepad",                 # <-- Dialog window title
            preferences_key: "com.noble-architecture.notepad",                # <-- Preferences key
            scrollable:      true,                                            # <-- Enable scrolling
            resizable:       true,                                            # <-- Allow resize
            width:           625,                                             # <-- Window width
            height:          900,                                             # <-- Window height
            style:           UI::HtmlDialog::STYLE_DIALOG                    # <-- Dialog style
        )

        # Locate logo path
        plugin_dir  = File.dirname(__FILE__)                                 # <-- Get plugin directory
        logo_path   = File.join(plugin_dir, "Na__Common__PluginDependencies", "IMG01__PNG__NaCompanyLogo.png")  # <-- Logo path
        logo_exists = File.exist?(logo_path)                                 # <-- Check if logo exists

        html_content = <<-HTML
            <!DOCTYPE html>
            <html lang="en">
            <head>
                <meta charset="UTF-8">
                <title>Noble Architecture | Notepad</title>
                <style>
                #{stylesheet}
                </style>
            </head>
            <body>
                <div class="NA_header">
                    <h2>Notepad</h2>
                    #{logo_exists ? "<img src=\"file:///#{logo_path.gsub('\\', '/')}\" class=\"NA_logo\" alt=\"Noble Architecture\">" : ""}
                </div>
                
                <div class="NA_Notepad_info">
                    <p>Notes are automatically saved with this model file.</p>
                </div>
                
                <textarea id="Notepad_textarea" placeholder="Enter your notes here..."></textarea>
                <div id="Notepad_status">Last saved: -</div>
                <div class="Notepad_autosave_status">Autosave enabled (every 5 minutes)</div>
                <div class="Notepad_button_container">
                    <button class="NA_Notepad_button" onclick="clearNotes()">Clear Notes</button>
                    <button class="NA_Notepad_button" onclick="saveNotes()">Save Notes</button>
                </div>

                <script>
                let saveTimer = null;
                let autoSaveTimer = null;
                let lastSavedContent = '';
                let hasUnsavedChanges = false;

                window.onload = function() {
                    sketchup.getNotes();
                    document.getElementById('Notepad_textarea')
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
                    const notes = document.getElementById('Notepad_textarea').value;
                    sketchup.saveNotes(notes);
                    lastSavedContent = notes;
                    hasUnsavedChanges = false;
                    updateSaveStatus();
                }
                function clearNotes() {
                    if (confirm('Are you sure you want to clear all notes?')) {
                        document.getElementById('Notepad_textarea').value = '';
                        saveNotes();
                    }
                }
                function setNotes(content) {
                    document.getElementById('Notepad_textarea').value = content;
                    lastSavedContent = content;
                    hasUnsavedChanges = false;
                    updateSaveStatus();
                }
                function updateSaveStatus() {
                    const now = new Date();
                    const timeStr = now.toLocaleTimeString();
                    document.getElementById('Notepad_status').textContent = 'Last saved: ' + timeStr;
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

        @dialog.set_html(html_content)                                       # <-- Set dialog HTML content

        @dialog.add_action_callback('saveNotes') do |_dlg, notes|
            save_notes_to_model(notes)                                        # <-- Save notes callback
        end
        @dialog.add_action_callback('getNotes') do |_dlg|
            notes = get_notes_from_model                                     # <-- Get notes from model
            @dialog.execute_script("setNotes('#{escape_js(notes)}');")      # <-- Send notes to dialog
        end
        @dialog.add_action_callback('checkForUnsavedChanges') do |_dlg|
            # Handled in JS                                                  # <-- Unsaved changes handled client-side
        end

        add_model_observers                                                  # <-- Add model observers
        @dialog                                                              # <-- Return dialog
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Model Observers
    # -----------------------------------------------------------------------------

    # FUNCTION | Add Model Observers
    # ------------------------------------------------------------
    def add_model_observers
        return if @observer_added                                            # <-- Exit if already added
        @model_observer = NotepadModelObserver.new                           # <-- Create observer instance
        Sketchup.active_model.add_observer(@model_observer)                 # <-- Add observer to model
        @observer_added = true                                               # <-- Mark as added
    end
    # ---------------------------------------------------------------

    # FUNCTION | Save Current Notes (Called by Observer)
    # ------------------------------------------------------------
    def save_current_notes
        return unless @dialog && @dialog.visible?                            # <-- Exit if dialog not visible
        @dialog.execute_script("saveNotes();")                              # <-- Trigger save via JavaScript
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Data Persistence
    # -----------------------------------------------------------------------------

    # FUNCTION | Escape JavaScript String
    # ------------------------------------------------------------
    def escape_js(string)
        return '' if string.nil?                                             # <-- Return empty string for nil
        string.to_s.gsub(/\\/, '\\\\\\').gsub(/\n/, '\\n').gsub(/\r/, '\\r').gsub(/['"]/) { |m| "\\#{m}" }  # <-- Escape special characters
    end
    # ---------------------------------------------------------------

    # FUNCTION | Save Notes to Model Dictionary
    # ------------------------------------------------------------
    def save_notes_to_model(notes)
        model = Sketchup.active_model                                        # <-- Get active model
        return if model.nil?                                                 # <-- Exit if no model
        model.start_operation("Save Notebook Notes", true)                   # <-- Begin undo operation
        dict = model.attribute_dictionary("na_notebook_dictionary")          # <-- Get attribute dictionary
        if dict.nil?
            model.set_attribute("na_notebook_dictionary", "notes", notes)    # <-- Create dictionary and save
        else
            model.set_attribute("na_notebook_dictionary", "notes", notes)    # <-- Save to existing dictionary
        end
        model.commit_operation                                               # <-- Commit undo operation
    end
    # ---------------------------------------------------------------

    # FUNCTION | Get Notes from Model Dictionary
    # ------------------------------------------------------------
    def get_notes_from_model
        model = Sketchup.active_model                                        # <-- Get active model
        return '' if model.nil?                                              # <-- Return empty if no model
        dict = model.attribute_dictionary("na_notebook_dictionary")          # <-- Get attribute dictionary
        return '' if dict.nil?                                               # <-- Return empty if no dictionary
        dict["notes"] || ''                                                  # <-- Return notes or empty string
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Dialog Management
    # -----------------------------------------------------------------------------

    # FUNCTION | Show Notepad Dialog
    # ------------------------------------------------------------
    def show_notepad
        if @dialog && @dialog.visible?                                       # <-- Check if dialog already open
            @dialog.bring_to_front                                           # <-- Bring to front if open
        else
            @dialog = create_dialog                                          # <-- Create new dialog
            @dialog.show                                                     # <-- Show dialog
        end
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Public Entry Point
    # -----------------------------------------------------------------------------

    # FUNCTION | Run SketchUp Notepad (Hotkey Entry Point)
    # ------------------------------------------------------------
    # Bind this method in Preferences → Shortcuts
    # Method name: NotepadPlugin.Na__SketchUpNotepad__Run
    # ------------------------------------------------------------
    def self.Na__SketchUpNotepad__Run
        model = Sketchup.active_model                                        # <-- Get active model
        return unless model                                                  # <-- Exit if no active model

        show_notepad                                                         # <-- Show notepad dialog
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Menu Registration
    # -----------------------------------------------------------------------------

    # FUNCTION | Install Menu and Commands
    # ------------------------------------------------------------
    def self.install_menu_and_commands
        return if @menu_installed                                            # <-- Exit if already installed

        # Create UI command
        cmd = UI::Command.new('NA_SketchUpNotepad') do                       # <-- Create command
            NotepadPlugin.Na__SketchUpNotepad__Run                           # <-- Run logic
        end
        cmd.tooltip = "Open SketchUp Notepad"                                # <-- Tooltip
        cmd.status_bar_text = "Open model-persistent notepad"                # <-- Status bar
        cmd.menu_text = "Na__SketchUpNotepad"                                # <-- Menu text

        # Add to Plugins menu
        UI.menu('Plugins').add_item(cmd)                                     # <-- Add item

        @menu_installed = true                                               # <-- Mark installed
    end
    # ---------------------------------------------------------------

    # FUNCTION | Activate for Model
    # ------------------------------------------------------------
    def self.activate_for_model(model)
        install_menu_and_commands                                            # <-- Install commands
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

end # End Module

# -----------------------------------------------------------------------------
# FILE LOADED CHECK
# -----------------------------------------------------------------------------
unless file_loaded?(__FILE__)
    NotepadPlugin.activate_for_model(Sketchup.active_model)                 # <-- Activate
    file_loaded(__FILE__)                                                    # <-- Mark loaded
end
