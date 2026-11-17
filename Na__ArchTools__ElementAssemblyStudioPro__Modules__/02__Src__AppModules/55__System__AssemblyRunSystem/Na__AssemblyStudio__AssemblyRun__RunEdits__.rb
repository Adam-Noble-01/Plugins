# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - ASSEMBLY RUN SYSTEM - RUN EDITS
# =============================================================================
#
# FILE       : Na__AssemblyStudio__AssemblyRun__RunEdits__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__AssemblyRunSystem
# MODULE     : Na__RunEdits
# AUTHOR     : Noble Architecture
# PURPOSE    : The changes a user or an agent makes to a run, each as a plain
#              change to its configuration: Make Panel Unique, recode a panel
#              type, give a span another type or another product, turn the
#              run inside out, set a new path. The pipeline then rebuilds the
#              run from the changed configuration, so every edit takes the one
#              build path.
# CREATED    : 16-Nov-2026 (V2.7.0); products and Flip Inside Out V2.7.2
#
# ANOTHER PRODUCT (V2.7.2)
# - A panel type's product (casement, sliding, base ...) is what its element
#   IS. Changing it drops what belonged to the old element (its id, its kept
#   settings, its preset and values): the type is built again from the new
#   product's start. Its code, width and height stay, and its sill too when
#   the new product is a window.
# - One span, a leg's fill, or a whole type can change. A span or a fill
#   that shares its type takes a new type under the next code; one that has
#   its type to itself changes that type.
#
# FLIP INSIDE OUT (V2.7.2)
# - The elements are seen from the RIGHT of the path. Turning a run inside
#   out is therefore turning its path round: the points, the legs and each
#   leg's items are stored in the opposite order, in the same place. Nothing
#   else in the system needs to know.
#
# THE DIALOG STAGES SOME EDITS HERE (na_stage!)
# - The Assembly Runs tab sends its description and the edit's name; the
#   description comes back changed, for Update Run to build. One rule for
#   the tab, the banner, the agent seam and the offline suite.
#
# EVERY EDIT IS DATA FIRST
# - Nothing here touches the model. An edit changes the configuration (and
#   raises ArgumentError, naming the fix, when it cannot); Na__RunPipelines
#   resolves and rebuilds. A failed rebuild aborts, leaving the run as it was.
#
# A LEG FILLED BY A RULE BECOMES A LIST WHEN ONE SPAN IS SINGLED OUT
# - A leg with a Fill ("three of type A", "600 units, remainder at the end")
#   has no list to change one span of. Singling one out writes the leg's
#   present spans and columns down as its Items; the Fill rule is kept beside
#   them as FillWas, for the record, and no longer drives the leg.
#
# PURE RUBY: no Sketchup or Geom calls, so the offline suite can run it.
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix.
#
# =============================================================================

require 'json'
require_relative 'Na__AssemblyStudio__AssemblyRun__Defaults__'
require_relative 'Na__AssemblyStudio__AssemblyRun__PathMath__'

module Na__AssemblyStudio
module Na__AssemblyRunSystem
    module Na__RunEdits

# -----------------------------------------------------------------------------
# REGION | Module References
# -----------------------------------------------------------------------------

        Defaults = Na__AssemblyStudio::Na__AssemblyRunSystem::Na__Defaults
        PathMath = Na__AssemblyStudio::Na__AssemblyRunSystem::Na__PathMath

        # What a panel type row holds of the element it stood for. All of it
        # goes when the product changes: the type is then built again from
        # the new product's own starting values.
        NA_ELEMENT_KEYS = %w[ElementId SeedRoot SeedFrom PresetCode Values FrameBeforeFuse UniqueOf].freeze

        # A cabinet fill's leftover, seen from the other end of its leg.
        NA_INFILL_TURNED = {
            Defaults::NA_INFILL_END   => Defaults::NA_INFILL_START,
            Defaults::NA_INFILL_START => Defaults::NA_INFILL_END
        }.freeze

        # The edits the Assembly Runs tab stages through na_stage!.
        NA_STAGED_EDITS = %w[span_product fill_product type_product flip].freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Rows and Legs
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | The Panel Type Rows (Made When Absent)
        # ------------------------------------------------------------
        def self.na_rows(config)
            key = Defaults.na_key("PanelTypes")
            config[key] = [] unless config[key].is_a?(Array)
            config[key]
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | One Panel Type Row by Code, or a Refusal
        # ------------------------------------------------------------
        def self.na_row!(config, code)
            wanted = code.to_s.strip.upcase
            row    = na_rows(config).find { |item| item.is_a?(Hash) && item["Code"].to_s.strip.upcase == wanted }
            return row if row
            raise ArgumentError, "There is no panel type '#{wanted}' on this run (#{na_codes(config).join(', ')})."
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Every Panel Type Code in Use
        # ------------------------------------------------------------
        def self.na_codes(config)
            na_rows(config).map { |row| row["Code"].to_s.strip.upcase }
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | The Leg Rows, One per Leg (Made and Padded)
        # ------------------------------------------------------------
        def self.na_leg_rows(config, leg_count)
            key = Defaults.na_key("Legs")
            config[key] = [] unless config[key].is_a?(Array)
            config[key] << {} while config[key].length < leg_count
            config[key].map! { |row| row.is_a?(Hash) ? row : {} }
            config[key]
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Leg's Present Spans and Columns as an Items List
        # ------------------------------------------------------------
        # The run's own additions (joint columns, end columns, fused posts)
        # are left out: the resolver adds them again.
        # @param layout_leg [Hash] one leg of a resolved layout
        def self.na_items_of(layout_leg)
            Array(layout_leg[:items]).filter_map do |item|
                if item[:kind] == Defaults::NA_ITEM_SPAN
                    { "Kind" => Defaults::NA_ITEM_SPAN, "PanelType" => item[:type] }
                elsif item[:kind] == Defaults::NA_ITEM_COLUMN && %w[Item Fill].include?(item[:origin].to_s)
                    { "Kind" => Defaults::NA_ITEM_COLUMN, "Column" => item[:role], "Width_mm" => item[:width].round(1) }
                end
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Write a Leg Down as Its Own Items List
        # ------------------------------------------------------------
        # @return [Array<Hash>] the leg's Items (the live list, to change)
        def self.na_materialise_leg!(config, layout, leg_index)
            layout_leg = layout[:legs][leg_index]
            raise ArgumentError, "The run has no leg #{leg_index + 1} (it has #{layout[:legs].length})." unless layout_leg

            row = na_leg_rows(config, layout[:legs].length)[leg_index]
            unless row["Items"].is_a?(Array) && !row["Items"].empty?
                row["Items"]   = na_items_of(layout_leg)
                row["FillWas"] = row.delete("Fill") if row["Fill"]
                na_write_down_types!(config, layout, row["Items"])
            end
            row["Items"]
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Give a Listed Span's Fill-Made Type Its Row
        # ------------------------------------------------------------
        # A cabinet fill makes the narrower types it needs. Until the run is
        # built they are in the layout only, with no row; a leg written down
        # as a list named them all the same, and the next layout refused it
        # ("panel type 'B' is not in the list", found 16-Nov-2026). Each one
        # is written down here as a panel type at the width it has, to be
        # built as a copy of the type it came from.
        def self.na_write_down_types!(config, layout, items)
            rows = na_rows(config)
            items.each do |item|
                next unless item["Kind"] == Defaults::NA_ITEM_SPAN
                code = item["PanelType"].to_s.strip.upcase
                type = layout[:types][code]
                next unless type && rows.none? { |row| row.is_a?(Hash) && row["Code"].to_s.strip.upcase == code }
                rows << { "Code" => code, "Product" => type[:product], "Width_mm" => (type[:width] ? type[:width].round(1) : nil),
                          "SeedFrom" => type[:derived_from] }.compact
            end
        end
        private_class_method :na_write_down_types!
        # ---------------------------------------------------------------

        # HELPER FUNCTION | The Items Entry of the Nth Span on a Leg
        # ------------------------------------------------------------
        def self.na_span_entry!(items, leg_index, span_index)
            spans = items.select { |item| item.is_a?(Hash) && item["Kind"] == Defaults::NA_ITEM_SPAN }
            entry = span_index >= 0 ? spans[span_index] : nil
            return entry if entry
            raise ArgumentError, "Leg #{leg_index + 1} has #{spans.length} span#{spans.length == 1 ? '' : 's'}; there is no span #{span_index + 1}."
        end
        private_class_method :na_span_entry!
        # ---------------------------------------------------------------

        # HELPER FUNCTION | The Nth Span of a Leg as the Layout Stands It
        # ------------------------------------------------------------
        # Read before anything is changed, so a refusal leaves the
        # configuration exactly as it was.
        # @return [Hash] the layout's span item (:type, :width ...)
        def self.na_layout_span!(layout, leg_index, span_index)
            leg = leg_index >= 0 ? layout[:legs][leg_index] : nil
            raise ArgumentError, "The run has no leg #{leg_index + 1} (it has #{layout[:legs].length})." unless leg
            spans = Array(leg[:items]).select { |item| item[:kind] == Defaults::NA_ITEM_SPAN }
            span  = span_index >= 0 ? spans[span_index] : nil
            return span if span
            raise ArgumentError, "Leg #{leg_index + 1} has #{spans.length} span#{spans.length == 1 ? '' : 's'}; there is no span #{span_index + 1}."
        end
        private_class_method :na_layout_span!
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Does Any Other Leg Use This Panel Type
        # ------------------------------------------------------------
        # Asked of the layout (which knows a leg left empty takes the first
        # type, and the narrower types a fill makes from this one) and of
        # the leg rows themselves (a leg the layout could not set out).
        def self.na_type_on_other_legs?(config, layout, code, leg_index)
            laid = layout[:legs].any? do |leg|
                next false if leg[:index] == leg_index
                Array(leg[:items]).any? do |item|
                    next false unless item[:kind] == Defaults::NA_ITEM_SPAN
                    item[:type] == code || (layout[:types][item[:type]] || {})[:derived_from] == code
                end
            end
            return true if laid

            Array(config[Defaults.na_key("Legs")]).each_with_index.any? do |leg, index|
                next false if index == leg_index || !leg.is_a?(Hash)
                listed = Array(leg["Items"]).any? { |item| item.is_a?(Hash) && item["PanelType"].to_s.strip.upcase == code }
                listed || (leg["Fill"].is_a?(Hash) && leg["Fill"]["PanelType"].to_s.strip.upcase == code)
            end
        end
        private_class_method :na_type_on_other_legs?
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API - Panel Edits
# -----------------------------------------------------------------------------

        # FUNCTION | Make One Span's Panel Its Own Type, With a New Code
        # ------------------------------------------------------------
        # The new type starts as a copy of the old one's element (seed_root)
        # at the width the span has now, so nothing else on the run moves.
        # @param seed_root [Hash] the present element's full payload
        # @param new_code  [String, nil] the code to give it (nil = next free)
        # @return [String] the new panel type's code
        def self.na_make_unique!(config, layout, leg_index, span_index, seed_root, new_code = nil)
            items  = na_materialise_leg!(config, layout, leg_index)
            entry  = na_span_entry!(items, leg_index, span_index)
            old    = na_row!(config, entry["PanelType"])
            type   = layout[:types][old["Code"].to_s.strip.upcase] || {}
            if type[:count].to_i <= 1
                raise ArgumentError, "Panel type #{old['Code']} is used on this one span only: it is already unique. Recode it to give it another code."
            end

            code = na_claim_code!(config, new_code)
            copy = JSON.parse(JSON.generate(old.reject { |key, _value| %w[ElementId SeedRoot SeedFrom Auto DerivedFrom].include?(key) }))
            copy["Code"]     = code
            copy["Width_mm"] = type[:width].round(1) if type[:width]
            copy["SeedRoot"] = JSON.parse(JSON.generate(seed_root)) if seed_root.is_a?(Hash)
            copy["UniqueOf"] = old["Code"].to_s.strip.upcase
            na_rows(config) << copy
            entry["PanelType"] = code
            code
        end
        # ---------------------------------------------------------------

        # FUNCTION | Give a Panel Type Another Code, Everywhere It Is Used
        # ------------------------------------------------------------
        # @return [String] the new code
        def self.na_recode!(config, from_code, to_code)
            row  = na_row!(config, from_code)
            from = row["Code"].to_s.strip.upcase
            to   = to_code.to_s.strip.upcase
            return from if to == from
            na_claim_code!(config, to)

            row["Code"] = to
            na_rows(config).each do |other|
                %w[DerivedFrom SeedFrom UniqueOf].each { |key| other[key] = to if other[key].to_s.strip.upcase == from }
            end
            Array(config[Defaults.na_key("Legs")]).each do |leg|
                next unless leg.is_a?(Hash)
                Array(leg["Items"]).each { |item| item["PanelType"] = to if item.is_a?(Hash) && item["PanelType"].to_s.strip.upcase == from }
                %w[Fill FillWas].each do |key|
                    leg[key]["PanelType"] = to if leg[key].is_a?(Hash) && leg[key]["PanelType"].to_s.strip.upcase == from
                end
            end
            to
        end
        # ---------------------------------------------------------------

        # FUNCTION | Give One Span Another Panel Type Already on the Run
        # ------------------------------------------------------------
        def self.na_set_span_type!(config, layout, leg_index, span_index, code)
            target = na_row!(config, code)
            items  = na_materialise_leg!(config, layout, leg_index)
            na_span_entry!(items, leg_index, span_index)["PanelType"] = target["Code"].to_s.strip.upcase
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | A Free, Valid Code (Given, or the Next Letter)
        # ------------------------------------------------------------
        def self.na_claim_code!(config, wanted)
            taken = na_codes(config)
            code  = wanted.to_s.strip.upcase
            return Defaults.na_next_type_code(taken) if code.empty?
            unless Defaults.na_valid_type_code?(code)
                raise ArgumentError, "'#{wanted}' will not do as a panel type code: a letter, then up to five letters or digits (A, B2, DR1)."
            end
            raise ArgumentError, "Panel type #{code} is already on this run. Pick a code that is not one of #{taken.join(', ')}." if taken.include?(code)
            code
        end
        private_class_method :na_claim_code!
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API - Another Product (V2.7.2)
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | A Product Key of the Run's Mode, or a Refusal
        # ------------------------------------------------------------
        def self.na_product!(config, product)
            mode    = config[Defaults.na_key("Mode")].to_s
            mode    = Defaults::NA_MODE_FRAMES unless Defaults::NA_MODES.include?(mode)
            allowed = Defaults::NA_MODE_PRODUCTS[mode]
            wanted  = product.to_s.strip.downcase
            return wanted if allowed.include?(wanted)
            raise ArgumentError, "'#{product}' is not a #{mode} product. Use one of: #{allowed.join(', ')}."
        end
        private_class_method :na_product!
        # ---------------------------------------------------------------

        # HELPER FUNCTION | A Product's Name as the Tab Shows It
        # ------------------------------------------------------------
        def self.na_product_label(product)
            Defaults::NA_PRODUCT_LABELS[product.to_s] || product.to_s
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Make a Row Stand for Another Product
        # ------------------------------------------------------------
        # Its code, width and height stay. The sill stays only under a window.
        def self.na_become!(row, product)
            NA_ELEMENT_KEYS.each { |key| row.delete(key) }
            row["Product"] = product
            row.delete("SillHeight_mm") unless Defaults::NA_SILL_PRODUCTS.include?(product)
            row
        end
        private_class_method :na_become!
        # ---------------------------------------------------------------

        # HELPER FUNCTION | A New Row of Another Product, Sized Like an Old One
        # ------------------------------------------------------------
        # @param width [Numeric, String, nil] nil leaves the width out: the
        #     type's spans then share what their leg has left
        def self.na_row_like(source, code, product, width)
            row = { "Code" => code, "Product" => product }
            row["Width_mm"]      = width.is_a?(Numeric) ? width.round(1) : width unless width.nil? || width.to_s.strip.empty?
            row["Height_mm"]     = source["Height_mm"] unless source["Height_mm"].nil?
            row["SillHeight_mm"] = source["SillHeight_mm"] if Defaults::NA_SILL_PRODUCTS.include?(product) && source["SillHeight_mm"].to_f > 0
            row
        end
        private_class_method :na_row_like
        # ---------------------------------------------------------------

        # FUNCTION | Give a Panel Type Another Product: Every Span of It Changes
        # ------------------------------------------------------------
        # The narrower types a cabinet fill made from it follow.
        # @return [String] the type's code
        def self.na_set_type_product!(config, code, product)
            row    = na_row!(config, code)
            wanted = na_product!(config, product)
            own    = row["Code"].to_s.strip.upcase
            if row["Auto"] == true
                parent = row["DerivedFrom"].to_s.strip.upcase
                raise ArgumentError, "Panel type #{own} is made by a leg's fill rule from type #{parent}, and follows it. " \
                                     "Change #{parent}, or change the one span: it is then given a type of its own."
            end
            return own if row["Product"].to_s == wanted

            na_become!(row, wanted)
            na_rows(config).each do |child|
                next unless child.is_a?(Hash) && child["Auto"] == true && child["DerivedFrom"].to_s.strip.upcase == own
                na_become!(child, wanted)
                child["SeedFrom"] = own                                          # <-- Built as a copy of its parent's new element, at its own width
            end
            own
        end
        # ---------------------------------------------------------------

        # FUNCTION | Give One Span Another Product
        # ------------------------------------------------------------
        # A span that shares its type takes a new type (the next code, or
        # new_code) sized as the old one, so nothing else on the run moves.
        # A span with its type to itself changes that type.
        # @param leg_index, span_index [Integer] zero-based
        # @return [Hash] { :code => the span's type now, :made => a new type was added }
        def self.na_set_span_product!(config, layout, leg_index, span_index, product, new_code = nil)
            wanted = na_product!(config, product)
            span   = na_layout_span!(layout, leg_index, span_index)
            code   = span[:type].to_s
            type   = layout[:types][code] || {}
            if type[:product].to_s == wanted
                raise ArgumentError, "Leg #{leg_index + 1} span #{span_index + 1} is already #{na_product_label(wanted)} (panel type #{code}). " \
                                     "Make Panel Unique gives it a type of its own."
            end

            # A type a fill made follows its rule, so its leg is written down
            # as a list first: the span's type is then the span's own.
            fill_made = type[:auto] == true
            alone     = type[:count].to_i <= 1 && !na_type_on_other_legs?(config, layout, code, leg_index)
            items     = fill_made || !alone ? na_materialise_leg!(config, layout, leg_index) : nil
            own       = na_row!(config, code)

            if alone
                if own["Auto"] == true
                    own.delete("Auto")
                    own.delete("DerivedFrom")
                    own["Width_mm"] = type[:width].round(1) if type[:width]
                end
                kept = na_set_type_product!(config, code, wanted)
                kept = na_recode!(config, kept, new_code) unless new_code.to_s.strip.empty?
                return { :code => kept, :made => false }
            end

            fresh = na_claim_code!(config, new_code)                             # <-- After the leg is written down: its types' codes are taken by then
            entry = na_span_entry!(items, leg_index, span_index)
            width = fill_made ? type[:width] : own["Width_mm"]                   # <-- A fill-made width was the rule's: the new type keeps it as its own
            na_rows(config) << na_row_like(own, fresh, wanted, width)
            entry["PanelType"] = fresh
            { :code => fresh, :made => true }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Give a Leg's Fill Another Product
        # ------------------------------------------------------------
        # A fill whose type no other leg uses changes that type; otherwise
        # the leg fills with a new type, sized as the old one.
        # @return [Hash] { :code => the fill's type now, :made => a new type was added }
        def self.na_set_fill_product!(config, layout, leg_index, product, new_code = nil)
            wanted = na_product!(config, product)
            count  = layout[:legs].length
            raise ArgumentError, "The run has no leg #{leg_index + 1} (it has #{count})." unless leg_index >= 0 && leg_index < count

            row = na_leg_rows(config, count)[leg_index]
            if row["Items"].is_a?(Array) && !row["Items"].empty?
                raise ArgumentError, "Leg #{leg_index + 1} has its own list of spans: change them one at a time."
            end
            fill   = row["Fill"].is_a?(Hash) ? row["Fill"] : { "PanelType" => na_codes(config).first.to_s }
            source = na_row!(config, fill["PanelType"])
            code   = source["Code"].to_s.strip.upcase
            raise ArgumentError, "Leg #{leg_index + 1} already fills with #{na_product_label(wanted)} (panel type #{code})." if source["Product"].to_s == wanted

            unless source["Auto"] == true || na_type_on_other_legs?(config, layout, code, leg_index)
                kept = na_set_type_product!(config, code, wanted)
                kept = na_recode!(config, kept, new_code) unless new_code.to_s.strip.empty?
                return { :code => kept, :made => false }
            end

            fresh = na_claim_code!(config, new_code)
            na_rows(config) << na_row_like(source, fresh, wanted, source["Width_mm"])
            row["Fill"] = fill.merge("PanelType" => fresh)
            { :code => fresh, :made => true }
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API - Path Edits
# -----------------------------------------------------------------------------

        # FUNCTION | Set a New Path, Keeping Each Leg's Contents by Position
        # ------------------------------------------------------------
        # Leg 1 keeps leg 1's spans, and so on. A leg the new path no longer
        # has is dropped; a new leg starts empty and takes the first type.
        # @param points [Array<Array>] [[x, y], ...] mm, the run's own plan
        def self.na_set_path!(config, points, closed)
            clean = PathMath.na_clean_points(points, closed == true)
            raise ArgumentError, closed ? "A closed path needs at least three corners." : "A path needs at least two points." if clean.length < (closed ? 3 : 2)

            leg_count = closed ? clean.length : clean.length - 1
            config[Defaults.na_key("PathPoints")] = clean.map { |point| [point[0].round(2), point[1].round(2)] }
            config[Defaults.na_key("PathClosed")] = (closed == true)
            legs = na_leg_rows(config, leg_count)
            legs.slice!(leg_count..-1) if legs.length > leg_count
            corners = config[Defaults.na_key("Corners")]
            corner_count = closed ? leg_count : leg_count - 1
            corners.slice!(corner_count..-1) if corners.is_a?(Array) && corners.length > corner_count
            config
        end
        # ---------------------------------------------------------------

        # FUNCTION | Turn the Run Inside Out (V2.7.2)
        # ------------------------------------------------------------
        # The path is stored the other way round, where it lies. What was
        # its right is now its left, so every element faces the other way
        # and stands on the other side of the line; an inside corner becomes
        # an outside one. Each span and column keeps its place on the
        # ground, so a leg's items are stored in the opposite order and a
        # cabinet fill's leftover moves to the leg's other end.
        #   Open path   : the last point becomes the first. Leg 1 becomes
        #                 the last leg; corner 1 the last corner.
        #   Closed path : the first point stays the first and the rest are
        #                 walked the other way round. Corner 1 stays corner 1.
        # A blind corner (Cabinets) names no leg: after the turn it is the
        # other leg that runs into the corner.
        # @return [Boolean] the SideFlipped switch as it now stands
        def self.na_flip_side!(config)
            closed = config[Defaults.na_key("PathClosed")] == true
            stored = config[Defaults.na_key("PathPoints")] || Defaults::NA_DEFAULT_RUN_CONFIGURATION[Defaults.na_key("PathPoints")]
            points = PathMath.na_clean_points(stored, closed)
            raise ArgumentError, closed ? "A closed path needs at least three corners." : "A path needs at least two points." if points.length < (closed ? 3 : 2)

            leg_count    = closed ? points.length : points.length - 1
            corner_count = closed ? leg_count : leg_count - 1
            turned       = closed ? [points.first] + points.drop(1).reverse : points.reverse
            config[Defaults.na_key("PathPoints")] = turned.map { |point| [point[0].round(2), point[1].round(2)] }

            cabinets = config[Defaults.na_key("Mode")].to_s == Defaults::NA_MODE_CABINETS
            legs     = na_leg_rows(config, leg_count)
            legs.slice!(leg_count..-1) if legs.length > leg_count
            legs.reverse!
            legs.each { |leg| na_turn_leg_row!(leg, cabinets) }

            key     = Defaults.na_key("Corners")
            corners = config[key].is_a?(Array) ? config[key].map { |corner| corner.is_a?(Hash) ? corner : {} } : []
            corners << {} while corners.length < corner_count
            corners = corners.first(corner_count)
            corners = closed ? corners.first(1) + corners.drop(1).reverse : corners.reverse
            corners.pop while !corners.empty? && corners.last.empty?             # <-- Corners left to the run's setting need no entry at the end
            config[key] = corners

            flag = Defaults.na_key("SideFlipped")
            config[flag] = !(config[flag] == true)
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | One Leg's Row, Read From Its Other End
        # ------------------------------------------------------------
        def self.na_turn_leg_row!(leg, cabinets)
            leg["Items"].reverse! if leg["Items"].is_a?(Array)
            return leg unless cabinets
            %w[Fill FillWas].each do |name|
                rule = leg[name]
                next unless rule.is_a?(Hash)
                infill = rule["Infill"].to_s.empty? ? Defaults::NA_INFILL_END : rule["Infill"].to_s
                rule["Infill"] = NA_INFILL_TURNED[infill] if NA_INFILL_TURNED.key?(infill)
            end
            leg
        end
        private_class_method :na_turn_leg_row!
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API - Edits the Tab Stages (Nothing Is Built)
# -----------------------------------------------------------------------------

        # FUNCTION | One Staged Edit, by Name
        # ------------------------------------------------------------
        # The Assembly Runs tab sends its description and what was asked;
        # the description is changed here, for Update Run (or Create) to
        # build. The built-run pipelines and the agent seam call the same
        # functions, so a change means one thing wherever it is made.
        # @param edit [String] one of NA_STAGED_EDITS
        # @param args [Hash] { "leg", "span" (zero-based), "code", "product" }
        # @return [String] what changed, for the status line
        def self.na_stage!(config, layout, edit, args)
            args    = {} unless args.is_a?(Hash)
            leg     = args["leg"].to_i
            product = args["product"]
            case edit.to_s
            when "span_product"
                done = na_set_span_product!(config, layout, leg, args["span"].to_i, product)
                label = na_product_label(na_row!(config, done[:code])["Product"])
                done[:made] ? "Leg #{leg + 1} span #{args['span'].to_i + 1} is now panel type #{done[:code]}, #{label}: a new type." :
                              "Panel type #{done[:code]} is now #{label}."
            when "fill_product"
                done = na_set_fill_product!(config, layout, leg, product)
                label = na_product_label(na_row!(config, done[:code])["Product"])
                done[:made] ? "Leg #{leg + 1} now fills with panel type #{done[:code]}, #{label}: a new type." :
                              "Panel type #{done[:code]} is now #{label}."
            when "type_product"
                code = na_set_type_product!(config, args["code"], product)
                "Panel type #{code} is now #{na_product_label(na_row!(config, code)['Product'])}."
            when "flip"
                na_flip_side!(config)
                config[Defaults.na_key("PathClosed")] == true ?
                    "The run is turned inside out. Its legs are now numbered the other way round." :
                    "The run is turned inside out. Its legs are now numbered from the other end."
            else
                raise ArgumentError, "'#{edit}' is not an edit the tab stages (#{NA_STAGED_EDITS.join(', ')})."
            end
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__RunEdits
end # module Na__AssemblyRunSystem
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
