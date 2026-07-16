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
                    :scrollable => false,                                              # <-- No scrolling
                    :resizable => false,                                               # <-- Fixed size
                    :width => 600,                                                     # <-- Dialog width
                    :height => 900,                                                    # <-- Dialog height
                    :left => 200,                                                      # <-- X position
                    :top => 200                                                        # <-- Y position
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
                        font-size                                : 14px;
                    }
    
                    /* Base Layout Styles */
                    html, body {
                        margin                                   : 0;
                        padding                                  : 20px;
                        font-family                              : Arial, sans-serif;
                        font-size                                : 14px;
                        color                                    : var(--FontCol_TrueVisionStandardTextColour);
                        background-color                         : var(--TrueVisionBackgroundColor);
                    }
    
                    /* Form Styles */
                    h1 {
                        font-size                                : 18px;
                        margin-bottom                            : 20px;
                        color                                    : var(--TrueVisionBorderColor);
                    }
    
                    .option-group {
                        margin-bottom                            : 15px;
                        padding                                  : 10px;
                        background                               : white;
                        border-radius                            : 4px;
                    }
    
                    label {
                        display                                  : block;
                        margin-bottom                            : 5px;
                        font-weight                              : bold;
                    }
    
                    input[type="checkbox"] {
                        margin-right                             : 8px;
                        vertical-align                           : middle;
                    }
    
                    .info-text {
                        font-size                                : 12px;
                        color                                    : #666;
                        margin-top                               : 5px;
                    }
    
                    .excluded-info {
                        background                               : #fff3cd;
                        border                                   : 1px solid #ffeaa7;
                        padding                                  : 8px;
                        border-radius                            : 4px;
                        margin-top                               : 10px;
                        font-size                                : 12px;
                    }
                    
                    .export-info {
                        background                               : #d4edda;
                        border                                   : 1px solid #c3e6cb;
                        padding                                  : 10px;
                        border-radius                            : 4px;
                        margin                                   : 15px 0;
                        font-size                                : 13px;
                    }
                    
                    .export-list {
                        margin                                   : 10px 0;
                        padding-left                             : 20px;
                        font-size                                : 12px;
                        color                                    : #555;
                    }

                    .storey-heading {
                        font-weight                              : bold;
                        font-size                                : 12px;
                        color                                    : #172b3a;
                        margin-top                               : 8px;
                        margin-bottom                            : 4px;
                        padding-bottom                           : 2px;
                        border-bottom                            : 1px solid #c3e6cb;
                    }

                    .storey-badge {
                        background                               : #e8f4f8;
                        border                                   : 1px solid #b8daff;
                        padding                                  : 6px 10px;
                        border-radius                            : 4px;
                        margin                                   : 10px 0;
                        font-size                                : 12px;
                        color                                    : #172b3a;
                    }
    
                    /* Button Styles */
                    .button-group {
                        margin-top                               : 20px;
                        text-align                               : center;
                    }
    
                    button {
                        padding                                  : 8px 20px;
                        margin                                   : 0 5px;
                        background                               : var(--TrueVisionButtonBackground);
                        color                                    : white;
                        border                                   : none;
                        border-radius                            : 4px;
                        cursor                                   : pointer;
                        font-size                                : 14px;
                    }
    
                    button:hover {
                        background                               : var(--TrueVisionButtonHover);
                    }
    
                    button:disabled {
                        background                               : #999;
                        cursor                                   : not-allowed;
                    }
                </style>
            </head>
            <body>
                <h1>TrueVision3D GLB Builder Utility</h1>
                
                <div class="export-info">
                    <strong>Files to be exported:</strong>
                    <div class="export-list">
            HTML
            
            if total_export_count == 0
                html += "        <em>No entities found with valid tag ranges</em>\n"
            else
                # Show flat (non-storey) items first
                tag_groups.each do |filename, entities|
                    html += "        &bull; #{project_prefix}#{filename}#{MESH_MODEL_SUFFIX}.glb (#{entities.length} entities)<br>\n"
                    if filename != "01__OrbitHelperCube"
                        html += "        &bull; #{project_prefix}#{filename}#{LINEWORK_MODEL_SUFFIX}.glb (#{entities.length} entities)<br>\n"
                    end
                end

                # Show storey-grouped items
                if has_storeys
                    storey_export_plan.each do |storey_name, element_groups|
                        # Storey section heading
                        display_name = storey_name.gsub("Storey__", "").gsub(/([a-z])([A-Z])/, '\1 \2')
                        html += "        <div class='storey-heading'>&#127970; #{display_name}</div>\n"

                        element_groups.each do |element_name, entities|
                            base_filename = "#{storey_name}__#{element_name}"
                            html += "        &bull; #{project_prefix}#{base_filename}#{MESH_MODEL_SUFFIX}.glb (#{entities.length} entities)<br>\n"
                            html += "        &bull; #{project_prefix}#{base_filename}#{LINEWORK_MODEL_SUFFIX}.glb (#{entities.length} entities)<br>\n"
                        end
                    end
                end
            end

            # Storey mode badge (shown when storey containers are detected)
            storey_badge_html = ""
            if has_storeys
                total_storey_containers = storey_containers.values.map(&:length).sum
                storey_badge_html = "<div class='storey-badge'><strong>Storey Mode Active:</strong> #{storey_containers.length} storey key(s), #{total_storey_containers} container(s) detected. Duplicate storey containers are merged per-storey.</div>"
            end
            
            html += <<-HTML
                    </div>
                </div>

                #{storey_badge_html}
                
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
                        MAT000E__ exempt materials always export in every mode.
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
                
                <div class="info-text" style="background: #e8f4f8; padding: 10px; border-radius: 4px; margin: 10px 0;">
                    <strong>Export Method:</strong> Non-destructive virtual flattening with recursive traversal.
                    All transformations are accumulated and applied without modifying your model.
                </div>
                
                #{excluded_count > 0 ? "<div class='excluded-info'>#{excluded_count} layer(s) matching '#{EXCLUDED_LAYER_DESCRIPTION}' will be excluded</div>" : ""}
                
                <div class="button-group">
                    <button onclick="Na__TrueVision__GlbBuilder__PerformExport()" #{total_export_count == 0 ? 'disabled' : ''}>Export GLB Files</button>
                    <button onclick="Na__TrueVision__GlbBuilder__CancelExport()">Cancel</button>
                </div>
                
                <!-- Model Setup Utilities -->
                <div class="button-group" style="margin-top: 15px; border-top: 1px solid #ddd; padding-top: 15px;">
                    <div style="font-size: 11px; color: #888; margin-bottom: 8px; text-align: left; font-weight: bold; text-transform: uppercase; letter-spacing: 0.5px;">Model Setup</div>
                    <button onclick="Na__TrueVision__GlbBuilder__CreateStandardisedTags()" style="background: #2c6e49;">
                        Create Standardised Tags From Index
                    </button>
                </div>
                
                <!-- Developer Tools -->
                <div class="button-group" style="margin-top: 15px; border-top: 1px solid #ddd; padding-top: 15px;">
                    <button onclick="Na__TrueVision__GlbBuilder__ReloadScripts()" style="background: #95a5a6; border-color: #7f8c8d;">
                        🔄 Reload Scripts
                    </button>
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
