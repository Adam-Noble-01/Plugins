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
            puts "DEBUG: Na__UserInterface__ShowExportDialog called"
            begin
                # Close existing dialog if open
                @export_dialog.close if @export_dialog && @export_dialog.visible?      # Close if already open
                
                # Create new dialog
                puts "DEBUG: Creating new UI::HtmlDialog"
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
                
                # Set dialog HTML
                puts "DEBUG: Generating dialog HTML"
                html_content = self.Na__UserInterface__GenerateDialogHtml
                puts "DEBUG: HTML generated, length: #{html_content.length} characters"
                @export_dialog.set_html(html_content)
                
                # Add callbacks
                puts "DEBUG: Adding dialog callbacks"
                self.Na__UserInterface__AddDialogCallbacks(@export_dialog)
                
                # Show dialog
                puts "DEBUG: Showing dialog"
                @export_dialog.show
                puts "DEBUG: Dialog.show() called successfully"
            rescue => e
                puts "ERROR in Na__UserInterface__ShowExportDialog: #{e.message}"
                puts "Backtrace: #{e.backtrace.first(10).join("\n")}"
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
                storey_containers.each do |storey_name, storey_entity|
                    tag_groups.each { |_, entities| entities.delete(storey_entity) }
                end
                tag_groups.delete_if { |_, entities| entities.length == 0 }
            end

            # Count total exportable items
            total_export_count = tag_groups.length
            storey_export_plan = {}
            if has_storeys
                storey_containers.each do |storey_name, storey_entity|
                    element_groups = self.Na__ExportCore__OrganizeStoreyChildrenByTags(storey_entity, storey_name)
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
                storey_badge_html = "<div class='storey-badge'><strong>Storey Mode Active:</strong> #{storey_containers.length} storey container(s) detected. Building elements will be exported per-storey.</div>"
            end
            
            html += <<-HTML
                    </div>
                </div>

                #{storey_badge_html}
                
                <div class="option-group">
                    <label>
                        <input type="checkbox" id="downscale-textures" checked disabled>
                        Optimize Large Textures (Temporarily Disabled)
                    </label>
                    <div class="info-text">
                        Texture exporting is temporarily disabled until the core geometry engine is resolved.
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
                
                <!-- Developer Tools -->
                <div class="button-group" style="margin-top: 15px; border-top: 1px solid #ddd; padding-top: 15px;">
                    <button onclick="Na__TrueVision__GlbBuilder__ReloadScripts()" style="background: #95a5a6; border-color: #7f8c8d;">
                        🔄 Reload Scripts
                    </button>
                </div>
                
                <script>
                    function Na__TrueVision__GlbBuilder__PerformExport() {
                        var selectionOnly = false;  // Always export by tags
                        // DEBUG MODE: texture pipeline disabled while geometry export is being stabilized.
                        var downscaleTextures = false;
                        
                        // Pass parameters through the callback URL
                        var params = {
                            selectionOnly: selectionOnly,
                            downscaleTextures: downscaleTextures
                        };
                        
                        // Encode parameters and trigger callback
                        window.location = 'skp:Na__TrueVision__GlbBuilder__Export@' + JSON.stringify(params);
                    }
                    
                    function Na__TrueVision__GlbBuilder__CancelExport() {
                        window.location = 'skp:Na__TrueVision__GlbBuilder__Cancel';
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
            # Callback: Reload Scripts (Developer Feature)
            dialog.add_action_callback("Na__TrueVision__GlbBuilder__Reload") do |action_context|
                begin
                    puts "    🔄 Reload button clicked - reloading all scripts..."
                    TrueVision3D::GlbBuilderUtility.Na__DevTools__ReloadScripts
                    puts "    ✓ Reload callback executed successfully"
                rescue => e
                    puts "    ✗ Error in reload callback: #{e.message}"
                    puts e.backtrace.join("\n")
                end
            end
            
            # Export callback - robust event handling
            dialog.add_action_callback("Na__TrueVision__GlbBuilder__Export") do |action_context, params_string|
                puts "=== TrueVision3D GLB Export - Callback Received ==="
                puts "Export button clicked - processing parameters..."
                
                # Get parameters from the callback URL
                begin
                    if params_string && !params_string.empty?
                        puts "Parameters received: #{params_string}"
                        params = JSON.parse(params_string)                            # Parse JSON
                        @export_selection_only = params['selectionOnly']            # Set selection flag  
                        # DEBUG MODE: Texture export is intentionally disabled until core geometry is resolved.
                        @downscale_textures = false
                        puts "Parsed parameters: selection=#{@export_selection_only}, downscale=false (texture export disabled for debugging)"
                    else
                        # Default values if no parameters
                        @export_selection_only = false                                # Default values
                        @downscale_textures = false                                   # DEBUG default: texture export disabled
                        puts "Using default parameters"
                    end
                    
                rescue => e
                    puts "Parameter parsing error: #{e.message}"
                    puts "Error class: #{e.class}"
                    puts "Backtrace: #{e.backtrace.first(3).join("\n")}"
                    @export_selection_only = false                                     # Default values
                    @downscale_textures = false                                        # DEBUG fallback: texture export disabled
                end
                
                dialog.close                                                           # Close dialog
                
                # Get save directory from user
                begin
                    export_dir = UI.select_directory(title: "Select Export Directory")
                    
                    if export_dir
                        puts "Starting export to directory: #{export_dir}"
                        self.Na__PublicApi__PerformExport(export_dir)                       # Perform the export
                    else
                        puts "Export cancelled - no directory selected"
                    end
                rescue => e
                    puts "ERROR in export directory selection: #{e.message}"
                    UI.messagebox("Error selecting export directory: #{e.message}")
                end
            end
            
            # Cancel callback
            dialog.add_action_callback("Na__TrueVision__GlbBuilder__Cancel") do |action_context|
                puts "Export cancelled by user"
                dialog.close                                                           # Close dialog
            end
            
            # Error handling callback for any unhandled events
            dialog.set_on_closed {
                puts "Export dialog closed"
            }
        end
        # ---------------------------------------------------------------
    
    # endregion ===================================================================

    end  # module GlbBuilderUtility
end  # module TrueVision3D
