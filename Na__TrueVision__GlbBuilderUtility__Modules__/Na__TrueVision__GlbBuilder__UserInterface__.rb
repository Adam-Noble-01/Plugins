# =============================================================================
# TRUEVISION3D - GLB BUILDER UTILITY - USER INTERFACE MODULE
# =============================================================================
#
# FILE       : Na__TrueVision__GlbBuilder__UserInterface__.rb
# NAMESPACE  : TrueVision3D::GlbBuilderUtility
# MODULE     : User Interface (HTML Dialog and Menu Integration)
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : User interface management - HTML dialogs, callbacks, and menu integration
# CREATED    : 2025
#
# DESCRIPTION:
# - HTML dialog generation and management
# - Callback and event handling API
# - Menu integration for SketchUp Extensions menu
# - Provides robust communication between UI and core export functionality
#
# DEPENDENCIES:
# - Requires module constants from main file (@excluded_layers, etc.)
# - Requires functions from main file (organize_entities_by_tags, perform_export, start_export)
# - Accesses module instance variables (@export_dialog, @export_selection_only, @downscale_textures)
#
# =============================================================================

module TrueVision3D
    module GlbBuilderUtility
    
    # =============================================================================
    # REGION | Dialog Management - Main Dialog Control
    # =============================================================================
    
        # FUNCTION | Show Export Options Dialog
        # ------------------------------------------------------------
        def self.Na__UserInterface__ShowExportDialog
            begin
                @export_dialog.close if @export_dialog && @export_dialog.visible?      # Close if already open
                
                @export_dialog = UI::HtmlDialog.new(
                    :dialog_title => "TrueVision3D GLB Export Options",                # <-- Dialog title
                    :preferences_key => "TrueVision3D_GLBExport",                      # <-- Preferences key
                    :scrollable => true,                                               # <-- Allow content scrolling
                    :resizable => true,                                                # <-- User resizable
                    :width => 560,                                                     # <-- Dialog width
                    :height => 660,                                                    # <-- Dialog height (fits 1080p at 100% scale)
                    :min_width => 420,                                                 # <-- Minimum usable width
                    :min_height => 380,                                                # <-- Minimum usable height
                    :left => 200,                                                      # <-- X position
                    :top => 120                                                        # <-- Y position
                )
                
                html_content = self.Na__UserInterface__GenerateDialogHtml
                @export_dialog.set_html(html_content)
                self.Na__UserInterface__AddDialogCallbacks(@export_dialog)
                @export_dialog.show
            rescue => e
                Na__Log__Warn "ERROR in Na__UserInterface__ShowExportDialog: #{e.message}"
                Na__Log__Warn "Backtrace: #{e.backtrace.first(10).join("\n")}"
                UI.messagebox("Dialog error: #{e.message}\n\nCheck Ruby Console for details.")
            end
        end
        # ---------------------------------------------------------------
    
    # endregion ===================================================================
    
    # =============================================================================
    # REGION | HTML Generation - Dialog Content and Styling
    # =============================================================================
    
        # FUNCTION | Generate HTML for Export Dialog
        # ---------------------------------------------------------------
        def self.Na__UserInterface__GenerateDialogHtml
            excluded_count = @excluded_layers.length                                 # Count excluded layers
            model = Sketchup.active_model
            project_prefix = self.Na__Helpers__ExtractProjectPrefix(model)              # Extract project prefix
            tag_groups = self.Na__ExportCore__OrganizeEntitiesByTags(model)             # Get tag groups

            # Detect storey containers for grouped preview
            storey_containers = self.Na__ExportCore__DetectStoreyContainers(model)      # Scan for storey tags (90-93)
            has_storeys = storey_containers.any?                                       # Flag for storey mode

            # Remove storey entities from flat tag_groups for display
            if has_storeys
                storey_containers.each do |_storey_name, storey_entities|
                    Array(storey_entities).each do |storey_entity|
                        tag_groups.each { |_, entities| entities.delete(storey_entity) }
                    end
                end
                tag_groups.delete_if { |_, entities| entities.length == 0 }
            end

            # Count total exportable items
            total_export_count = tag_groups.length
            storey_export_plan = {}
            if has_storeys
                storey_containers.each do |storey_name, storey_entities|
                    element_groups = self.Na__ExportCore__OrganizeStoreyChildrenByTags(storey_entities, storey_name)
                    storey_export_plan[storey_name] = element_groups
                    total_export_count += element_groups.length
                end
            end

            # -----------------------------------------------------------
            # Build export manifest markup (rendered in lower scroll pane)
            # -----------------------------------------------------------
            export_list_html = ""                                                      # Accumulated file row markup
            total_file_count = 0                                                       # Running count of output GLB files

            if total_export_count == 0
                export_list_html = "<div class='empty-note'>No entities found with valid tag ranges</div>"
            else
                # Flat (non-storey) items first
                tag_groups.each do |filename, entities|
                    export_list_html += self.Na__UserInterface__BuildFileRow("#{project_prefix}#{filename}#{MESH_MODEL_SUFFIX}.glb", entities.length)
                    total_file_count += 1
                    if filename != "01__OrbitHelperCube"
                        export_list_html += self.Na__UserInterface__BuildFileRow("#{project_prefix}#{filename}#{LINEWORK_MODEL_SUFFIX}.glb", entities.length)
                        total_file_count += 1
                    end
                end

                # Storey-grouped items in collapsible sections
                if has_storeys
                    storey_export_plan.each do |storey_name, element_groups|
                        display_name  = storey_name.gsub("Storey__", "").gsub(/([a-z])([A-Z])/, '\1 \2')
                        storey_rows   = ""
                        storey_files  = 0

                        element_groups.each do |element_name, entities|
                            base_filename = "#{storey_name}__#{element_name}"
                            storey_rows  += self.Na__UserInterface__BuildFileRow("#{project_prefix}#{base_filename}#{MESH_MODEL_SUFFIX}.glb", entities.length)
                            storey_rows  += self.Na__UserInterface__BuildFileRow("#{project_prefix}#{base_filename}#{LINEWORK_MODEL_SUFFIX}.glb", entities.length)
                            storey_files += 2
                        end

                        total_file_count += storey_files
                        export_list_html += "<details class='storey-block' open>" \
                                            "<summary class='storey-heading'>&#127970; #{display_name}" \
                                            "<span class='entity-count'>#{storey_files} files</span></summary>" \
                                            "#{storey_rows}</details>\n"
                    end
                end
            end

            # -----------------------------------------------------------
            # Status notes rendered above the manifest in the output pane
            # -----------------------------------------------------------
            notes_html = ""

            if has_storeys
                total_storey_containers = storey_containers.values.map(&:length).sum
                notes_html += "<div class='note note-storey'><strong>Storey Mode Active:</strong> " \
                              "#{storey_containers.length} storey key(s), #{total_storey_containers} container(s) detected. " \
                              "Duplicate storey containers are merged per-storey.</div>"
            end

            if excluded_count > 0
                notes_html += "<div class='note note-excluded'><strong>#{excluded_count} layer(s)</strong> matching " \
                              "'#{EXCLUDED_LAYER_DESCRIPTION}' will be excluded</div>"
            end

            file_count_label = total_export_count == 0 ? "Nothing to export" : "#{total_file_count} GLB files"

            html = <<-HTML
            <!DOCTYPE html>
            <html>
            <head>
                <meta charset="UTF-8">
                <style>
                    /* CSS Variables - TrueVision3D Standards */
                    :root {
                        --FontCol_TrueVisionStandardTextColour   : #1e1e1e;
                        --FontCol_TrueVisionLinkTextColour       : #336699;
                        --TrueVisionBackgroundColor              : #f5f5f5;
                        --TrueVisionBorderColor                  : #172b3a;
                        --TrueVisionButtonBackground             : #172b3a;
                        --TrueVisionButtonHover                  : #2a4558;
                        font-size                                : 13px;
                    }

                    *, *::before, *::after { box-sizing: border-box; }

                    /* Base Layout - Fixed Shell With Internal Scroll Panes */
                    html, body {
                        height                                   : 100%;
                        margin                                   : 0;
                        padding                                  : 0;
                    }

                    body {
                        display                                  : flex;
                        flex-direction                           : column;
                        overflow                                 : hidden;
                        font-family                              : Arial, sans-serif;
                        font-size                                : 13px;
                        color                                    : var(--FontCol_TrueVisionStandardTextColour);
                        background-color                         : var(--TrueVisionBackgroundColor);
                    }

                    /* Scroll Pane Styling */
                    .scroll-pane {
                        overflow-y                               : auto;
                        overflow-x                               : hidden;
                    }

                    .scroll-pane::-webkit-scrollbar               { width: 11px; }
                    .scroll-pane::-webkit-scrollbar-track         { background: #e6e8ea; }
                    .scroll-pane::-webkit-scrollbar-thumb         { background: #9aa5ad; border-radius: 6px; border: 2px solid #e6e8ea; }
                    .scroll-pane::-webkit-scrollbar-thumb:hover   { background: var(--TrueVisionButtonHover); }

                    /* Header Bar */
                    .app-header {
                        flex                                     : 0 0 auto;
                        padding                                  : 9px 14px;
                        background                               : var(--TrueVisionBorderColor);
                        color                                    : #ffffff;
                    }

                    .app-header h1 {
                        margin                                   : 0;
                        font-size                                : 14px;
                        letter-spacing                           : 0.4px;
                    }

                    /* Configuration Pane - Top Section */
                    .config-pane {
                        flex                                     : 0 1 auto;
                        min-height                               : 0;
                        padding                                  : 10px 14px 3px 14px;
                    }

                    .option-group {
                        background                               : #ffffff;
                        border                                   : 1px solid #e2e5e8;
                        border-radius                            : 4px;
                        padding                                  : 7px 10px;
                        margin-bottom                            : 7px;
                    }

                    label {
                        display                                  : block;
                        margin                                   : 0;
                        font-weight                              : bold;
                        font-size                                : 12.5px;
                        cursor                                   : pointer;
                    }

                    input[type="checkbox"] {
                        margin-right                             : 7px;
                        vertical-align                           : middle;
                    }

                    .info-text {
                        font-size                                : 11px;
                        line-height                              : 1.35;
                        color                                    : #666666;
                        margin-top                               : 4px;
                        padding-left                             : 21px;
                    }

                    /* Action Bar - Buttons Pinned Below Configuration */
                    .action-bar {
                        flex                                     : 0 0 auto;
                        padding                                  : 5px 14px 10px 14px;
                        background                               : var(--TrueVisionBackgroundColor);
                    }

                    .action-row {
                        display                                  : flex;
                        gap                                      : 7px;
                    }

                    .action-row.secondary {
                        margin-top                               : 7px;
                        padding-top                              : 8px;
                        border-top                               : 1px solid #dcdfe2;
                    }

                    button {
                        flex                                     : 1 1 auto;
                        padding                                  : 8px 12px;
                        background                               : var(--TrueVisionButtonBackground);
                        color                                    : white;
                        border                                   : none;
                        border-radius                            : 4px;
                        cursor                                   : pointer;
                        font-family                              : Arial, sans-serif;
                        font-size                                : 13px;
                    }

                    button:hover:not(:disabled) {
                        background                               : var(--TrueVisionButtonHover);
                    }

                    button:disabled {
                        background                               : #999999;
                        cursor                                   : not-allowed;
                    }

                    .btn-primary                                  { font-weight: bold; }
                    .btn-cancel                                   { flex: 0 0 110px; background: #6b7780; }
                    .btn-cancel:hover:not(:disabled)              { background: #566169; }
                    .btn-setup                                    { background: #2c6e49; font-size: 11.5px; padding: 7px 10px; }
                    .btn-setup:hover:not(:disabled)               { background: #37855a; }
                    .btn-reload                                   { flex: 0 0 130px; background: #95a5a6; font-size: 11.5px; padding: 7px 10px; }
                    .btn-reload:hover:not(:disabled)              { background: #7f8c8d; }

                    /* Output Pane - Bottom Section, Scrolls Independently */
                    .output-pane {
                        flex                                     : 1 1 auto;
                        display                                  : flex;
                        flex-direction                           : column;
                        min-height                               : 92px;
                        border-top                               : 1px solid #c9ccd0;
                        background                               : #f0f5f0;
                    }

                    .output-header {
                        flex                                     : 0 0 auto;
                        display                                  : flex;
                        justify-content                          : space-between;
                        align-items                              : center;
                        padding                                  : 6px 14px;
                        background                               : #e1ece3;
                        border-bottom                            : 1px solid #c3e6cb;
                        font-size                                : 12px;
                        font-weight                              : bold;
                        color                                    : var(--TrueVisionBorderColor);
                    }

                    .output-count {
                        font-weight                              : normal;
                        font-size                                : 11px;
                        color                                    : #4b5a52;
                    }

                    .output-body {
                        flex                                     : 1 1 auto;
                        min-height                               : 0;
                        padding                                  : 8px 14px 12px 14px;
                    }

                    /* File Manifest Rows */
                    .file-row {
                        display                                  : flex;
                        gap                                      : 10px;
                        align-items                              : baseline;
                        font-size                                : 11px;
                        color                                    : #3a4550;
                        padding                                  : 1px 0;
                    }

                    .file-name {
                        flex                                     : 1 1 auto;
                        min-width                                : 0;
                        overflow-wrap                            : anywhere;
                    }

                    .entity-count {
                        flex                                     : 0 0 auto;
                        font-size                                : 10px;
                        font-weight                              : normal;
                        color                                    : #7b868f;
                    }

                    .empty-note {
                        font-style                               : italic;
                        font-size                                : 12px;
                        color                                    : #7b868f;
                    }

                    /* Collapsible Storey Sections */
                    .storey-block {
                        margin-top                               : 9px;
                    }

                    .storey-heading {
                        display                                  : flex;
                        justify-content                          : space-between;
                        align-items                              : baseline;
                        gap                                      : 10px;
                        font-weight                              : bold;
                        font-size                                : 11.5px;
                        color                                    : var(--TrueVisionBorderColor);
                        padding                                  : 3px 0;
                        margin-bottom                            : 3px;
                        border-bottom                            : 1px solid #c3e6cb;
                        cursor                                   : pointer;
                        list-style                               : none;
                        user-select                              : none;
                    }

                    .storey-heading::-webkit-details-marker       { display: none; }
                    .storey-block > summary::before               { content: "▸ "; }
                    .storey-block[open] > summary::before         { content: "▾ "; }

                    /* Status Notes */
                    .note {
                        border-radius                            : 4px;
                        padding                                  : 6px 9px;
                        margin-bottom                            : 8px;
                        font-size                                : 11px;
                        line-height                              : 1.35;
                    }

                    .note-storey {
                        background                               : #e8f4f8;
                        border                                   : 1px solid #b8daff;
                        color                                    : var(--TrueVisionBorderColor);
                    }

                    .note-excluded {
                        background                               : #fff3cd;
                        border                                   : 1px solid #ffeaa7;
                    }

                    /* Footer Strip */
                    .app-footer {
                        flex                                     : 0 0 auto;
                        padding                                  : 6px 14px 7px 14px;
                        border-top                               : 1px solid #c9ccd0;
                        background                               : var(--TrueVisionBackgroundColor);
                        font-size                                : 10.5px;
                        line-height                              : 1.35;
                        color                                    : #7b868f;
                    }
                </style>
            </head>
            <body>

                <!-- Header -->
                <div class="app-header">
                    <h1>TrueVision3D GLB Builder Utility</h1>
                </div>

                <!-- Configuration Options (Top) -->
                <div class="config-pane scroll-pane">
                    <div class="option-group">
                        <label>
                            <input type="checkbox" id="export-materials" checked onchange="Na__TrueVision__GlbBuilder__ToggleMaterials()">
                            Export Materials
                        </label>
                        <div class="info-text">
                            When unchecked, meshes export with a default whitecard material for clean massing models,
                            except MAT000E__ exempt materials which still write colour + texture into the GLB.
                            Materials are resolved per-face only (group/component materials are not inherited).
                        </div>
                    </div>

                    <div class="option-group" id="indexed-materials-group">
                        <label>
                            <input type="checkbox" id="export-indexed-only" checked>
                            Export Standard Indexed Materials Only
                        </label>
                        <div class="info-text">
                            Only export materials matching the standard naming convention (MAT001__, MAT101__, etc.)
                            from the materials library, plus exempt materials (MAT000E__). Custom materials are replaced
                            with the default whitecard. Uncheck to export all SketchUp materials.
                        </div>
                    </div>

                    <div class="option-group">
                        <label>
                            <input type="checkbox" id="downscale-textures">
                            Optimize Large Textures
                        </label>
                        <div class="info-text">
                            Downscale textures larger than 1024px for smaller GLB file sizes.
                            Uncheck for full-resolution texture export.
                        </div>
                    </div>
                </div>

                <!-- Action Buttons (Top, Always Visible) -->
                <div class="action-bar">
                    <div class="action-row">
                        <button class="btn-primary" onclick="Na__TrueVision__GlbBuilder__PerformExport()" #{total_export_count == 0 ? 'disabled' : ''}>Export GLB Files</button>
                        <button class="btn-cancel" onclick="Na__TrueVision__GlbBuilder__CancelExport()">Cancel</button>
                    </div>
                    <div class="action-row secondary">
                        <button class="btn-setup" onclick="Na__TrueVision__GlbBuilder__CreateStandardisedTags()">Create Standardised Tags From Index</button>
                        <button class="btn-reload" onclick="Na__TrueVision__GlbBuilder__ReloadScripts()">&#128260; Reload Scripts</button>
                    </div>
                </div>

                <!-- Export Manifest Output (Bottom, Scrollable) -->
                <div class="output-pane">
                    <div class="output-header">
                        <span>Files to be exported</span>
                        <span class="output-count">#{file_count_label}</span>
                    </div>
                    <div class="output-body scroll-pane">
                        #{notes_html}
                        #{export_list_html}
                    </div>
                </div>

                <!-- Footer -->
                <div class="app-footer">
                    <strong>Export Method:</strong> Non-destructive virtual flattening with recursive traversal.
                    All transformations are accumulated and applied without modifying your model.
                </div>

                <script>
                    function Na__TrueVision__GlbBuilder__ToggleMaterials() {
                        var exportMaterials     = document.getElementById('export-materials').checked;
                        var indexedGroup        = document.getElementById('indexed-materials-group');
                        if (exportMaterials) {
                            indexedGroup.style.opacity       = '1.0';
                            indexedGroup.style.pointerEvents = 'auto';
                        } else {
                            indexedGroup.style.opacity       = '0.4';
                            indexedGroup.style.pointerEvents = 'none';
                        }
                    }

                    function Na__TrueVision__GlbBuilder__PerformExport() {
                        var selectionOnly       = false;
                        var downscaleTextures   = document.getElementById('downscale-textures').checked;
                        var exportMaterials     = document.getElementById('export-materials').checked;
                        var indexedOnly         = document.getElementById('export-indexed-only').checked;

                        var materialExportMode  = 'no_materials';
                        if (exportMaterials && indexedOnly) {
                            materialExportMode  = 'indexed_only';
                        } else if (exportMaterials && !indexedOnly) {
                            materialExportMode  = 'all_materials';
                        }

                        var params = {
                            selectionOnly        : selectionOnly,
                            downscaleTextures    : downscaleTextures,
                            materialExportMode   : materialExportMode
                        };

                        window.location = 'skp:Na__TrueVision__GlbBuilder__Export@' + JSON.stringify(params);
                    }

                    function Na__TrueVision__GlbBuilder__CancelExport() {
                        window.location = 'skp:Na__TrueVision__GlbBuilder__Cancel';
                    }

                    function Na__TrueVision__GlbBuilder__CreateStandardisedTags() {
                        window.location = 'skp:Na__TrueVision__GlbBuilder__CreateTags';
                    }

                    function Na__TrueVision__GlbBuilder__ReloadScripts() {
                        window.location = 'skp:Na__TrueVision__GlbBuilder__Reload';
                    }
                </script>
            </body>
            </html>
            HTML

            html
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Build a Single File Manifest Row
        # ---------------------------------------------------------------
        def self.Na__UserInterface__BuildFileRow(file_name, entity_count)
            "<div class='file-row'><span class='file-name'>#{file_name}</span>" \
            "<span class='entity-count'>#{entity_count} entities</span></div>\n"
        end
        # ---------------------------------------------------------------
    
    # endregion ===================================================================
    
    # =============================================================================
    # REGION | Event Handling - Callback Registration and Processing
    # =============================================================================
    
        # FUNCTION | Add Dialog Callbacks with Robust Event Handling
        # ---------------------------------------------------------------
        def self.Na__UserInterface__AddDialogCallbacks(dialog)
            # Callback: Create Standardised Tags From Index
            dialog.add_action_callback("Na__TrueVision__GlbBuilder__CreateTags") do |action_context|
                begin
                    TrueVision3D::GlbBuilderUtility.Na__PublicApi__CreateStandardisedTags
                rescue => e
                    Na__Log__Warn "    ✗ Error in create tags callback: #{e.message}"
                    Na__Log__Warn e.backtrace.join("\n")
                    UI.messagebox("Error creating tags: #{e.message}")
                end
            end

            # Callback: Reload Scripts (Developer Feature)
            dialog.add_action_callback("Na__TrueVision__GlbBuilder__Reload") do |action_context|
                begin
                    TrueVision3D::GlbBuilderUtility.Na__DevTools__ReloadScripts
                rescue => e
                    Na__Log__Warn "    ✗ Error in reload callback: #{e.message}"
                    Na__Log__Warn e.backtrace.join("\n")
                end
            end
            
            # Export callback - robust event handling
            dialog.add_action_callback("Na__TrueVision__GlbBuilder__Export") do |action_context, params_string|
                begin
                    if params_string && !params_string.empty?
                        params = JSON.parse(params_string)
                        @export_selection_only = params['selectionOnly']
                        @downscale_textures = params['downscaleTextures'] == true

                        mode_string = params['materialExportMode'] || 'no_materials'
                        mode_sym = mode_string.to_sym
                        self.Na__MaterialEngine__SetExportMode(mode_sym)
                    else
                        @export_selection_only = false
                        @downscale_textures = false
                        self.Na__MaterialEngine__SetExportMode(:no_materials)
                    end
                    
                rescue => e
                    Na__Log__Warn "Parameter parsing error: #{e.message}"
                    @export_selection_only = false
                    @downscale_textures = false
                    self.Na__MaterialEngine__SetExportMode(:no_materials)
                end
                
                dialog.close                                                           # Close dialog
                
                # Get save directory from user
                begin
                    export_dir = UI.select_directory(title: "Select Export Directory")
                    
                    if export_dir
                        self.Na__PublicApi__PerformExport(export_dir)
                    end
                rescue => e
                    Na__Log__Warn "ERROR in export directory selection: #{e.message}"
                    UI.messagebox("Error selecting export directory: #{e.message}")
                end
            end
            
            dialog.add_action_callback("Na__TrueVision__GlbBuilder__Cancel") do |action_context|
                dialog.close
            end
            
            dialog.set_on_closed {}
        end
        # ---------------------------------------------------------------
    
    # endregion ===================================================================

    end  # module GlbBuilderUtility
end  # module TrueVision3D
