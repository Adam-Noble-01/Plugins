# =============================================================================
# TRUEVISION3D - GLB BUILDER UTILITY - USER INTERFACE MODULE
# =============================================================================
#
# FILE       : Na__TrueVision__GlbBuilder__UserInterface__.rb
# NAMESPACE  : TrueVision3D::GlbBuilderUtility
# MODULE     : User Interface (HtmlDialog Lifecycle and Ruby <-> JS Bridge)
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : User interface management - HtmlDialog, callbacks, and push API
# CREATED    : 2025
#
# DESCRIPTION:
# - Creates the UI::HtmlDialog with inlined CSS + JS from the 05__Plugin__UserInterface
#   asset files, following the ValeVision Cloud Sync dialog pattern.
# - Registers named action callbacks for export, site plan, rescan, tags and reload.
# - Builds the model status and export manifest as JSON and pushes it to the UI,
#   so a rescan never needs a full set_html round trip.
# - Renders the outcome of an export into the badge-driven report panel rather
#   than a modal message box.
#
# DEPENDENCIES:
# - Requires module constants from the main file (MESH_MODEL_SUFFIX, SITE_PLAN_TAG_PATTERN, etc.)
# - Requires Na__PathResolver__* helpers for asset paths
# - Requires Na__ExportCore__* helpers for the tag / storey / linetype scan
#
# -----------------------------------------------------------------------------
#
# DEVELOPMENT LOG:
# 2025 - Version 1.0.0
# - Original single-file HtmlDialog with inline HTML, CSS and JS.
#
# 19-Sep-2026 - Version 2.8.0
# - Rebuilt on the ValeVision Cloud Sync UI pattern: external HTML / CSS / JS
#   assets, Noble Architecture brand header, Open Sans face, tabbed layout,
#   action cards, and a badge-driven report panel.
# - Export now runs quiet and reports in-dialog; the dialog stays open.
#
# =============================================================================

require 'json'

module TrueVision3D
    module GlbBuilderUtility

    # =============================================================================
    # REGION | Dialog Lifecycle
    # =============================================================================

        # FUNCTION | Show Export Options Dialog
        # ---------------------------------------------------------------
        # Re-uses the open dialog when there is one, so the toolbar button and
        # the menu entry both behave like a toggle-to-front rather than stacking
        # duplicate windows.
        # ---------------------------------------------------------------
        def self.Na__UserInterface__ShowExportDialog
            if @export_dialog && @export_dialog.visible?
                @export_dialog.bring_to_front
                self.Na__UserInterface__PushModelStatus(@export_dialog)
                self.Na__UserInterface__PushProjectStatus(@export_dialog)
                return @export_dialog
            end

            @export_dialog = UI::HtmlDialog.new(
                :dialog_title    => 'TrueVision GLB Builder',                      # <-- Dialog title
                :preferences_key => 'Na__TrueVision__GlbBuilder__Dialog',          # <-- Remembers size and position
                :scrollable      => true,                                          # <-- Allow content scrolling
                :resizable       => true,                                          # <-- User resizable
                :width           => 620,                                           # <-- Dialog width
                :height          => 760,                                           # <-- Dialog height (fits 1080p at 100% scale)
                :min_width       => 460,                                           # <-- Minimum usable width
                :min_height      => 420,                                           # <-- Minimum usable height
                :left            => 200,                                           # <-- X position
                :top             => 100,                                           # <-- Y position
                :style           => UI::HtmlDialog::STYLE_DIALOG
            )

            @export_dialog.set_html(self.Na__UserInterface__GenerateDialogHtml)
            self.Na__UserInterface__AddDialogCallbacks(@export_dialog)
            @export_dialog.set_on_closed { @export_dialog = nil }
            @export_dialog.show
            @export_dialog
        rescue => e
            Na__Log__Warn "ERROR in Na__UserInterface__ShowExportDialog: #{e.message}"
            Na__Log__Warn "Backtrace: #{e.backtrace.first(10).join("\n")}"
            UI.messagebox("Dialog error: #{e.message}\n\nCheck Ruby Console for details.")
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Report Whether The Dialog Is Currently Visible
        # ---------------------------------------------------------------
        def self.Na__UserInterface__DialogVisible
            !!(@export_dialog && @export_dialog.visible?)
        end
        # ---------------------------------------------------------------

    # endregion ===================================================================


    # =============================================================================
    # REGION | HTML Rendering
    # =============================================================================

        # FUNCTION | Render The Dialog HTML From The Asset Templates
        # ---------------------------------------------------------------
        # The stylesheet and bridge script are inlined rather than linked so the
        # dialog needs no local web server and no file:// script permissions.
        # ---------------------------------------------------------------
        def self.Na__UserInterface__GenerateDialogHtml
            html_template      = File.read(self.Na__PathResolver__UiLayoutFilePath)
            stylesheet_content = File.read(self.Na__PathResolver__UiStylesheetFilePath)
            ui_bridge_script   = File.read(self.Na__PathResolver__UiBridgeFilePath)

            font_dir_uri = self.Na__UserInterface__FontDirectoryUri
            stylesheet_content = stylesheet_content.gsub('{{FONT_DIR_URI}}') { font_dir_uri }

            # NOTE | Every substitution below uses the BLOCK form of gsub on purpose.
            # The two-argument form interprets backslash sequences inside the
            # REPLACEMENT string: \\ collapses to \, and \' expands to the entire
            # post-match. The bridge script contains both (a JS string such as
            # 'model\'s ...', and the \\ in escAttr's regexes), so the two-argument
            # form silently shreds the script into a SyntaxError and no function on
            # the page is ever defined. The block form returns its value verbatim.
            logo_remote = self.Na__PathResolver__BrandLogoRemoteUrl
            logo_local  = self.Na__PathResolver__FileUriFor(self.Na__PathResolver__BrandLogoFilePath)
            title_text  = self.Na__UserInterface__EscapeHtml('TrueVision GLB Builder')

            html_template
                .gsub('{{DIALOG_TITLE}}')       { title_text }
                .gsub('{{LOGO_REMOTE_URL}}')    { logo_remote }
                .gsub('{{LOGO_FILE_URI}}')      { logo_local }
                .gsub('{{STYLESHEET_CONTENT}}') { stylesheet_content }
                .gsub('{{UI_BRIDGE_SCRIPT}}')   { ui_bridge_script }
        rescue => e
            Na__Log__Warn "ERROR rendering GLB Builder dialog HTML: #{e.message}"
            self.Na__UserInterface__FallbackHtml(e)
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Resolve The Bundled Font Directory As A file:/// URI
        # ---------------------------------------------------------------
        # The stylesheet lists this local copy first and the canonical
        # noble-architecture.com copy second, so Open Sans renders instantly
        # offline and still resolves if the bundled folder is ever missing.
        # ---------------------------------------------------------------
        def self.Na__UserInterface__FontDirectoryUri
            font_dir = self.Na__PathResolver__FontDirectory
            uri      = self.Na__PathResolver__FileUriFor(font_dir, require_exists: true)
            return uri unless uri.empty?

            Na__Log__Warn "[GlbBuilder] Bundled Open Sans folder not found at: #{font_dir} - falling back to the web font."
            'https://www.noble-architecture.com/na-apps/01__Assets__NaApps__CommonAssets/NaApps__CommonFonts'
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Minimal Fallback Markup When An Asset Is Missing
        # ---------------------------------------------------------------
        def self.Na__UserInterface__FallbackHtml(error)
            "<html><body style=\"font-family:Segoe UI,Arial,sans-serif;padding:20px;\">" \
            "<h2>TrueVision GLB Builder</h2>" \
            "<p>The dialog assets could not be loaded.</p>" \
            "<p><strong>#{self.Na__UserInterface__EscapeHtml(error.class.to_s)}:</strong> " \
            "#{self.Na__UserInterface__EscapeHtml(error.message)}</p>" \
            "<p>Expected assets in: <code>#{self.Na__UserInterface__EscapeHtml(self.Na__PathResolver__UiDirectory)}</code></p>" \
            "</body></html>"
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Escape Text For Safe HTML Interpolation
        # ---------------------------------------------------------------
        def self.Na__UserInterface__EscapeHtml(raw_text)
            raw_text.to_s
                .gsub('&', '&amp;')
                .gsub('<', '&lt;')
                .gsub('>', '&gt;')
                .gsub('"', '&quot;')
                .gsub("'", '&#39;')
        end
        # ---------------------------------------------------------------

    # endregion ===================================================================


    # =============================================================================
    # REGION | JS Bridge - Callback Registration
    # =============================================================================

        # FUNCTION | Register The Dialog Action Callbacks
        # ---------------------------------------------------------------
        def self.Na__UserInterface__AddDialogCallbacks(dialog)
            # Callback: the DOM is ready, push the initial model status
            dialog.add_action_callback('na_tvgb_dialog_ready') do |_ctx|
                self.Na__UserInterface__PushModelStatus(dialog)
                self.Na__UserInterface__PushProjectStatus(dialog)                  # <-- Carries should_prompt, which opens the link modal
            end

            # Callback: run one of the dialog actions
            dialog.add_action_callback('na_tvgb_run_action') do |_ctx, action_id, params_json|
                self.Na__UserInterface__HandleAction(dialog, action_id.to_s, params_json.to_s)
            end
        end
        # ---------------------------------------------------------------

    # endregion ===================================================================


    # =============================================================================
    # REGION | Action Handlers
    # =============================================================================

        # FUNCTION | Route A Dialog Action To Its Handler
        # ---------------------------------------------------------------
        # Every handler is wrapped so a fault reports into the dialog rather than
        # leaving the UI stuck behind a disabled button set.
        # ---------------------------------------------------------------
        def self.Na__UserInterface__HandleAction(dialog, action_id, params_json)
            case action_id
            when 'export_model'     then self.Na__UserInterface__ActionExportModel(dialog, params_json)
            when 'export_site_plan' then self.Na__UserInterface__ActionExportSitePlan(dialog)
            when 'rescan_model'     then self.Na__UserInterface__ActionRescanModel(dialog)
            when 'create_tags'      then self.Na__UserInterface__ActionCreateTags(dialog)
            when 'reload_plugin'    then self.Na__UserInterface__ActionReloadPlugin(dialog)
            when 'set_file_selection' then self.Na__UserInterface__ActionSetFileSelection(dialog, params_json)
            else
                # Project tab actions live in the ProjectActions module; it answers
                # false when the action is not one of its own.
                handled = self.respond_to?(:Na__UserInterface__HandleProjectAction) &&
                          self.Na__UserInterface__HandleProjectAction(
                              dialog, action_id, self.Na__UserInterface__ParseParams(params_json)
                          )

                unless handled
                    self.Na__UserInterface__PushStatus(dialog, "Unknown action: #{action_id}", 'error')
                    self.Na__UserInterface__PushReport(dialog, self.Na__UserInterface__BuildIdleReport)
                end
            end
        rescue => e
            Na__Log__Warn "    x Error in dialog action '#{action_id}': #{e.message}"
            Na__Log__Warn e.backtrace.first(10).join("\n")
            self.Na__UserInterface__PushStatus(dialog, "#{e.class}: #{e.message}", 'error')
            self.Na__UserInterface__PushReport(dialog, {
                success: false,
                running: false,
                message: "#{e.class}: #{e.message}",
                steps:   [{ label: 'Action', success: false, message: action_id }]
            })
        end
        # ---------------------------------------------------------------

        # ACTION HANDLER | Export The Model GLB Files
        # ---------------------------------------------------------------
        # Runs the export quiet so the outcome lands in the report panel instead
        # of a modal box, then reveals the output folder the way the old dialog
        # did once the report is on screen.
        # ---------------------------------------------------------------
        def self.Na__UserInterface__ActionExportModel(dialog, params_json)
            self.Na__UserInterface__ApplyExportParams(params_json)

            export_dir = UI.select_directory(title: 'Select Export Directory')
            unless export_dir
                self.Na__UserInterface__PushStatus(dialog, 'Export cancelled - no folder chosen.', 'info')
                self.Na__UserInterface__PushReport(dialog, self.Na__UserInterface__BuildIdleReport)
                return
            end

            self.Na__UserInterface__PushStatus(dialog, 'Exporting GLB files, please wait...', 'info')
            self.Na__UserInterface__PushReport(dialog, { running: true, steps: [] })

            self.Na__PublicApi__PerformExport(export_dir, quiet: true)             # <-- quiet: report panel replaces the modal

            summary = self.Na__ExportCore__LastExportSummary || {}
            report  = self.Na__UserInterface__BuildExportReport(summary, export_dir)

            self.Na__UserInterface__PushReport(dialog, report)
            self.Na__UserInterface__PushStatus(
                dialog,
                report[:message],
                report[:success] ? 'success' : 'error'
            )
            self.Na__UserInterface__PushModelStatus(dialog)

            self.Na__Helpers__OpenFolder(export_dir) if report[:success]           # <-- Reveal output, as the old dialog did
        end
        # ---------------------------------------------------------------

        # ACTION HANDLER | Export The Site Plan Drawing Data
        # ---------------------------------------------------------------
        # Na__SitePlan__Run owns its own confirm / folder-choice dialogs, so this
        # handler only records the outcome.
        # ---------------------------------------------------------------
        def self.Na__UserInterface__ActionExportSitePlan(dialog)
            self.Na__UserInterface__PushStatus(dialog, 'Exporting site plan data...', 'info')
            self.Na__UserInterface__PushReport(dialog, { running: true, steps: [] })

            succeeded = self.Na__PublicApi__ExportSitePlanData

            message = succeeded ? 'Site plan data exported.' : 'Site plan export did not complete.'
            self.Na__UserInterface__PushReport(dialog, {
                success: succeeded,
                running: false,
                message: message,
                steps:   [{
                    label:   'Site Plan Data',
                    success: succeeded,
                    message: succeeded ? 'Linework GLBs, fills and manifest written.' \
                                       : 'Cancelled, or nothing sits on a site plan tag (71-75).'
                }]
            })
            self.Na__UserInterface__PushStatus(dialog, message, succeeded ? 'success' : 'warning')
        end
        # ---------------------------------------------------------------

        # ACTION HANDLER | Rescan The Model And Rebuild The Manifest
        # ---------------------------------------------------------------
        def self.Na__UserInterface__ActionRescanModel(dialog)
            self.Na__UserInterface__PushModelStatus(dialog)
            self.Na__UserInterface__PushProjectStatus(dialog)                      # <-- Folder list and GLB counts may have moved on disk
            self.Na__UserInterface__PushReport(dialog, self.Na__UserInterface__BuildIdleReport)
            self.Na__UserInterface__PushStatus(dialog, 'Model and project folders rescanned.', 'success')
        end
        # ---------------------------------------------------------------

        # ACTION HANDLER | Create The Standardised Tags From The Shared Index
        # ---------------------------------------------------------------
        def self.Na__UserInterface__ActionCreateTags(dialog)
            self.Na__UserInterface__PushStatus(dialog, 'Creating standardised tags...', 'info')

            self.Na__PublicApi__CreateStandardisedTags

            self.Na__UserInterface__PushModelStatus(dialog)                        # <-- Manifest reflects the new tags
            self.Na__UserInterface__PushStatus(dialog, 'Standardised tags created. Manifest rescanned.', 'success')
        end
        # ---------------------------------------------------------------

        # ACTION HANDLER | Hot Reload The Plugin Ruby Files
        # ---------------------------------------------------------------
        # The reloader re-opens this dialog itself, so nothing is pushed after it.
        # ---------------------------------------------------------------
        def self.Na__UserInterface__ActionReloadPlugin(dialog)
            self.Na__UserInterface__PushStatus(dialog, 'Reloading plugin scripts...', 'info')
            self.Na__DevTools__ReloadScripts
        end
        # ---------------------------------------------------------------

        # ACTION HANDLER | Toggle Which Files This Model Exports
        # ---------------------------------------------------------------
        # Handles a single row, a whole group, and Enable / Disable All. The
        # choice is written to the model dictionary, so it survives the session.
        # ---------------------------------------------------------------
        def self.Na__UserInterface__ActionSetFileSelection(dialog, params_json)
            model  = Sketchup.active_model
            params = self.Na__UserInterface__ParseParams(params_json)
            scope  = params['scope'].to_s

            result = if scope == 'all'
                if params['selected'] == true
                    self.Na__ExportSelection__SelectAll(model)
                else
                    status = self.Na__UserInterface__BuildModelStatus
                    names  = Array(status[:groups]).flat_map { |g| Array(g[:rows]).map { |r| r[:name] } }
                    self.Na__ExportSelection__SetManySelected(model, names, false)
                end
            else
                self.Na__ExportSelection__SetManySelected(model, Array(params['fileNames']), params['selected'] == true)
            end

            self.Na__UserInterface__PushModelStatus(dialog)

            unless result[:success]
                self.Na__UserInterface__PushStatus(dialog, result[:message], 'error')
                return
            end

            count = result[:deselected_count].to_i
            self.Na__UserInterface__PushStatus(
                dialog,
                count.zero? ? 'Every file is selected for export.' : "#{count} file(s) toggled off for this model.",
                'info'
            )
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Parse A JSON Params String Into A Hash
        # ---------------------------------------------------------------
        # Always answers a Hash, so action handlers never nil-check the payload.
        # ---------------------------------------------------------------
        def self.Na__UserInterface__ParseParams(params_json)
            return {} if params_json.nil? || params_json.to_s.empty?

            parsed = JSON.parse(params_json.to_s)
            parsed.is_a?(Hash) ? parsed : {}
        rescue JSON::ParserError
            {}
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Apply The Export Options Sent From The Dialog
        # ---------------------------------------------------------------
        def self.Na__UserInterface__ApplyExportParams(params_json)
            params = (params_json && !params_json.empty?) ? JSON.parse(params_json) : {}

            @export_selection_only = params['selectionOnly'] == true
            @downscale_textures    = params['downscaleTextures'] == true

            mode_string = params['materialExportMode'] || 'no_materials'
            self.Na__MaterialEngine__SetExportMode(mode_string.to_sym)
        rescue => e
            Na__Log__Warn "Parameter parsing error: #{e.message} - falling back to safe defaults"
            @export_selection_only = false
            @downscale_textures    = false
            self.Na__MaterialEngine__SetExportMode(:no_materials)
        end
        # ---------------------------------------------------------------

    # endregion ===================================================================


    # =============================================================================
    # REGION | Report Building
    # =============================================================================

        # FUNCTION | Build The Report Panel Payload From An Export Summary
        # ---------------------------------------------------------------
        def self.Na__UserInterface__BuildExportReport(summary, export_dir)
            mesh_count     = summary[:mesh_count].to_i
            linework_count = summary[:linework_count].to_i
            linetype_count = summary[:linetype_count].to_i
            total_count    = summary[:total_count].to_i
            succeeded      = summary[:success] == true

            steps = []
            steps << self.Na__UserInterface__BuildReportStep('Mesh Models',      mesh_count,     'mesh GLB')
            steps << self.Na__UserInterface__BuildReportStep('Linework Models',  linework_count, 'linework GLB')
            steps << self.Na__UserInterface__BuildReportStep('Linetype Linework', linetype_count, 'linetype GLB')

            steps << {
                label:   'Output Folder',
                success: succeeded,
                message: export_dir.to_s
            }

            skipped = summary[:skipped_count].to_i
            if skipped > 0
                steps << {
                    label:   'Toggled Off',
                    status:  'skip',
                    message: "#{skipped} file(s) were not written because they are toggled off for this model. " \
                             'Any existing copies were left untouched.'
                }
            end

            log_path = summary[:log_path]
            if log_path && !log_path.to_s.empty?
                steps << { label: 'Export Log', success: true, message: File.basename(log_path.to_s) }
            else
                steps << { label: 'Export Log', status: 'skip', message: 'Log file writing is disabled.' }
            end

            message = if succeeded
                "#{total_count} GLB file(s) exported" \
                " - #{mesh_count} mesh, #{linework_count} linework, #{linetype_count} linetype."
            else
                summary[:message].to_s.empty? ? 'Export failed.' : summary[:message].to_s
            end

            { success: succeeded, running: false, message: message, steps: steps }
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Build A Single Count-Based Report Step
        # ---------------------------------------------------------------
        # A zero count is a SKIP rather than an error: a model with no linetype
        # tags is a normal model, not a failed export.
        # ---------------------------------------------------------------
        def self.Na__UserInterface__BuildReportStep(label, count, noun)
            if count > 0
                { label: label, success: true, message: "#{count} #{noun} file(s) written." }
            else
                { label: label, status: 'skip', message: 'None in this model.' }
            end
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Build An Empty Report That Hides The Panel
        # ---------------------------------------------------------------
        def self.Na__UserInterface__BuildIdleReport
            { success: nil, running: false, message: '', steps: [] }
        end
        # ---------------------------------------------------------------

    # endregion ===================================================================


    # =============================================================================
    # REGION | Model Status and Export Manifest
    # =============================================================================

        # FUNCTION | Build The Model Status And Export Manifest Payload
        # ---------------------------------------------------------------
        # Mirrors the export planning that Na__ExportCore__PerformExport does, so
        # the manifest the user reads is the file set the exporter will write.
        # ---------------------------------------------------------------
        def self.Na__UserInterface__BuildModelStatus
            model = Sketchup.active_model
            return self.Na__UserInterface__EmptyModelStatus unless model

            self.Na__ExportCore__IdentifyExcludedLayers(model)                     # <-- Keep @excluded_layers current for a rescan

            project_prefix      = self.Na__Helpers__ExtractProjectPrefix(model)
            site_plan_tag_count = model.layers.count { |layer| layer.name =~ SITE_PLAN_TAG_PATTERN }
            tag_groups          = self.Na__ExportCore__OrganizeEntitiesByTags(model)
            linetype_plan       = self.Na__ExportCore__PlanLinetypeLinework(model, project_prefix)
            storey_containers   = self.Na__ExportCore__DetectStoreyContainers(model)
            has_storeys         = storey_containers.any?

            # Storey entities are exported per-element, so lift them out of the flat groups
            if has_storeys
                storey_containers.each do |_storey_name, storey_entities|
                    Array(storey_entities).each do |storey_entity|
                        tag_groups.each { |_, entities| entities.delete(storey_entity) }
                    end
                end
                tag_groups.delete_if { |_, entities| entities.length == 0 }
            end

            deselected  = self.Na__ExportSelection__DeselectedSet(model)
            groups      = []
            total_files = 0

            flat_rows, flat_files = self.Na__UserInterface__BuildFlatGroupRows(tag_groups, project_prefix, deselected)
            if flat_rows.any?
                groups      << { rows: flat_rows }                                 # <-- No label: renders as bare rows
                total_files += flat_files
            end

            if has_storeys
                storey_containers.each do |storey_name, storey_entities|
                    element_groups = self.Na__ExportCore__OrganizeStoreyChildrenByTags(storey_entities, storey_name)
                    storey_rows, storey_files = self.Na__UserInterface__BuildStoreyGroupRows(
                        element_groups, storey_name, project_prefix, deselected
                    )
                    next if storey_rows.empty?

                    groups << {
                        icon:        "\u{1F3E2}",                                   # <-- Office building glyph
                        label:       self.Na__UserInterface__FormatStoreyLabel(storey_name),
                        count_label: "#{storey_files} files",
                        rows:        storey_rows
                    }
                    total_files += storey_files
                end
            end

            if linetype_plan.any?
                linetype_rows = linetype_plan.map do |row|
                    name = row[:filename].to_s
                    {
                        name:     name,
                        meta:     "#{row[:edge_count]} edges · #{row[:line_type]}",
                        selected: !deselected[name]
                    }
                end
                groups << {
                    icon:        "□",                                          # <-- Hollow square glyph
                    label:       'Linetype Linework',
                    count_label: "#{linetype_plan.length} files",
                    rows:        linetype_rows
                }
                total_files += linetype_plan.length
            end

            # Forget toggles for files this model no longer produces, so a renamed
            # tag cannot leave an invisible "off" behind.
            all_file_names = groups.flat_map { |group| Array(group[:rows]).map { |row| row[:name] } }
            self.Na__ExportSelection__PruneToKnown(model, all_file_names)

            selected_files   = groups.sum { |group| Array(group[:rows]).count { |row| row[:selected] } }
            can_export_model = selected_files > 0

            {
                model_name:             self.Na__UserInterface__ModelDisplayName(model),
                project_prefix:         project_prefix.to_s.empty? ? '(none)' : project_prefix.to_s,
                storey_count:           storey_containers.length,
                storey_container_count: storey_containers.values.map { |entities| Array(entities).length }.sum,
                site_plan_tag_count:    site_plan_tag_count,
                excluded_tag_count:     Array(@excluded_layers).length,
                linetype_tag_count:     linetype_plan.length,
                verbose_logging:        self.Na__ExportConfig__LoggingConsoleVerbose,
                log_file_enabled:       self.Na__ExportConfig__LoggingTextFileEnabled,
                total_file_count:       total_files,
                selected_file_count:    selected_files,
                can_export_model:       can_export_model,
                can_export_site_plan:   site_plan_tag_count > 0,
                notes:                  self.Na__UserInterface__BuildManifestNotes(
                                            has_storeys:         has_storeys,
                                            storey_containers:   storey_containers,
                                            site_plan_tag_count: site_plan_tag_count,
                                            linetype_plan:       linetype_plan,
                                            can_export_model:    can_export_model,
                                            total_files:         total_files
                                        ),
                groups:                 groups
            }
        rescue => e
            Na__Log__Warn "ERROR building GLB Builder model status: #{e.message}"
            Na__Log__Warn e.backtrace.first(5).join("\n")
            self.Na__UserInterface__EmptyModelStatus("#{e.class}: #{e.message}")
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Build The Flat (Non-Storey) Manifest Rows
        # ---------------------------------------------------------------
        # Returns [rows, file_count]. The orbit helper cube is mesh-only, so it
        # contributes one file where every other group contributes two.
        # ---------------------------------------------------------------
        def self.Na__UserInterface__BuildFlatGroupRows(tag_groups, project_prefix, deselected = {})
            rows       = []
            file_count = 0

            tag_groups.each do |base_filename, entities|
                entity_count = entities.length
                rows << self.Na__UserInterface__BuildFileRow(
                    "#{project_prefix}#{base_filename}#{MESH_MODEL_SUFFIX}.glb", entity_count, deselected
                )
                file_count += 1

                next if base_filename == '01__OrbitHelperCube'

                rows << self.Na__UserInterface__BuildFileRow(
                    "#{project_prefix}#{base_filename}#{LINEWORK_MODEL_SUFFIX}.glb", entity_count, deselected
                )
                file_count += 1
            end

            [rows, file_count]
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Build The Manifest Rows For One Storey
        # ---------------------------------------------------------------
        # Returns [rows, file_count]. Every storey element writes a mesh and a
        # linework GLB.
        # ---------------------------------------------------------------
        def self.Na__UserInterface__BuildStoreyGroupRows(element_groups, storey_name, project_prefix, deselected = {})
            rows       = []
            file_count = 0

            element_groups.each do |element_name, entities|
                base_filename = "#{storey_name}__#{element_name}"
                entity_count  = entities.length

                rows << self.Na__UserInterface__BuildFileRow(
                    "#{project_prefix}#{base_filename}#{MESH_MODEL_SUFFIX}.glb", entity_count, deselected
                )
                rows << self.Na__UserInterface__BuildFileRow(
                    "#{project_prefix}#{base_filename}#{LINEWORK_MODEL_SUFFIX}.glb", entity_count, deselected
                )
                file_count += 2
            end

            [rows, file_count]
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Build A Single File Manifest Row
        # ---------------------------------------------------------------
        # `selected` drives the row's toggle. The deselected set is passed in so
        # the whole manifest is built against one read of the dictionary.
        # ---------------------------------------------------------------
        def self.Na__UserInterface__BuildFileRow(file_name, entity_count, deselected = {})
            name = file_name.to_s
            { name: name, meta: "#{entity_count} entities", selected: !deselected[name] }
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Build The Advisory Notes Shown Above The Manifest
        # ---------------------------------------------------------------
        def self.Na__UserInterface__BuildManifestNotes(has_storeys:, storey_containers:,
                                                        site_plan_tag_count:, linetype_plan:,
                                                        can_export_model:, total_files: 0)
            notes = []

            if has_storeys
                container_total = storey_containers.values.map { |entities| Array(entities).length }.sum
                notes << {
                    variant: 'storey',
                    title:   'Storey Mode Active:',
                    text:    "#{storey_containers.length} storey key(s), #{container_total} container(s) detected. " \
                             'Duplicate storey containers are merged per-storey.'
                }
            end

            if site_plan_tag_count > 0
                notes << {
                    variant: 'siteplan',
                    title:   "#{site_plan_tag_count} site plan tag(s)",
                    text:    '(71-75) in this model. They never go into model GLBs: use Export Site Plan Data.'
                }
            end

            if linetype_plan.any?
                linetype_tags = linetype_plan.map { |row| row[:tag_name] }.join(', ')
                notes << {
                    variant: 'siteplan',
                    title:   "#{linetype_plan.length} linetype tag(s)",
                    text:    "hold linework: #{linetype_tags}. Each exports as its own LineworkModel GLB for the " \
                             'drawing editors; none of it reaches a mesh GLB.'
                }
            end

            excluded_count = Array(@excluded_layers).length
            if excluded_count > 0
                notes << {
                    variant: 'excluded',
                    title:   "#{excluded_count} tag(s)",
                    text:    "left out of model GLBs (reference, helper and site plan tags, and '#{EXCLUDED_LAYER_DESCRIPTION}')."
                }
            end

            # Everything switched off is a different problem from nothing to find
            if !can_export_model && total_files > 0
                notes << {
                    variant: 'excluded',
                    title:   'Every file is toggled off.',
                    text:    'Use Enable All, or tick the files you want, before exporting.'
                }
            elsif !can_export_model
                notes << if site_plan_tag_count > 0
                    {
                        variant: 'empty',
                        title:   '',
                        text:    'No model layers to export. This model holds site plan tags: use Export Site Plan Data.'
                    }
                else
                    {
                        variant: 'empty',
                        title:   '',
                        text:    'No entities found with valid tag ranges.'
                    }
                end
            end

            notes
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Humanise A Storey Container Tag Name
        # ---------------------------------------------------------------
        def self.Na__UserInterface__FormatStoreyLabel(storey_name)
            storey_name.to_s.gsub('Storey__', '').gsub(/([a-z])([A-Z])/, '\1 \2')
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Resolve A Display Name For The Active Model
        # ---------------------------------------------------------------
        def self.Na__UserInterface__ModelDisplayName(model)
            path = model.path.to_s
            return '(Unsaved model)' if path.empty?

            File.basename(path, '.skp')
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Status Payload For A Session With No Usable Model
        # ---------------------------------------------------------------
        def self.Na__UserInterface__EmptyModelStatus(error_text = nil)
            notes = []
            notes << { variant: 'empty', title: 'Scan failed:', text: error_text } if error_text

            {
                model_name:             '(No active model)',
                project_prefix:         '(none)',
                storey_count:           0,
                storey_container_count: 0,
                site_plan_tag_count:    0,
                excluded_tag_count:     0,
                linetype_tag_count:     0,
                verbose_logging:        false,
                log_file_enabled:       false,
                total_file_count:       0,
                selected_file_count:    0,
                can_export_model:       false,
                can_export_site_plan:   false,
                notes:                  notes,
                groups:                 []
            }
        end
        # ---------------------------------------------------------------

    # endregion ===================================================================


    # =============================================================================
    # REGION | JS Push - Status, Report, and Model Status
    # =============================================================================

        # FUNCTION | Push The Footer Status Line To The Dialog
        # ---------------------------------------------------------------
        def self.Na__UserInterface__PushStatus(dialog, status_text, status_variant = 'info')
            return unless dialog

            script = <<~SCRIPT
            (function() {
                var el = document.getElementById('naTvgbStatus');
                if (!el) { return; }
                el.textContent = #{status_text.to_s.to_json};
                el.className   = 'naTvgb__Status naTvgb__Status--' + #{status_variant.to_s.to_json};
            })();
            SCRIPT
            dialog.execute_script(script)
        rescue => e
            Na__Log__Warn "[GlbBuilder] Could not push status to dialog: #{e.message}"
        end
        # ---------------------------------------------------------------

        # FUNCTION | Push The Report Panel Payload To The Dialog
        # ---------------------------------------------------------------
        def self.Na__UserInterface__PushReport(dialog, report_hash)
            return unless dialog

            dialog.execute_script(
                "window.Na__Tvgb__ReceiveReport && window.Na__Tvgb__ReceiveReport(#{report_hash.to_json});"
            )
        rescue => e
            Na__Log__Warn "[GlbBuilder] Could not push report to dialog: #{e.message}"
        end
        # ---------------------------------------------------------------

        # FUNCTION | Push The Model Status And Manifest To The Dialog
        # ---------------------------------------------------------------
        def self.Na__UserInterface__PushModelStatus(dialog)
            return unless dialog

            status_json = self.Na__UserInterface__BuildModelStatus.to_json
            dialog.execute_script(
                "window.Na__Tvgb__ReceiveModelStatus && window.Na__Tvgb__ReceiveModelStatus(#{status_json});"
            )
        rescue => e
            Na__Log__Warn "[GlbBuilder] Could not push model status to dialog: #{e.message}"
        end
        # ---------------------------------------------------------------

    # endregion ===================================================================

    end  # module GlbBuilderUtility
end  # module TrueVision3D

# =============================================================================
# END OF FILE
# =============================================================================
