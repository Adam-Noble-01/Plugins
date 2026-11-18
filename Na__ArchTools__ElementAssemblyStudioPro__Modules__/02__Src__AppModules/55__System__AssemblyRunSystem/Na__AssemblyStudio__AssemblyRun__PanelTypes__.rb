# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - ASSEMBLY RUN SYSTEM - PANEL TYPES
# =============================================================================
#
# FILE       : Na__AssemblyStudio__AssemblyRun__PanelTypes__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__AssemblyRunSystem
# MODULE     : Na__PanelTypes
# AUTHOR     : Noble Architecture
# PURPOSE    : A run's panel types (A, B, C ...) and the one element each
#              stands for. Makes sure every panel type in use has an element
#              of the right size, by creating or rebuilding it through the
#              element's OWN pipeline (the Windows tab's, the Cabinetry tab's),
#              so a span is exactly what that tab would have built.
# CREATED    : 16-Nov-2026 (V2.7.0)
#
# ONE PANEL TYPE = ONE ELEMENT DEFINITION
# - Every span of type A is an instance of one AWN / ADR / ACB definition.
#   Select any of them, change it in its own tab, and all of them change:
#   that is SketchUp's own component rule, with nothing added.
# - The element's settings live on the element (its tab's own dictionary).
#   A panel type row keeps only what the run decides: the code, the product,
#   the width and height, the sill, and the element's id.
#
# A NEW TYPE'S FIRST SETTINGS (its "seed")
# - The row's SeedRoot when it has one: a full element payload, from the
#   dialog's tab, a preset, or a copy of another type (Make Panel Unique).
# - Else the product's own starting values, from the agent seam's planner
#   (60__System__McpOperations), the one Ruby copy of the dialog defaults.
#   The seed is used once and dropped; the element owns its settings after.
#
# WHAT THE RUN WRITES INTO AN ELEMENT
# - Its width; for a frame its height (less the cill, as Measure Opening
#   takes it off); and, with Fuse Framework on, both side frames set to 0 so
#   the run's own mullions and jambs are the only uprights. The side frames
#   it had are kept on the row (FrameBeforeFuse) and put back when the run
#   is unfused.
# - V2.7.3, fused WINDOWS: every frame member set to 0. The run builds the
#   window's head and bottom rail itself, at the thickness the window had
#   (na_own_rails_mm), as part of the one framework solid; the element is
#   then only its casements and glass, the height of the clear opening.
# - V2.7.3, joined cills: the element's own cill and window board switched
#   off (kept on the row as CillBeforeJoin, put back when the run stops
#   joining them). The run builds one cill and one board for the stretch,
#   and the element stands on the cill (its height less the run's cill).
#
# OPERATIONS
# - Everything here runs inside the run pipeline's one open undo step
#   (Na__OperationScope.na_embed), so the element pipelines join it.
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix.
#
# =============================================================================

require 'sketchup.rb'
require 'json'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__DebugTools__'
require_relative 'Na__AssemblyStudio__AssemblyRun__Defaults__'

module Na__AssemblyStudio
module Na__AssemblyRunSystem
    module Na__PanelTypes

# -----------------------------------------------------------------------------
# REGION | Module References and Constants
# -----------------------------------------------------------------------------

        DebugTools = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools
        Defaults   = Na__AssemblyStudio::Na__AssemblyRunSystem::Na__Defaults

        NA_SYSTEM_WINDOWS  = "window_family".freeze
        NA_SYSTEM_CABINETS = "cabinet".freeze

        NA_CONFIG_BLOCKS = {
            NA_SYSTEM_WINDOWS  => "windowConfiguration".freeze,
            NA_SYSTEM_CABINETS => "Na__CabinetConfiguration".freeze
        }.freeze

        NA_FUSE_FRAME_KEYS = %w[advanced_frame_controls frame_top_thickness_mm frame_bottom_thickness_mm
                                frame_left_thickness_mm frame_right_thickness_mm].freeze

        # What a joined cill takes over from an element (V2.7.3).
        NA_JOIN_KEYS = %w[has_cill window_board_enabled].freeze

        # A cabinet element's lowest point further above its origin than
        # this, when it should stand on the floor, is built again (V2.7.5).
        NA_FLOOR_TOLERANCE_MM = 0.5

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | The Other Systems (Resolved When Called, Never at Load)
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | The Agent Seam: Product Defaults and Element Reading
        # ------------------------------------------------------------
        def self.na_seam
            Na__AssemblyStudio::Na__McpOperations
        end
        private_class_method :na_seam
        # ---------------------------------------------------------------

        # HELPER FUNCTION | The Window Family's Pipelines
        # ------------------------------------------------------------
        def self.na_window_callbacks
            Na__AssemblyStudio::Na__WindowSystem::Na__DialogCallbacks
        end
        private_class_method :na_window_callbacks
        # ---------------------------------------------------------------

        # HELPER FUNCTION | The Cabinetry Pipelines
        # ------------------------------------------------------------
        def self.na_cabinet_router
            Na__AssemblyStudio::Na__InteriorCabinetrySystem.na_require_modules
            Na__AssemblyStudio::Na__InteriorCabinetrySystem::Na__DialogRouter
        end
        private_class_method :na_cabinet_router
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Panel Type Rows
# -----------------------------------------------------------------------------

        # FUNCTION | The Panel Type Rows of a Configuration (Made When Absent)
        # ------------------------------------------------------------
        def self.na_rows(config)
            key = Defaults.na_key("PanelTypes")
            config[key] = [] unless config[key].is_a?(Array)
            config[key]
        end
        # ---------------------------------------------------------------

        # FUNCTION | One Panel Type Row by Code (or Nil)
        # ------------------------------------------------------------
        def self.na_row(config, code)
            wanted = code.to_s.strip.upcase
            na_rows(config).find { |row| row.is_a?(Hash) && row["Code"].to_s.strip.upcase == wanted }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Bring a Layout's Fill-Made Types Into the Configuration
        # ------------------------------------------------------------
        # A cabinet fill makes the narrower types it needs (the resolver's
        # :derived_types). They join the rows so their elements are kept; a
        # fill-made type no leg uses any more is dropped.
        # A new one starts as its parent would (V2.7.4): the parent's element
        # when it has one (na_seed_root), else the parent's seed, preset and
        # values, copied here. An Equal fill gives EVERY span the derived
        # width, so the parent itself is never built: before 2.7.4 the
        # derived type then came out at the product's start, losing the
        # parent's values (SK02 ARN012, 17-Nov-2026: a 430-deep, 300-high
        # open base built 560 deep and 720 high).
        def self.na_adopt_derived!(config, layout)
            rows = na_rows(config)
            layout[:derived_types].each do |code|
                next if na_row(config, code)
                type   = layout[:types][code]
                parent = na_row(config, type[:derived_from]) || {}
                seeded = parent["SeedRoot"].is_a?(Hash)
                rows << {
                    "Code"        => code,
                    "Product"     => type[:product],
                    "Width_mm"    => type[:width],
                    "Auto"        => true,
                    "DerivedFrom" => type[:derived_from],
                    "SeedRoot"    => seeded ? na_deep_copy(parent["SeedRoot"]) : nil,
                    "PresetCode"  => seeded || parent["PresetCode"].to_s.strip.empty? ? nil : parent["PresetCode"],
                    "Values"      => seeded || !parent["Values"].is_a?(Hash) ? nil : na_deep_copy(parent["Values"]),
                    "SeedFrom"    => type[:derived_from]
                }.compact
            end
            rows.reject! { |row| row["Auto"] == true && (layout[:types][row["Code"].to_s.upcase] || {})[:count].to_i.zero? }
            rows.each do |row|                                                    # <-- A fill-made type follows the width its fill now gives it
                type = layout[:types][row["Code"].to_s.upcase]
                row["Width_mm"] = type[:width].round(1) if row["Auto"] == true && type && type[:width]
            end
            rows
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Reading the Spans Already Standing in a Run
# -----------------------------------------------------------------------------

        # FUNCTION | One Standing Member per Element, by the Element's Id
        # ------------------------------------------------------------
        # Taken before a rebuild, while every element id is still in the
        # model for the id allocators to see. Keyed by ELEMENT id, not by
        # panel type code: a recode changes the code and must find the same
        # element again (keyed by code, a recode built a fresh one and lost
        # the type's settings, 16-Nov-2026).
        # @return [Hash{String=>Hash}] id => { :instance, :root }
        def self.na_standing_members(members)
            seen = {}
            members.each_with_object({}) do |instance, found|
                next if seen[instance.definition]
                seen[instance.definition] = true
                element = na_seam.na_element_of(instance)
                found[element["id"]] = { :instance => instance, :root => element["root"] } if element
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Keep the Settings of a Panel Type No Span Uses Any More
        # ------------------------------------------------------------
        # Its spans are about to be cleared, and with them the only placed
        # copies of its element. The element's payload is kept on the row as
        # its seed, so the type builds again exactly as it was (under a new
        # element id) when a span is next given it.
        def self.na_shelve_unused!(row, standing)
            known = standing[row["ElementId"].to_s]
            return unless known
            row["SeedRoot"] = na_deep_copy(known[:root])
            row.delete("ElementId")
        end
        private_class_method :na_shelve_unused!
        # ---------------------------------------------------------------

        # FUNCTION | What an Instance Wears, to Dress Its Copies the Same
        # ------------------------------------------------------------
        # A span is placed by add_instance, which copies no attributes: the
        # element's id lives on the instance, so every copy must be given it.
        # The run's own membership stamp is left out (each span gets its own).
        # @return [Hash] { :definition, :name, :layer, :material, :attributes }
        def self.na_dress_of(instance)
            attributes = {}
            (instance.attribute_dictionaries || []).each do |dictionary|
                next if dictionary.name == Defaults::NA_MEMBER_DICT
                pairs = {}
                dictionary.each_pair { |key, value| pairs[key] = value }       # <-- each_pair without a block raises in SketchUp (it returns no enumerator)
                attributes[dictionary.name] = pairs
            end
            { :definition => instance.definition, :name => instance.name, :layer => instance.layer,
              :material => instance.material, :attributes => attributes }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Dress a Newly Placed Copy
        # ------------------------------------------------------------
        def self.na_dress!(instance, dress)
            instance.name     = dress[:name].to_s
            instance.layer    = dress[:layer] if dress[:layer] && dress[:layer].valid?
            instance.material = dress[:material] if dress[:material] && dress[:material].valid?
            dress[:attributes].each do |dictionary, pairs|
                pairs.each { |key, value| instance.set_attribute(dictionary, key, value) }
            end
            instance
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API - Every Panel Type in Use Gets Its Element
# -----------------------------------------------------------------------------

        # FUNCTION | Create or Resize the Element of Every Panel Type in Use
        # ------------------------------------------------------------
        # @param config   [Hash] the run's configuration (its rows are updated:
        #                 ElementId written, SeedRoot dropped)
        # @param layout   [Hash] the resolved layout (widths and heights)
        # @param standing [Hash] na_standing_members of the run (by element id)
        # @param run_id   [String] for the elements' name tails
        # @return [Hash] { :dresses => { code => dress }, :values => { code =>
        #     element values }, :rails => { code => { :top, :bottom } mm the
        #     run builds round a frameless window, else 0 }, :temporary =>
        #     [instances to erase when the spans are placed], :warnings => [String] }
        def self.na_ensure_elements!(config, layout, standing, run_id)
            result = { :dresses => {}, :values => {}, :rails => {}, :temporary => [], :warnings => [] }
            na_ensure_materials(result[:warnings])
            fuse = layout[:settings][:fuse]

            layout[:types].each_value do |type|
                code   = type[:code]
                row    = na_row(config, code)
                raise "Panel type #{code} has no row in the run's configuration." unless row
                if type[:count].to_i.zero?
                    na_shelve_unused!(row, standing)
                    next
                end
                system = type[:system]
                tail   = na_element_tail(run_id, code)
                known  = row["SeedRoot"].is_a?(Hash) ? nil : standing[row["ElementId"].to_s]   # <-- A seed asks for a NEW element (Make Panel Unique)
                member = known && known[:instance].valid? ? known[:instance] : nil

                if member
                    na_resize_standing!(system, member, row, type, fuse, tail)
                    instance = member
                else
                    if row["ElementId"].to_s != "" && !row["SeedRoot"].is_a?(Hash)
                        result[:warnings] << "Panel type #{code}: its element #{row['ElementId']} was no longer in the run, so a new one was made from the #{type[:product]} starting values."
                    end
                    instance = na_create_element!(system, row, type, fuse, tail, config)
                    result[:temporary] << instance
                end

                element = na_seam.na_element_of(instance)
                raise "Panel type #{code}: its element could not be read back after building." unless element
                row["ElementId"] = element["id"]
                row.delete("SeedRoot")
                row.delete("SeedFrom")
                result[:dresses][code] = na_dress_of(instance)
                result[:values][code]  = element["root"][NA_CONFIG_BLOCKS[system]] || {}
                result[:rails][code]   = type[:frameless] ? na_own_rails_mm(row, result[:values][code]) : { :top => 0.0, :bottom => 0.0 }
                na_follow_product!(row, system, result[:values][code], layout[:mode])
            end
            result
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Head and Bottom Rail a Window Had of Its Own
        # ------------------------------------------------------------
        # Read from what was kept when the run first fused it (or from the
        # values, when it was never fused): the per-side thicknesses when
        # Per-Side Frame Thickness was on, else the one Frame Thickness. The
        # run builds the rails at these sizes, so a fused window keeps the
        # frame it was given in its own tab.
        # @return [Hash] { :top, :bottom } mm
        def self.na_own_rails_mm(row, values)
            kept    = row["FrameBeforeFuse"].is_a?(Hash) ? row["FrameBeforeFuse"] : values
            uniform = (values["frame_thickness_mm"] || Na__AssemblyStudio::Na__WindowSystem::NA_DEFAULT_FRAME_THICKNESS).to_f
            return { :top => uniform, :bottom => uniform } unless kept["advanced_frame_controls"] == true
            { :top => (kept["frame_top_thickness_mm"] || uniform).to_f, :bottom => (kept["frame_bottom_thickness_mm"] || uniform).to_f }
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | A Row's Product Follows What Its Element Is
        # ------------------------------------------------------------
        # A panel's product can also be changed in its own tab (a casement
        # made a sash, a base unit given drawers). The element is then the
        # truth: the row is brought into step, so the run's tab and its
        # menus name the panel for what it is (V2.7.2).
        def self.na_follow_product!(row, system, values, mode)
            actual = na_seam.na_product_of_values(system, values)
            row["Product"] = actual if Array(Defaults::NA_MODE_PRODUCTS[mode]).include?(actual)
        rescue StandardError => e
            DebugTools.na_debug_warn("Run panel type #{row['Code']}: its element's product could not be read (#{e.message}).")
        end
        private_class_method :na_follow_product!
        # ---------------------------------------------------------------

        # HELPER FUNCTION | The Name Tail of a Type's Element: ARN001__Type-A
        # ------------------------------------------------------------
        # Shown after the element's own fixed head in the Outliner, so every
        # span says which run and which panel type it is.
        def self.na_element_tail(run_id, code)
            "#{run_id}__Type-#{code}"
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | The Material Library, Loaded as Opening the Dialog Loads It
        # ------------------------------------------------------------
        def self.na_ensure_materials(warnings)
            na_seam.send(:na_ensure_materials)
        rescue StandardError => e
            warnings << "The material library could not be loaded, so finishes may be blank: #{e.message}"
        end
        private_class_method :na_ensure_materials
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Creating and Resizing One Element
# -----------------------------------------------------------------------------

        # SUB FUNCTION | A New Element for a Panel Type, at the Origin
        # ------------------------------------------------------------
        # The instance it returns is temporary: the spans are instances of
        # its definition inside the run, and this one is erased afterwards.
        def self.na_create_element!(system, row, type, fuse, tail, config)
            root = na_seed_root(row, type, config)
            na_apply_size!(system, root, row, type, fuse)
            na_check_buildable!(system, type, root)
            instance =
                if system == NA_SYSTEM_CABINETS
                    na_cabinet_metadata(root)["Na__Cabinet__ComponentName"] = tail
                    na_cabinet_router.na_pipeline_create(root, Geom::Transformation.new, "Create Cabinet")
                else
                    frame_helper = Na__AssemblyStudio::Na__GeometryHelpers::Na__InsertionFrame
                    frame = {
                        frame_helper::NA_FRAME_KEY_ORIGIN => Geom::Point3d.new(0, 0, 0),
                        frame_helper::NA_FRAME_KEY_XAXIS  => Geom::Vector3d.new(1, 0, 0),
                        frame_helper::NA_FRAME_KEY_YAXIS  => Geom::Vector3d.new(0, 1, 0),
                        frame_helper::NA_FRAME_KEY_ZAXIS  => Geom::Vector3d.new(0, 0, 1)
                    }
                    na_window_callbacks.na_pipeline_create(root, frame, name: tail)
                end
            raise "Panel type #{type[:code]}: the #{type[:product]} could not be built." unless instance && instance.valid?
            DebugTools.na_debug_geometry("Run panel type #{type[:code]}: new #{type[:product]} #{type[:width].round(1)}mm")
            instance
        end
        private_class_method :na_create_element!
        # ---------------------------------------------------------------

        # SUB FUNCTION | Rebuild a Standing Element When Its Size Has Changed
        # ------------------------------------------------------------
        # Rebuilding one member rebuilds the definition, so every span of
        # the type follows. Nothing is rebuilt when nothing changed, except
        # a cabinet still standing where an older version put it (V2.7.5,
        # na_cabinet_off_floor?).
        def self.na_resize_standing!(system, member, row, type, fuse, tail)
            element = na_seam.na_element_of(member)
            root    = element["root"]
            changed = na_apply_size!(system, root, row, type, fuse)
            na_check_buildable!(system, type, root) if changed
            if system == NA_SYSTEM_CABINETS
                changed ||= na_cabinet_off_floor?(member, root)
                na_cabinet_router.na_pipeline_update(member, root) if changed
                current = na_cabinet_metadata(root)["Na__Cabinet__ComponentName"].to_s
                na_cabinet_router.na_pipeline_rename(member, tail) unless current == tail
            else
                na_window_callbacks.na_pipeline_update(member, root, name: tail) if changed
                na_window_callbacks.na_pipeline_apply_name(member, tail) unless changed
            end
            DebugTools.na_debug_geometry("Run panel type #{type[:code]}: #{changed ? 'rebuilt' : 'kept'} at #{type[:width].round(1)}mm")
        end
        private_class_method :na_resize_standing!
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Does a Cabinet Stand Off the Floor It Should Now Stand On (V2.7.5)
        # ------------------------------------------------------------
        # Before 2.7.5 a floor unit with neither a plinth nor legs still
        # stood on PlinthHeight_mm (SK02 R23, 150 into the slab above). Its
        # element keeps that geometry until it is built again, while the
        # run's worktop and infill blocks follow the new rule (the unit's
        # top from the floor). So the run builds such an element again; one
        # already on the floor (PlinthHeight_mm 0, or built by 2.7.5) is kept.
        def self.na_cabinet_off_floor?(member, root)
            values = root[NA_CONFIG_BLOCKS[NA_SYSTEM_CABINETS]] || {}
            unit   = Na__AssemblyStudio::Na__InteriorCabinetrySystem::Na__LayoutResolver.na_effective(values)
            return false if unit[:type] == "Wall" || unit[:z_base] > 0.0
            member.definition.bounds.min.z.to_mm > NA_FLOOR_TOLERANCE_MM
        rescue StandardError => e
            DebugTools.na_debug_warn("Run cabinet floor check skipped: #{e.message}")
            false
        end
        private_class_method :na_cabinet_off_floor?
        # ---------------------------------------------------------------

        # HELPER FUNCTION | The Payload a New Element Starts From
        # ------------------------------------------------------------
        # The row's own seed; else, for a type a fill derived, the seed its
        # parent type was just built from (config-wide lookup); else the
        # product's starting values.
        def self.na_seed_root(row, type, config)
            return na_deep_copy(row["SeedRoot"]) if row["SeedRoot"].is_a?(Hash)

            parent = row["SeedFrom"].to_s.empty? ? nil : na_row(config, row["SeedFrom"])
            if parent && parent["ElementId"].to_s != ""
                copy = na_root_of_element_id(type[:system], parent["ElementId"])
                return copy if copy
            end

            preset = row["PresetCode"].to_s.strip
            values = row["Values"].is_a?(Hash) ? row["Values"] : nil
            return na_seam.na_fresh_root(type[:product]) if preset.empty? && (values.nil? || values.empty?)

            # A preset and / or values over the product's start: the seam's
            # own planner, so every value is checked as a single build's is.
            plan = na_seam.send(:na_build_plan, { "type" => type[:product], "preset" => (preset.empty? ? nil : preset), "values" => values }.compact)
            plan["root"]
        end
        private_class_method :na_seed_root
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Would the Element's Own Tab Build It at This Size
        # ------------------------------------------------------------
        # The run sets a width and height the seed never saw; the dialog's
        # own build checks (too narrow for its casements, too short for its
        # rails) are asked before anything is built.
        def self.na_check_buildable!(system, type, root)
            return unless system == NA_SYSTEM_WINDOWS
            errors = na_seam.send(:na_validation_errors, system, type[:product], root[NA_CONFIG_BLOCKS[system]] || {})
            return if errors.nil? || errors.empty?
            raise "Panel type #{type[:code]} (#{type[:product]}, #{type[:width].round}mm wide#{type[:height] ? " by #{type[:height].round}mm" : ''}) " \
                  "would be refused by its own tab: #{errors.join(' | ')}"
        end
        private_class_method :na_check_buildable!
        # ---------------------------------------------------------------

        # HELPER FUNCTION | A Copy of the Stored Payload of an Element by Id
        # ------------------------------------------------------------
        # Found on any placed instance wearing that id, at any depth.
        def self.na_root_of_element_id(system, element_id)
            Sketchup.active_model.definitions.each do |definition|
                next if definition.image?
                definition.instances.each do |instance|
                    element = na_seam.na_element_of(instance)
                    return na_deep_copy(element["root"]) if element && element["id"] == element_id && element["system"] == system
                end
            end
            nil
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | What the Run Writes Into an Element's Settings
# -----------------------------------------------------------------------------

        # FUNCTION | Write the Run's Sizes Into an Element Payload
        # ------------------------------------------------------------
        # @return [Boolean] true when any value changed
        def self.na_apply_size!(system, root, row, type, fuse)
            block  = NA_CONFIG_BLOCKS[system]
            values = (root[block] ||= {})
            before = na_deep_copy(values)

            if system == NA_SYSTEM_CABINETS
                values["Na__CabinetConfig__Width_mm"] = na_tidy(type[:width])
            else
                values["width_mm"] = na_tidy(type[:width])
                frameless = fuse && type[:frameless] == true
                rails     = na_apply_fuse!(values, row, fuse, frameless)
                na_apply_join!(values, row, type[:cill_joined] == true)
                cill = type[:cill_joined] == true ? type[:cill_lift].to_f : na_cill_deduction_mm(values)
                values["height_mm"] = na_tidy(type[:height] - cill - rails[:top] - rails[:bottom])
            end
            before != values
        end
        # ---------------------------------------------------------------

        # SUB FUNCTION | Fuse Framework: the Run's Frame Members; Unfused: Put Them Back
        # ------------------------------------------------------------
        # Fused, a panel has no side frames: the run's mullions and jambs are
        # its uprights. A fused WINDOW has no head or bottom rail either
        # (V2.7.3): the run builds them at the window's own thickness, so
        # they and the mullions are one solid. A fused door keeps its own
        # head and bottom (its threshold). Per-Side Frame Thickness is
        # switched on to reach each side.
        # @return [Hash] { :top, :bottom } mm the run builds for this panel
        #     (0 unless it is a frameless window)
        def self.na_apply_fuse!(values, row, fuse, frameless)
            none = { :top => 0.0, :bottom => 0.0 }
            unless fuse
                row.delete("FrameBeforeFuse").each { |key, value| value.nil? ? values.delete(key) : values[key] = value } if row["FrameBeforeFuse"].is_a?(Hash)
                return none
            end

            row["FrameBeforeFuse"] ||= NA_FUSE_FRAME_KEYS.each_with_object({}) { |key, kept| kept[key] = values[key] }
            own = na_own_rails_mm(row, values)
            values["advanced_frame_controls"]   = true
            values["frame_left_thickness_mm"]   = 0
            values["frame_right_thickness_mm"]  = 0
            values["frame_top_thickness_mm"]    = frameless ? 0 : na_tidy(own[:top])
            values["frame_bottom_thickness_mm"] = frameless ? 0 : na_tidy(own[:bottom])
            frameless ? own : none
        end
        private_class_method :na_apply_fuse!
        # ---------------------------------------------------------------

        # SUB FUNCTION | Joined Cills: No Cill or Window Board of Its Own; Else Put Them Back
        # ------------------------------------------------------------
        def self.na_apply_join!(values, row, joined)
            if joined
                row["CillBeforeJoin"] ||= NA_JOIN_KEYS.each_with_object({}) { |key, kept| kept[key] = values[key] }
                NA_JOIN_KEYS.each { |key| values[key] = false }
            elsif row["CillBeforeJoin"].is_a?(Hash)
                row.delete("CillBeforeJoin").each { |key, value| value.nil? ? values.delete(key) : values[key] = value }
            end
        end
        private_class_method :na_apply_join!
        # ---------------------------------------------------------------

        # HELPER FUNCTION | What Measure Opening Takes Off a Height for the Cill
        # ------------------------------------------------------------
        def self.na_cill_deduction_mm(values)
            na_seam.send(:na_cill_deduction_mm, values).to_f
        rescue StandardError => e
            DebugTools.na_debug_warn("Run cill deduction unavailable (#{e.message}); none taken off.")
            0.0
        end
        private_class_method :na_cill_deduction_mm
        # ---------------------------------------------------------------

        # HELPER FUNCTION | A Size as the Dialog Would Send It
        # ------------------------------------------------------------
        # Whole numbers as integers (the window DXF header writes "#{width}.0"),
        # the rest to a tenth of a millimetre.
        def self.na_tidy(value)
            rounded = value.to_f.round(1)
            rounded == rounded.round ? rounded.round : rounded
        end
        private_class_method :na_tidy
        # ---------------------------------------------------------------

        # HELPER FUNCTION | The First Metadata Entry of a Cabinet Payload
        # ------------------------------------------------------------
        def self.na_cabinet_metadata(root)
            list = root["Na__CabinetMetadata"]
            root["Na__CabinetMetadata"] = list = [{}] unless list.is_a?(Array) && list.first.is_a?(Hash)
            list.first
        end
        private_class_method :na_cabinet_metadata
        # ---------------------------------------------------------------

        # HELPER FUNCTION | A Deep, Unfrozen Copy of JSON-Shaped Data
        # ------------------------------------------------------------
        def self.na_deep_copy(value)
            JSON.parse(JSON.generate(value))
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__PanelTypes
end # module Na__AssemblyRunSystem
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
