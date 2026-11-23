# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - ASSEMBLY RUN SYSTEM - DIALOG ROUTER
# =============================================================================
#
# FILE       : Na__AssemblyStudio__AssemblyRun__DialogRouter__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__AssemblyRunSystem
# MODULE     : Na__DialogRouter
# AUTHOR     : Noble Architecture
# PURPOSE    : Receives the Assembly Run Studio tab's callbacks and runs its
#              flows: resolve a layout for the preview, measure a path,
#              create, update, the panel edits (make unique, recode, change
#              type), Edit Path, and the selection load / clear. Also tells
#              the dialog when the element selected in the model is a span
#              of a run ("editing panel type A").
# CREATED    : 16-Nov-2026 (V2.7.0)
#
# IT BUILDS NOTHING ITSELF
# - Every create, rebuild and edit goes through Na__RunPipelines, the same
#   calls the agent seam makes. This file keeps only what is the dialog's:
#   which run it is showing, the measured path waiting to be used, the
#   selection, and the status line.
#
# CALLBACKS (JS -> Ruby)
#   na_runRequestBootstrap()        na_runResolve(json)
#   na_runMeasurePath(json)         na_runClearMeasuredPath()
#   na_runCreate(json)              na_runUpdate(json)
#   na_runRename(json)              na_runMakeUnique(json)
#   na_runRecode(json)              na_runSetSpanType(json)
#   na_runSelectMember(json)        na_runSelectRun(json)
#   na_runEditPath()                na_runFinishPathEdit()
#   na_runDiscardPathEdit()         na_runJsLog(message)
#   na_runSetPreviewPanel(json)     (V2.7.1: widen / narrow the dialog for
#                                    the flipped-out preview)
#   na_runStageEdit(json)           (V2.7.2: change the page's description
#                                    by a named edit; nothing is built)
#   na_runSetSpanProduct(json)      na_runSetTypeProduct(json)
#                                   (V2.7.2: another product, built at once;
#                                    the member banner's commands)
#   na_runLiveUpdate(json)          (V2.7.7: Live Mode, the page's description
#                                    rebuilt at once; always answered)
#
# RUBY -> JS
#   window.na_receiveRunBootstrap(json)   window.na_receiveRunLayout(json)
#   window.na_setInitialRunConfig(json)   window.na_clearCurrentRun()
#   window.na_receiveRunPath(json)        window.na_runMeasureCancelled()
#   window.na_setRunMember(json)          window.na_clearRunMember()
#   window.na_setRunPathEdit(json)        window.na_receiveRunStaged(json)
#   window.na_receiveRunLive(json)        (V2.7.7)
#
# WHY A RUN IS SENT (V2.7.7): na_setInitialRunConfig carries a reason,
# "selected", "built" or "renamed". The page keeps its staged changes on
# anything but "built" (Adam, 23-Nov-2026: "as you make changes, they get
# lost before you press the update button": every selection of the run
# replaced them with what it stored).
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix.
#
# =============================================================================

require 'sketchup.rb'
require 'json'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__DebugTools__'
require_relative '../01__AppCore/Na__AssemblyStudio__AppCore__UiBridge__'
require_relative '../06__Tools__MeasurementTools/Na__AssemblyStudio__MeasurementTools__RunPathMeasureTool__'
require_relative 'Na__AssemblyStudio__AssemblyRun__Defaults__'
require_relative 'Na__AssemblyStudio__AssemblyRun__PathMath__'
require_relative 'Na__AssemblyStudio__AssemblyRun__LayoutResolver__'
require_relative 'Na__AssemblyStudio__AssemblyRun__DataSerializer__'
require_relative 'Na__AssemblyStudio__AssemblyRun__ColumnLibrary__'
require_relative 'Na__AssemblyStudio__AssemblyRun__RunPipelines__'
require_relative 'Na__AssemblyStudio__AssemblyRun__PathEditor__'
require_relative 'Na__AssemblyStudio__AssemblyRun__MemberSync__'

module Na__AssemblyStudio
module Na__AssemblyRunSystem
    module Na__DialogRouter

# -----------------------------------------------------------------------------
# REGION | Module References
# -----------------------------------------------------------------------------

        DebugTools      = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools
        UiBridge        = Na__AssemblyStudio::Na__AppCore::Na__UiBridge
        PathMeasureTool = Na__AssemblyStudio::Na__MeasurementTools::Na__RunPathMeasureTool
        Defaults        = Na__AssemblyStudio::Na__AssemblyRunSystem::Na__Defaults
        PathMath        = Na__AssemblyStudio::Na__AssemblyRunSystem::Na__PathMath
        RunCills        = Na__AssemblyStudio::Na__AssemblyRunSystem::Na__RunCills
        LayoutResolver  = Na__AssemblyStudio::Na__AssemblyRunSystem::Na__LayoutResolver
        DataSerializer  = Na__AssemblyStudio::Na__AssemblyRunSystem::Na__DataSerializer
        ColumnLibrary   = Na__AssemblyStudio::Na__AssemblyRunSystem::Na__ColumnLibrary
        RunPipelines    = Na__AssemblyStudio::Na__AssemblyRunSystem::Na__RunPipelines
        RunEdits        = Na__AssemblyStudio::Na__AssemblyRunSystem::Na__RunEdits
        PathEditor      = Na__AssemblyStudio::Na__AssemblyRunSystem::Na__PathEditor
        MemberSync      = Na__AssemblyStudio::Na__AssemblyRunSystem::Na__MemberSync

        NA_SIDE_LABELS = {
            Defaults::NA_MODE_FRAMES   => "the OUTSIDE of the framework",
            Defaults::NA_MODE_CABINETS => "the ROOM side the units face"
        }.freeze

        # The flipped-out preview (V2.7.1): the dialog's width before it was
        # widened, kept in SketchUp's own preferences so it is still known
        # after the dialog, or SketchUp, was closed while flipped out.
        NA_PREFS_SECTION         = "Na__AssemblyStudio".freeze
        NA_PREFS_PANEL_WIDTH     = "AssemblyRun__PreviewPanel__WidthBefore".freeze
        NA_PANEL_RESTORE_DELAY_S = 0.6                                           # <-- A new dialog is given this long to show before it is narrowed

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Module Variables
# -----------------------------------------------------------------------------

        @na_current_instance = nil      # <-- The run last created, loaded or updated
        @na_pending_path     = nil      # <-- { :transform, :points, :closed } a measured path waiting for Create

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API - Initialisation
# -----------------------------------------------------------------------------

        # FUNCTION | Register Every Callback on the Shared Dialog
        # ------------------------------------------------------------
        def self.na_init(dialog)
            UiBridge.na_register_callbacks(dialog, na_callback_registry)
            PathEditor.na_on_finished { |result| na_path_edit_finished(result) }
            MemberSync.na_on_refit { |result| na_member_refitted(result) }
            na_restore_width_after_open(dialog)
            DebugTools.na_debug_ui("Assembly Run callbacks registered")
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Callback Name -> Handler
        # ------------------------------------------------------------
        def self.na_callback_registry
            {
                "na_runRequestBootstrap"  => proc { na_send_bootstrap },
                "na_runResolve"           => proc { |json| na_send_layout(json) },
                "na_runMeasurePath"       => proc { |json| na_start_path_measure(json) },
                "na_runClearMeasuredPath" => proc { na_clear_measured_path },
                "na_runCreate"            => proc { |json| na_create(json) },
                "na_runUpdate"            => proc { |json| na_update(json) },
                "na_runLiveUpdate"        => proc { |json| na_live_update(json) },        # <-- V2.7.7 Live Mode
                "na_runRename"            => proc { |json| na_rename(json) },
                "na_runMakeUnique"        => proc { |json| na_panel_edit(json, :unique) },
                "na_runRecode"            => proc { |json| na_panel_edit(json, :recode) },
                "na_runSetSpanType"       => proc { |json| na_panel_edit(json, :set_type) },
                "na_runSetSpanProduct"    => proc { |json| na_panel_edit(json, :span_product) },
                "na_runSetTypeProduct"    => proc { |json| na_panel_edit(json, :type_product) },
                "na_runStageEdit"         => proc { |json| na_stage_edit(json) },
                "na_runSelectMember"      => proc { |json| na_select_member(json) },
                "na_runSelectRun"         => proc { |json| na_select_run(json) },
                "na_runEditPath"          => proc { na_edit_path },
                "na_runFinishPathEdit"    => proc { PathEditor.na_finish },
                "na_runDiscardPathEdit"   => proc { PathEditor.na_discard },
                "na_runSetPreviewPanel"   => proc { |json| na_set_preview_panel(json) },
                "na_runJsLog"             => proc { |message|
                    @na_last_js_message = message.to_s
                    DebugTools.na_debug_ui("[JS:Run] #{message}")
                }
            }
        end
        private_class_method :na_callback_registry
        # ---------------------------------------------------------------

        # FUNCTION | The Last Message the Page Logged (for Tests Driving the Real Dialog)
        # ------------------------------------------------------------
        # A test runs a script in the page that ends in sketchup.na_runJsLog
        # with what it found, then reads it here: the one way to get an
        # answer back out of an HtmlDialog without adding a callback, which
        # a page already loaded would not see.
        def self.na_last_js_message
            @na_last_js_message
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Bootstrap and Layout (Nothing in the Model Changes)
# -----------------------------------------------------------------------------

        # FUNCTION | Everything the Tab Needs to Draw Itself
        # ------------------------------------------------------------
        # The defaults, the option lists and the limits all come from Ruby,
        # so the page holds no second copy of them.
        def self.na_send_bootstrap
            UiBridge.na_execute_json_function(na_dialog, "window.na_receiveRunBootstrap", na_bootstrap_payload)
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Bootstrap Payload (Also Read by the Offline Page Test)
        # ------------------------------------------------------------
        def self.na_bootstrap_payload
            {
                "defaults"       => Defaults::NA_MODES.each_with_object({}) { |mode, all| all[mode] = Defaults.na_default_config(mode) },
                "modes"          => Defaults::NA_MODES,
                "products"       => Defaults::NA_MODE_PRODUCTS,
                "productLabels"  => Defaults::NA_PRODUCT_LABELS,
                "columnKinds"    => Defaults::NA_COLUMN_KINDS_BY_MODE,
                "cornerKinds"    => Defaults::NA_CORNER_KINDS_BY_MODE,
                "infillModes"    => Defaults::NA_INFILL_MODES,
                "limits"         => Defaults::NA_LIMITS,
                "minimums"       => { "leg" => Defaults::NA_MIN_LEG_MM, "span" => Defaults::NA_MIN_SPAN_MM },
                "libraryColumns" => ColumnLibrary.na_list,
                "presets"        => na_preset_rows,
                "productWidths"  => na_product_widths,
                "keys"           => { "metadata" => Defaults::NA_KEY_METADATA, "components" => Defaults::NA_KEY_COMPONENTS,
                                      "configuration" => Defaults::NA_KEY_CONFIGURATION, "prefix" => Defaults::NA_CONFIG_KEY_PREFIX,
                                      "draftPath" => Defaults::NA_KEY_DRAFT_PATH, "draftPathPage" => Defaults::NA_DRAFT_PATH_PAGE,
                                      "liveSeq" => Defaults::NA_KEY_LIVE_SEQ },
                "sillProducts"   => Defaults::NA_SILL_PRODUCTS,
                "pathEdit"       => PathEditor.na_editing_run_id
            }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Resolve the Page's Configuration and Send the Layout Back
        # ------------------------------------------------------------
        def self.na_send_layout(config_json)
            root = na_parse(config_json)
            return unless root
            UiBridge.na_execute_json_function(na_dialog, "window.na_receiveRunLayout", na_layout_payload(root))
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Root's Layout as the Page Draws It
        # ------------------------------------------------------------
        # @return [Hash] { "layout" => the resolver's report, "ok" => no errors }
        def self.na_layout_payload(root)
            layout = RunPipelines.na_layout(root)
            { "layout" => na_preview_report(layout), "ok" => layout[:errors].empty? }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Stage One Named Edit on the Page's Description (V2.7.2)
        # ------------------------------------------------------------
        # Another product for a span, a leg's fill or a panel type; the
        # inside-out flip. The page sends its description, Na__RunEdits
        # changes it, and it goes back with its layout. Nothing in the
        # model changes: Update Run (or Create) builds it.
        # @param payload_json { root, edit, leg, span (zero-based), code, product }
        def self.na_stage_edit(payload_json)
            payload = na_parse(payload_json)
            return unless payload
            UiBridge.na_execute_json_function(na_dialog, "window.na_receiveRunStaged", na_staged_payload(payload))
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Staged Edit's Answer
        # ------------------------------------------------------------
        # @return [Hash] { "ok" => true, "edit", "root", "layout", "message" }
        #     or { "ok" => false, "edit", "message" } when the edit is refused
        def self.na_staged_payload(payload)
            edit = payload["edit"].to_s
            root = payload["root"]
            return { "ok" => false, "edit" => edit, "message" => "The run's settings could not be read." } unless root.is_a?(Hash)

            message = RunEdits.na_stage!(RunPipelines.na_config(root), RunPipelines.na_layout(root), edit, payload)
            { "ok" => true, "edit" => edit, "root" => root, "layout" => na_layout_payload(root)["layout"], "message" => message }
        rescue ArgumentError => e
            { "ok" => false, "edit" => edit, "message" => e.message }
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | The Layout Report, With Cabinet Heights for the Elevation
        # ------------------------------------------------------------
        # A frame span carries its own height. A cabinet's height is its
        # product's, which the resolver does not know: each cabinet type is
        # given the height its product starts at (preview_z0 / preview_z1),
        # so the elevation draws a wall unit hung and a wardrobe tall.
        def self.na_preview_report(layout)
            report = LayoutResolver.na_report(layout)
            return report unless layout[:mode] == Defaults::NA_MODE_CABINETS
            report["types"].each_value do |type|
                heights = na_product_heights(type["product"])
                next unless heights
                type["preview_z0"], type["preview_z1"] = heights
            end
            na_preview_worktops!(report, layout)
            report
        end
        private_class_method :na_preview_report
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Each Worktop's Plan Outline and Height for the Preview (V2.7.4)
        # ------------------------------------------------------------
        # The build sizes a worktop from the units' own settings. The preview
        # takes them from the first unit type's product start, as it takes
        # the units' heights: preview_z0 / preview_z1, preview_front (mm
        # from the path to the front edge) and the outline in plan.
        def self.na_preview_worktops!(report, layout)
            v = layout[:settings]
            Array(layout[:worktops]).each_with_index do |stretch, index|
                row  = Array(report["worktops"])[index]
                type = layout[:types][stretch[:types].first] || {}
                unit = na_product_worktop_base(type[:product])
                next unless row && unit
                front   = unit[:front] + v[:worktop_overhang].to_f
                outline = RunCills.na_band_outline(stretch[:centreline], -front, v[:worktop_back].to_f, stretch[:closed])
                rounded = lambda { |loop_points| loop_points && loop_points.map { |point| point.map { |value| value.round(2) } } }
                row["outline"]       = { "outer" => rounded.call(outline[:outer]), "inner" => rounded.call(outline[:inner]) }
                row["preview_front"] = front.round(2)
                row["preview_z0"]    = unit[:top].round(2)
                row["preview_z1"]    = (unit[:top] + v[:worktop_thickness].to_f).round(2)
            end
        end
        private_class_method :na_preview_worktops!
        # ---------------------------------------------------------------

        # HELPER FUNCTION | A Cabinet Product's Top and Front, From Its Start (V2.7.4)
        # ------------------------------------------------------------
        # @return [Hash, nil] { :top (plinth and carcass), :front (carcass and door) } mm
        def self.na_product_worktop_base(product)
            @na_product_worktop_base ||= {}
            return @na_product_worktop_base[product] if @na_product_worktop_base.key?(product)
            values = Na__AssemblyStudio::Na__McpOperations.na_fresh_root(product)["Na__CabinetConfiguration"] || {}
            unit   = Na__AssemblyStudio::Na__InteriorCabinetrySystem::Na__LayoutResolver.na_effective(values)
            @na_product_worktop_base[product] = { :top   => unit[:z_base] + unit[:height],
                                                  :front => unit[:depth] + (unit[:layout] == "Open" ? 0.0 : unit[:front_standoff].to_f + unit[:front_thickness]) }
        rescue StandardError => e
            DebugTools.na_debug_warn("Run preview worktop for '#{product}' unavailable: #{e.message}")
            @na_product_worktop_base[product] = nil
        end
        private_class_method :na_product_worktop_base
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Where a Cabinet Product Starts and Stops, Above the Floor
        # ------------------------------------------------------------
        # From the product's own starting values, read once per product.
        def self.na_product_heights(product)
            @na_product_heights ||= {}
            return @na_product_heights[product] if @na_product_heights.key?(product)
            values    = Na__AssemblyStudio::Na__McpOperations.na_fresh_root(product)["Na__CabinetConfiguration"] || {}
            effective = Na__AssemblyStudio::Na__InteriorCabinetrySystem::Na__LayoutResolver.na_effective(values)
            bottom    = effective[:type] == "Wall" ? effective[:z_base] : 0.0
            @na_product_heights[product] = [bottom, effective[:z_base] + effective[:height]]
        rescue StandardError => e
            DebugTools.na_debug_warn("Run preview height for '#{product}' unavailable: #{e.message}")
            @na_product_heights[product] = nil
        end
        private_class_method :na_product_heights
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Each Frame Product's Own Starting Width
        # ------------------------------------------------------------
        # Read once from the product's starting values (never a second
        # table here). The page divides a measured leg by it to give the
        # leg a first count of spans; the user then changes the count.
        def self.na_product_widths
            return @na_product_widths if @na_product_widths
            block  = Na__AssemblyStudio::Na__AssemblyRunSystem::Na__PanelTypes::NA_CONFIG_BLOCKS[Defaults::NA_MODE_SYSTEMS[Defaults::NA_MODE_FRAMES]]
            widths = Defaults::NA_MODE_PRODUCTS[Defaults::NA_MODE_FRAMES].each_with_object({}) do |product, found|
                width = (Na__AssemblyStudio::Na__McpOperations.na_fresh_root(product)[block] || {})["width_mm"].to_f
                found[product] = width if width > 0
            end
            @na_product_widths = widths
        rescue StandardError => e
            DebugTools.na_debug_warn("Run product widths unavailable: #{e.message}")
            {}
        end
        private_class_method :na_product_widths
        # ---------------------------------------------------------------

        # HELPER FUNCTION | The Presets a Panel Type Can Start From
        # ------------------------------------------------------------
        def self.na_preset_rows
            listed = Na__AssemblyStudio::Na__McpOperations.Na__AssemblyStudio__McpRead("list_presets", {})
            Array(listed["presets"]).map { |row| { "code" => row["code"], "name" => row["name"], "product" => row["type"] } }
        rescue StandardError => e
            DebugTools.na_debug_warn("Run presets unavailable: #{e.message}")
            []
        end
        private_class_method :na_preset_rows
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | The Flipped-Out Preview (the Dialog Is Widened to Make Room)
# -----------------------------------------------------------------------------

        # FUNCTION | Widen the Dialog for the Flipped-Out Preview, or Narrow It Again
        # ------------------------------------------------------------
        # The page lays the preview out in a panel to the right of its
        # controls and asks for the room. It measures in page pixels and the
        # dialog is sized in its own (logical) pixels, so the page sends the
        # dialog's width as IT sees it and the extra is scaled by the two.
        # @param payload_json { open: true, extra, outer } | { open: false }
        def self.na_set_preview_panel(payload_json)
            payload = na_parse(payload_json) || {}
            dialog  = na_dialog
            size    = (dialog && dialog.respond_to?(:get_size)) ? dialog.get_size : nil
            return unless size                                                   # <-- nil while the dialog is not showing
            width, height = size
            before = na_panel_width_before

            if payload["open"] == true
                outer = payload["outer"].to_f
                scale = outer > 0 ? width.to_f / outer : 1.0
                base  = before > 0 ? before : width                              # <-- Already wide (the page was reloaded): never grow twice
                Sketchup.write_default(NA_PREFS_SECTION, NA_PREFS_PANEL_WIDTH, base)
                dialog.set_size((base + payload["extra"].to_f * scale).round, height)
            else
                dialog.set_size(before, height) if before > 0
                Sketchup.write_default(NA_PREFS_SECTION, NA_PREFS_PANEL_WIDTH, 0)
            end
        rescue StandardError => e
            DebugTools.na_debug_warn("Run preview panel: the dialog could not be resized: #{e.message}")
        end
        # ---------------------------------------------------------------

        # SUB FUNCTION | A Dialog Closed While Flipped Out Comes Back Wide: Narrow It
        # ------------------------------------------------------------
        # The dialog remembers its own size between opens, but its page
        # always opens with the preview back in the column. Once the new
        # dialog is showing, the width it had before the flip-out is put back.
        def self.na_restore_width_after_open(dialog)
            before = na_panel_width_before
            return unless before > 0
            UI.start_timer(NA_PANEL_RESTORE_DELAY_S, false) do
                begin
                    size = dialog.visible? ? dialog.get_size : nil
                    dialog.set_size(before, size[1]) if size && size[0] > before
                    Sketchup.write_default(NA_PREFS_SECTION, NA_PREFS_PANEL_WIDTH, 0)
                rescue StandardError => e
                    DebugTools.na_debug_warn("Run preview panel: the dialog's width could not be put back: #{e.message}")
                end
            end
        end
        private_class_method :na_restore_width_after_open
        # ---------------------------------------------------------------

        # HELPER FUNCTION | The Dialog's Width Before the Preview Was Flipped Out (0 = Not Flipped)
        # ------------------------------------------------------------
        def self.na_panel_width_before
            Sketchup.read_default(NA_PREFS_SECTION, NA_PREFS_PANEL_WIDTH, 0).to_i
        end
        private_class_method :na_panel_width_before
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Measured Path
# -----------------------------------------------------------------------------

        # FUNCTION | Start Picking a Path in the Model
        # ------------------------------------------------------------
        def self.na_start_path_measure(payload_json)
            mode = (na_parse(payload_json) || {})["mode"].to_s
            mode = Defaults::NA_MODE_FRAMES unless Defaults::NA_MODES.include?(mode)
            Sketchup.active_model.select_tool(PathMeasureTool.new(self, side_label: NA_SIDE_LABELS[mode]))
        end
        # ---------------------------------------------------------------

        # FUNCTION | Path Measure Tool Host: the Path Was Picked
        # ------------------------------------------------------------
        # @param points [Array<Geom::Point3d>] world; side_point: world
        def self.na_send_run_path_to_dialog(points, side_point, closed)
            frame = RunPipelines.na_world_path_frame(points, side_point, closed)
            @na_pending_path = frame
            UiBridge.na_execute_json_function(na_dialog, "window.na_receiveRunPath", {
                "active" => true, "points" => frame[:points], "closed" => frame[:closed],
                "legs"   => PathMath.na_leg_rows(frame[:points], frame[:closed]),
                "length" => PathMath.na_legs(frame[:points], frame[:closed]).sum { |leg| leg[:length] }.round(1)
            })
            na_status("success", "Path measured: #{frame[:points].length} points#{closed ? ', closed' : ''}. Create Run builds along it.")
        rescue ArgumentError => e
            na_status("warning", e.message)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Path Measure Tool Host: Measuring Was Cancelled
        # ------------------------------------------------------------
        def self.na_send_run_path_cancelled_to_dialog
            UiBridge.na_invoke(na_dialog, "window.na_runMeasureCancelled")
        end
        # ---------------------------------------------------------------

        # FUNCTION | Forget the Measured Path
        # ------------------------------------------------------------
        def self.na_clear_measured_path
            @na_pending_path = nil
            UiBridge.na_execute_json_function(na_dialog, "window.na_receiveRunPath", { "active" => false })
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Create, Update, Rename
# -----------------------------------------------------------------------------

        # FUNCTION | Build the Page's Run: Along the Measured Path, or at the Origin
        # ------------------------------------------------------------
        def self.na_create(config_json)
            root = na_parse(config_json)
            return unless root
            config    = RunPipelines.na_config(root)
            page_path = root.delete(Defaults::NA_KEY_DRAFT_PATH) == Defaults::NA_DRAFT_PATH_PAGE
            if @na_pending_path
                # The placement is the measurement's. So is the path, unless
                # the draft holds that same path as the tab has since changed
                # it (flipped inside out, a leg retyped): see NA_KEY_DRAFT_PATH.
                unless page_path
                    config[Defaults.na_key("PathPoints")] = @na_pending_path[:points]
                    config[Defaults.na_key("PathClosed")] = @na_pending_path[:closed]
                end
                transform = @na_pending_path[:transform]
            else
                transform = Sketchup.active_model.axes.transformation
            end
            name   = RunPipelines.na_metadata(root)["Na__Run__ComponentName"].to_s
            report = RunPipelines.na_pipeline_create(root, transform, name: name)
            placed = @na_pending_path ? "along the measured path" : "at the model origin (no path was measured): move it into place"
            @na_pending_path = nil
            UiBridge.na_execute_json_function(na_dialog, "window.na_receiveRunPath", { "active" => false })
            na_after_build(report, "#{report[:instance].name} built #{placed}.")
        rescue Na__RunLayoutError => e
            na_refused(root, e)
        rescue StandardError => e
            DebugTools.na_debug_error("Run create failed", e)
            na_status("error", "The run could not be built: #{e.message}")
        end
        # ---------------------------------------------------------------

        # FUNCTION | Rebuild the Run the Page Is Showing
        # ------------------------------------------------------------
        def self.na_update(config_json)
            root = na_parse(config_json)
            return unless root
            root.delete(Defaults::NA_KEY_DRAFT_PATH)                             # <-- A draft's own marker: never part of a run's data
            instance = na_target_run(RunPipelines.na_metadata(root)["Na__Run__UniqueId"])
            unless instance
                na_status("warning", "Select an assembly run to update.")
                return
            end
            requested = RunPipelines.na_metadata(root)["Na__Run__ComponentName"]
            report    = RunPipelines.na_pipeline_update(instance, root, name: requested.nil? ? RunPipelines::NameSuffix::NA_KEEP : requested.to_s)
            na_after_build(report, "#{instance.name} updated.")
        rescue Na__RunLayoutError => e
            na_refused(root, e)
        rescue StandardError => e
            DebugTools.na_debug_error("Run update failed", e)
            na_status("error", "The run could not be updated: #{e.message}")
        end
        # ---------------------------------------------------------------

        # FUNCTION | Live Mode: Rebuild the Run the Page Is Showing (V2.7.7)
        # ------------------------------------------------------------
        # The page sends its description after each change while the dock's
        # Live switch is on. The same pipeline as Update Run, as its own undo
        # step (Defaults::NA_LIVE_OPERATION), never transparent: in a shared
        # window the step before may be another session's. Every request is
        # answered with window.na_receiveRunLive, built or not, carrying the
        # page's number for it, so the page sends what it changed meanwhile.
        def self.na_live_update(config_json)
            answer = { "ok" => false, "liveSeq" => nil }
            root   = na_parse(config_json)
            return unless root
            answer["liveSeq"] = root.delete(Defaults::NA_KEY_LIVE_SEQ)
            root.delete(Defaults::NA_KEY_DRAFT_PATH)
            instance = na_target_run(RunPipelines.na_metadata(root)["Na__Run__UniqueId"])
            unless instance
                na_status("warning", "Live Mode: that run is no longer in the model.")
                return
            end
            requested = RunPipelines.na_metadata(root)["Na__Run__ComponentName"]
            report    = RunPipelines.na_pipeline_update(instance, root, name: requested.nil? ? RunPipelines::NameSuffix::NA_KEEP : requested.to_s,
                                                        operation_name: Defaults::NA_LIVE_OPERATION)
            na_after_build(report, nil, send: false)
            na_status("warning", "Live Mode: #{report[:warnings].join(' ')}") unless report[:warnings].empty?
            payload = na_run_payload(report[:instance])
            answer  = payload.merge("ok" => true, "liveSeq" => answer["liveSeq"]) if payload
        rescue Na__RunLayoutError => e
            na_refused(root, e)
        rescue StandardError => e
            DebugTools.na_debug_error("Run live update failed", e)
            na_status("error", "Live Mode could not rebuild the run: #{e.message}")
        ensure
            UiBridge.na_execute_json_function(na_dialog, "window.na_receiveRunLive", answer) if answer
        end
        # ---------------------------------------------------------------

        # FUNCTION | Rename the Run (the Name Tail Only)
        # ------------------------------------------------------------
        def self.na_rename(payload_json)
            payload  = na_parse(payload_json) || {}
            instance = na_target_run(payload["runId"])
            return unless instance
            na_status("success", "Renamed #{RunPipelines.na_pipeline_rename(instance, payload['name'].to_s)}.")
            na_send_run(instance, "renamed")
        rescue StandardError => e
            DebugTools.na_debug_error("Run rename failed", e)
            na_status("error", "The run could not be renamed: #{e.message}")
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Panel Edits (the Right-Click Menu)
# -----------------------------------------------------------------------------

        # FUNCTION | Make Unique, Recode, or Change the Type or Product of a Panel
        # ------------------------------------------------------------
        # Built at once, as one undo step: the commands of the member banner
        # and of the tab's menu on a built run with nothing staged.
        # @param payload_json { runId, leg, span (zero-based), code, from, to, product }
        # @param edit [Symbol] :unique | :recode | :set_type | :span_product | :type_product
        def self.na_panel_edit(payload_json, edit)
            payload  = na_parse(payload_json) || {}
            instance = na_target_run(payload["runId"])
            unless instance
                na_status("warning", "That run is no longer in the model.")
                return
            end
            leg, span   = payload["leg"].to_i, payload["span"].to_i
            was_member  = na_selected_member_of(instance)
            report, said =
                case edit
                when :unique
                    done = RunPipelines.na_pipeline_make_unique(instance, leg, span, payload["code"])
                    [done, "Panel made unique: it is now panel type #{done[:edit]}, on its own."]
                when :recode
                    done = RunPipelines.na_pipeline_recode(instance, payload["from"], payload["to"])
                    [done, "Panel type #{payload['from'].to_s.upcase} is now #{done[:edit]}."]
                when :span_product
                    done  = RunPipelines.na_pipeline_set_span_product(instance, leg, span, payload["product"])
                    label = RunEdits.na_product_label(payload["product"].to_s.strip.downcase)
                    [done, done[:edit][:made] ? "That span is now panel type #{done[:edit][:code]}, #{label}: a new type." : "Panel type #{done[:edit][:code]} is now #{label}."]
                when :type_product
                    done = RunPipelines.na_pipeline_set_type_product(instance, payload["code"], payload["product"])
                    [done, "Panel type #{done[:edit]} is now #{RunEdits.na_product_label(payload['product'].to_s.strip.downcase)}: every span of it."]
                else
                    done = RunPipelines.na_pipeline_set_span_type(instance, leg, span, payload["code"])
                    [done, "That span is now panel type #{payload['code'].to_s.upcase}."]
                end
            na_after_build(report, said, reselect: was_member ? [leg, span] : nil, was_member: was_member)
        rescue ArgumentError, Na__RunLayoutError => e
            na_status("warning", e.message)
        rescue StandardError => e
            DebugTools.na_debug_error("Run panel edit failed", e)
            na_status("error", "That could not be done: #{e.message}")
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Edit Path in SketchUp
# -----------------------------------------------------------------------------

        # FUNCTION | Open the Shown Run's Path as a Red Line in the Model
        # ------------------------------------------------------------
        def self.na_edit_path
            instance = na_target_run(nil)
            unless instance
                na_status("warning", "Select an assembly run, then Edit Path.")
                return
            end
            opened = PathEditor.na_open(instance)
            UiBridge.na_execute_json_function(na_dialog, "window.na_setRunPathEdit", { "active" => true, "runId" => opened[:run_id] })
            na_status("info", "The red line is #{opened[:run_id]}'s path. Move its corners, add or erase lines, then click outside it (or Finish Path Edit): the run rebuilds along it.")
        rescue StandardError => e
            na_status("warning", e.message)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Path Editor Listener: a Path Edit Ended
        # ------------------------------------------------------------
        def self.na_path_edit_finished(result)
            still_open = !PathEditor.na_editing_run_id.nil?
            UiBridge.na_execute_json_function(na_dialog, "window.na_setRunPathEdit", { "active" => still_open, "runId" => PathEditor.na_editing_run_id })
            type = { :rebuilt => "success", :unchanged => "info", :discarded => "info" }[result[:status]] || "warning"
            na_status(type, result[:message])
            na_after_build(result[:report], nil) if result[:report]
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Selection
# -----------------------------------------------------------------------------

        # FUNCTION | A Run Was Selected: Show It in the Tab
        # ------------------------------------------------------------
        def self.na_load_into_dialog(instance, _run_id)
            @na_current_instance = instance
            na_send_run(instance, "selected")                                    # <-- V2.7.7: the page keeps staged changes to it
        end
        # ---------------------------------------------------------------

        # FUNCTION | Nothing (or Something Else) Is Selected
        # ------------------------------------------------------------
        def self.na_clear_from_dialog
            UiBridge.na_invoke(na_dialog, "window.na_clearCurrentRun")
        end
        # ---------------------------------------------------------------

        # FUNCTION | Selection Listener: Is the Selected Element a Span of a Run
        # ------------------------------------------------------------
        # Called by the SelectionCoordinator on every selection change,
        # whichever tab the element itself loads into. A span's element
        # gets the banner: which run, which panel type, how many share it.
        def self.na_selection_changed(selection)
            instance = (selection.length == 1 && selection.first.is_a?(Sketchup::ComponentInstance)) ? selection.first : nil
            member   = instance ? DataSerializer.na_member_of(instance) : nil
            unless member
                UiBridge.na_invoke(na_dialog, "window.na_clearRunMember")
                return
            end
            copies = DataSerializer.na_members(member[:run_definition]).count do |other|
                other.get_attribute(Defaults::NA_MEMBER_DICT, Defaults::NA_MEMBER_KEY_TYPE).to_s == member[:type]
            end
            run    = DataSerializer.na_instance_of(member[:run_definition])
            config = na_stored_config(run)
            rows   = Array(config[Defaults.na_key("PanelTypes")]).select { |row| row.is_a?(Hash) }
            own    = rows.find { |row| row["Code"].to_s.strip.upcase == member[:type].to_s.strip.upcase } || {}
            mode   = config[Defaults.na_key("Mode")].to_s
            UiBridge.na_execute_json_function(na_dialog, "window.na_setRunMember", {
                "runId"    => member[:run_id],
                "runName"  => run ? run.name : member[:run_id],
                "type"     => member[:type],
                "leg"      => member[:leg],
                "span"     => member[:span],
                "copies"   => copies,
                "types"    => rows.map { |row| row["Code"].to_s },
                "product"  => own["Product"].to_s,                               # <-- V2.7.2: what the panel is, and what it can become
                "auto"     => own["Auto"] == true,
                "products" => (Defaults::NA_MODE_PRODUCTS[mode] || []).map { |key| { "key" => key, "label" => RunEdits.na_product_label(key) } }
            })
        rescue StandardError => e
            DebugTools.na_debug_warn("Run member banner failed: #{e.message}")
        end
        # ---------------------------------------------------------------

        # FUNCTION | Member Sync Listener: a Panel Was Put Back to Its Run's Sizes
        # ------------------------------------------------------------
        # The rebuild replaced the span's instance, so it is selected again
        # (its own tab reloads, showing the sizes the run gives it).
        def self.na_member_refitted(result)
            na_reselect_member(result[:run], result[:leg], result[:span])
            na_status("warning", result[:message])
        end
        # ---------------------------------------------------------------

        # FUNCTION | Select One Span's Element in the Model (Opens the Run)
        # ------------------------------------------------------------
        # The element then loads into its own tab, as a click on it would.
        def self.na_select_member(payload_json)
            payload  = na_parse(payload_json) || {}
            instance = na_target_run(payload["runId"])
            return unless instance
            na_reselect_member(instance, payload["leg"].to_i, payload["span"].to_i) ||
                na_status("warning", "That span could not be selected: open the group holding the run first.")
        end
        # ---------------------------------------------------------------

        # FUNCTION | Select the Run Itself
        # ------------------------------------------------------------
        def self.na_select_run(payload_json)
            payload  = na_parse(payload_json) || {}
            instance = na_target_run(payload["runId"])
            return unless instance
            model = Sketchup.active_model
            path  = Array(model.active_path)
            index = path.index(instance)
            model.active_path = (index.zero? ? nil : path[0...index]) if index   # <-- Step out of the run first
            model.selection.clear
            model.selection.add(instance) if instance.parent == model.active_entities.parent
            Na__AssemblyStudio::Na__AppCore::Na__SelectionCoordinator.na_dispatch_selection(model.selection)
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Push One Run's Stored Data and Layout to the Tab
        # ------------------------------------------------------------
        # @param reason [String] V2.7.7: "selected", "built" or "renamed"; the
        #   page keeps its staged changes to the run on anything but "built"
        def self.na_send_run(instance, reason = "built")
            payload = na_run_payload(instance)
            UiBridge.na_execute_json_function(na_dialog, "window.na_setInitialRunConfig", payload.merge("reason" => reason)) if payload
        end
        private_class_method :na_send_run
        # ---------------------------------------------------------------

        # FUNCTION | One Run as the Tab Shows It (Also Read by the Offline Page Test)
        # ------------------------------------------------------------
        # @return [Hash, nil]
        def self.na_run_payload(instance)
            loaded = RunPipelines.na_pipeline_load(instance)
            return nil unless loaded
            {
                "runId"  => loaded[:id],
                "name"   => instance.name,
                "copies" => instance.definition.instances.length,
                "root"   => loaded[:root],
                "layout" => na_layout_payload(loaded[:root])["layout"]
            }
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | After a Build or Rebuild: Track, Select, Report
        # ------------------------------------------------------------
        # @param reselect   [Array, nil] [leg, span] of the span to select again
        # @param was_member [Boolean] the user was inside the run on a span
        # @param send       [Boolean] V2.7.7: false for Live Mode, whose answer
        #   carries the run (a "built" payload here would overwrite what the
        #   page changed while it was building)
        def self.na_after_build(report, message, reselect: nil, was_member: false, send: true)
            instance = report[:instance]
            @na_current_instance = instance
            model = Sketchup.active_model
            if reselect && na_reselect_member(instance, reselect[0], reselect[1])
                # The span's element is selected again and loads into its own tab.
            elsif !was_member && instance.parent == model.active_entities.parent
                model.selection.clear
                model.selection.add(instance)
            end
            na_send_run(instance, "built") if send
            return unless message
            warned = report[:warnings].empty? ? "" : " Note: #{report[:warnings].join(' ')}"
            na_status(report[:warnings].empty? ? "success" : "warning", "#{message}#{warned}")
        end
        private_class_method :na_after_build
        # ---------------------------------------------------------------

        # HELPER FUNCTION | A Refused Configuration: Say Why, Show Every Error
        # ------------------------------------------------------------
        def self.na_refused(root, error)
            na_send_layout(JSON.generate(root)) if root
            na_status("warning", error.na_errors.first.to_s + (error.na_errors.length > 1 ? " (and #{error.na_errors.length - 1} more: see the list under the preview)" : ""))
        end
        private_class_method :na_refused
        # ---------------------------------------------------------------

        # HELPER FUNCTION | The Run an Action Is For
        # ------------------------------------------------------------
        # By id when one is given (the model is searched, the run being
        # edited first); else the selected run; else the one last shown.
        def self.na_target_run(run_id)
            model = Sketchup.active_model
            wanted = run_id.to_s
            unless wanted.empty?
                open_run = Array(model.active_path).find { |entity| DataSerializer.na_get_id_from_instance(entity) == wanted }
                return open_run if open_run
                return @na_current_instance if @na_current_instance && @na_current_instance.valid? && DataSerializer.na_get_id_from_instance(@na_current_instance) == wanted
                return DataSerializer.na_all_runs(model).find { |instance| DataSerializer.na_get_id_from_instance(instance) == wanted }
            end
            selected = model.selection.find { |entity| DataSerializer.na_get_id_from_instance(entity) }
            return selected if selected
            (@na_current_instance && @na_current_instance.valid?) ? @na_current_instance : nil
        end
        private_class_method :na_target_run
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Is the Selection a Span Inside This Run
        # ------------------------------------------------------------
        def self.na_selected_member_of(instance)
            selected = Sketchup.active_model.selection.first
            member   = selected ? DataSerializer.na_member_of(selected) : nil
            !member.nil? && member[:run_definition] == instance.definition
        end
        private_class_method :na_selected_member_of
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Select the Element Standing in One Span
        # ------------------------------------------------------------
        # Opens the run when it stands in the open context. Selection#add
        # from code raises no onSelectionBulkChange, so the coordinator is
        # called directly (as the agent seam's open_dialog does).
        # @return [Boolean]
        def self.na_reselect_member(instance, leg_index, span_index)
            member = RunPipelines.na_member_at(instance, leg_index, span_index)
            return false unless member
            model = Sketchup.active_model
            path  = Array(model.active_path)
            unless path.last == instance
                return false unless instance.parent == model.active_entities.parent
                model.active_path = path + [instance]
            end
            model.selection.clear
            model.selection.add(member)
            Na__AssemblyStudio::Na__AppCore::Na__SelectionCoordinator.na_dispatch_selection(model.selection)
            true
        end
        private_class_method :na_reselect_member
        # ---------------------------------------------------------------

        # HELPER FUNCTION | The Configuration a Run Stores ({} When It Is No Run)
        # ------------------------------------------------------------
        def self.na_stored_config(run_instance)
            loaded = run_instance ? RunPipelines.na_pipeline_load(run_instance) : nil
            loaded ? RunPipelines.na_config(loaded[:root]) : {}
        end
        private_class_method :na_stored_config
        # ---------------------------------------------------------------

        # HELPER FUNCTION | The Live Shared Dialog (Owned by AppCore)
        # ------------------------------------------------------------
        def self.na_dialog
            return nil unless defined?(::Na__AssemblyStudio::Na__AppCore::Na__DialogManager)
            ::Na__AssemblyStudio::Na__AppCore::Na__DialogManager.na_get_dialog
        end
        private_class_method :na_dialog
        # ---------------------------------------------------------------

        # HELPER FUNCTION | A Status Message in the Dialog's Dock
        # ------------------------------------------------------------
        def self.na_status(type, message)
            UiBridge.na_send_status(na_dialog, type, message)
        end
        private_class_method :na_status
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Parse a Payload (Nil, With a Status, When Unreadable)
        # ------------------------------------------------------------
        def self.na_parse(json)
            return nil if json.nil?
            parsed = JSON.parse(json.to_s)
            parsed.is_a?(Hash) ? parsed : nil
        rescue JSON::ParserError => e
            DebugTools.na_debug_error("Run payload unreadable", e)
            na_status("error", "The run's settings could not be read.")
            nil
        end
        private_class_method :na_parse
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__DialogRouter
end # module Na__AssemblyRunSystem
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
