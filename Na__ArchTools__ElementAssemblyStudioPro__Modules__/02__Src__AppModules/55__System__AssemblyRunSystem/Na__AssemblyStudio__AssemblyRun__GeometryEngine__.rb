# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - ASSEMBLY RUN SYSTEM - GEOMETRY ENGINE
# =============================================================================
#
# FILE       : Na__AssemblyStudio__AssemblyRun__GeometryEngine__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__AssemblyRunSystem
# MODULE     : Na__GeometryEngine
# AUTHOR     : Noble Architecture
# PURPOSE    : Fills a run's definition from its resolved layout: makes sure
#              each panel type has its element, stands an instance of it in
#              every span, then builds the run's own posts, columns and
#              corners. Used for a new run and for every rebuild.
# CREATED    : 16-Nov-2026 (V2.7.0)
#
# COMPONENT HIERARCHY
#   ARN001__AssemblyRun__<name>            ComponentInstance (the master)
#     AWN004__Window__ARN001__Type-A       a span: an instance of type A's element
#     AWN004__Window__ARN001__Type-A       another span of type A (same definition)
#     ADR002__ExteriorDoubleDoor__ARN001__Type-C
#     Na__Run__Posts                       mullions and jambs (when not fused into the framework)
#     Na__Run__Columns                     infill blocks, library columns on their backings
#     Na__Run__Corners                     corner blocks, library corner columns, corner units
#     Na__Run__Framework                   V2.7.3, fused: every frame member as ONE solid
#     Na__Run__Cill                        V2.7.3: one cill per stretch, round every corner
#     Na__Run__WindowBoard                 V2.7.3: one internal window board per stretch
#
# ORDER MATTERS ON A REBUILD
#   1. Elements first, while the old spans still stand: the id allocators
#      (AWN, ADR, ACB) count the ids they can see in the model, so a new
#      type made after the old spans were cleared could be handed an id
#      that is still in use. The standing spans are matched to their panel
#      type rows by ELEMENT id, so a recoded type keeps its element.
#   2. Then the definition is cleared and every span placed afresh.
#   3. Then the temporary instances the new elements were built on go.
#
# COORDINATES
# - Everything is placed in the run definition's own frame (a closed
#   context) from the layout's millimetres. Only the run instance itself is
#   placed in the model, by the pipeline, with a world transformation.
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__DebugTools__'
require_relative 'Na__AssemblyStudio__AssemblyRun__Defaults__'
require_relative 'Na__AssemblyStudio__AssemblyRun__LayoutResolver__'
require_relative 'Na__AssemblyStudio__AssemblyRun__DataSerializer__'
require_relative 'Na__AssemblyStudio__AssemblyRun__PanelTypes__'
require_relative 'Na__AssemblyStudio__AssemblyRun__ColumnBuilder__'
require_relative 'Na__AssemblyStudio__AssemblyRun__CornerUnitBuilder__'
require_relative 'Na__AssemblyStudio__AssemblyRun__FrameworkBuilder__'

module Na__AssemblyStudio
module Na__AssemblyRunSystem
    module Na__GeometryEngine

# -----------------------------------------------------------------------------
# REGION | Module References
# -----------------------------------------------------------------------------

        DebugTools        = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools
        Defaults          = Na__AssemblyStudio::Na__AssemblyRunSystem::Na__Defaults
        DataSerializer    = Na__AssemblyStudio::Na__AssemblyRunSystem::Na__DataSerializer
        PanelTypes        = Na__AssemblyStudio::Na__AssemblyRunSystem::Na__PanelTypes
        ColumnBuilder     = Na__AssemblyStudio::Na__AssemblyRunSystem::Na__ColumnBuilder
        CornerUnitBuilder = Na__AssemblyStudio::Na__AssemblyRunSystem::Na__CornerUnitBuilder
        FrameworkBuilder  = Na__AssemblyStudio::Na__AssemblyRunSystem::Na__FrameworkBuilder

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

        # FUNCTION | Build (or Rebuild) Everything Inside a Run's Definition
        # ------------------------------------------------------------
        # Call inside the run pipeline's open operation and embed block.
        # @param definition [Sketchup::ComponentDefinition] the run's
        # @param config     [Hash] the run's configuration (element ids are
        #                   written into its panel type rows)
        # @param layout     [Hash] Na__LayoutResolver.na_resolve of config,
        #                   with no errors
        # @return [Hash] { :components => [row per span], :warnings => [String],
        #                  :counts => { :spans, :posts, :columns, :corners,
        #                  :corner_units, :framework, :cills, :boards } }
        def self.na_build_run(definition, config, layout, run_id)
            model    = Sketchup.active_model
            standing = PanelTypes.na_standing_members(DataSerializer.na_members(definition))
            elements = PanelTypes.na_ensure_elements!(config, layout, standing, run_id)
            fused    = layout[:settings][:fuse] == true

            definition.entities.clear!
            na_fit_infill_heights!(layout, elements[:values])
            components = na_place_spans(definition.entities, layout, elements, config, run_id)
            counts     = ColumnBuilder.na_build(layout, definition.entities, model, framework: fused)
            counts[:corner_units] = na_build_corner_units(definition.entities, layout, elements[:values])
            counts[:framework]    = fused ? FrameworkBuilder.na_build_framework(definition.entities, layout, elements) : 0
            counts[:cills]        = FrameworkBuilder.na_build_cills(definition.entities, layout, elements, config)
            counts[:boards]       = FrameworkBuilder.na_build_boards(definition.entities, layout, elements, config)
            counts[:spans]        = components.length

            elements[:temporary].each { |instance| instance.erase! if instance.valid? }
            DebugTools.na_debug_geometry("Run #{run_id}: #{counts[:spans]} spans, #{counts[:posts]} posts, #{counts[:columns]} columns, " \
                                         "#{counts[:corners]} corner blocks, #{counts[:corner_units]} corner units, framework #{counts[:framework]} members, " \
                                         "#{counts[:cills]} cills, #{counts[:boards]} window boards")
            { :components => components, :warnings => elements[:warnings], :counts => counts }
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Spans
# -----------------------------------------------------------------------------

        # SUB FUNCTION | Stand an Instance of Its Panel Type's Element in Every Span
        # ------------------------------------------------------------
        # Each instance is dressed as the type's first element is (its id
        # lives on the instance) and stamped with its run, type and place.
        # It stands where its own geometry starts (V2.7.3): on the run's cill
        # when the cill is joined, and above the bottom rail the run builds
        # for a frameless window.
        # @return [Array<Hash>] the run's component rows (string keys)
        def self.na_place_spans(entities, layout, elements, config, run_id)
            rows = []
            layout[:legs].each do |leg|
                Array(leg[:items]).each do |item|
                    next unless item[:kind] == Defaults::NA_ITEM_SPAN
                    dress = elements[:dresses][item[:type]]
                    raise "Panel type #{item[:type]} has no element to place." unless dress && dress[:definition].valid?

                    rail     = (elements[:rails][item[:type]] || {})[:bottom].to_f
                    base     = (item[:base_z] || item[:z0]).to_f + rail
                    instance = entities.add_instance(dress[:definition], ColumnBuilder.na_leg_transformation(leg, item[:s0], base))
                    PanelTypes.na_dress!(instance, dress)
                    DataSerializer.na_stamp_member(instance, run_id, item[:type], item[:leg], item[:span])
                    rows << {
                        "Key"        => item[:key],
                        "Leg"        => item[:leg] + 1,
                        "Span"       => item[:span] + 1,
                        "PanelType"  => item[:type],
                        "ElementId"  => (PanelTypes.na_row(config, item[:type]) || {})["ElementId"],
                        "Station_mm" => item[:s0].round(2),
                        "Width_mm"   => item[:width].round(2)
                    }
                end
            end
            rows
        end
        private_class_method :na_place_spans
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Cabinet Infill Blocks
# -----------------------------------------------------------------------------

        # SUB FUNCTION | Stand a Cabinet Infill Block as Tall as the Unit Beside It
        # ------------------------------------------------------------
        # The resolver gives every infill block the run's Infill Height (a
        # base unit's 870), because it does not know the units' heights. A
        # block beside a 2120 wardrobe stood 870 tall (16-Nov-2026), so here,
        # with the elements built, each block takes the top of the nearest
        # span on its leg. A block with no span beside it keeps the setting.
        def self.na_fit_infill_heights!(layout, type_values)
            return if layout[:settings][:frames]
            resolver = Na__AssemblyStudio::Na__InteriorCabinetrySystem::Na__LayoutResolver
            tops     = type_values.transform_values do |values|
                effective = resolver.na_effective(values)
                effective[:z_base] + effective[:height]
            end
            layout[:legs].each do |leg|
                items = Array(leg[:items])
                items.each_with_index do |item, index|
                    next unless item[:kind] == Defaults::NA_ITEM_COLUMN && item[:role] == Defaults::NA_COLUMN_INFILL
                    beside = (items[0...index].reverse + items[(index + 1)..]).find { |other| other[:kind] == Defaults::NA_ITEM_SPAN }
                    item[:z1] = tops[beside[:type]] if beside && tops[beside[:type]]
                end
            end
        end
        private_class_method :na_fit_infill_heights!
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Cabinet Corner Units
# -----------------------------------------------------------------------------

        # SUB FUNCTION | An L-Shaped Corner Unit in Every Corner That Takes One
        # ------------------------------------------------------------
        # Styled from the panel type nearest the corner on the arriving leg
        # (else any type on the run).
        # @return [Integer] how many were built
        def self.na_build_corner_units(entities, layout, type_values)
            corners = layout[:corners].select { |corner| corner[:kind] == Defaults::NA_CORNER_UNIT }
            return 0 if corners.empty?

            holder = entities.grep(Sketchup::Group).find { |group| group.name == ColumnBuilder::NA_CORNERS_GROUP }
            unless holder
                holder      = entities.add_group
                holder.name = ColumnBuilder::NA_CORNERS_GROUP
            end
            corners.each do |corner|
                leg_in    = layout[:legs][corner[:leg_in]]
                neighbour = Array(leg_in[:items]).reverse.find { |item| item[:kind] == Defaults::NA_ITEM_SPAN }
                values    = neighbour ? type_values[neighbour[:type]] : type_values.values.first
                CornerUnitBuilder.na_build(holder.entities, corner, leg_in, values, "Na__RunCorner__C#{corner[:index] + 1}__CornerUnit")
            end
            corners.length
        end
        private_class_method :na_build_corner_units
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__GeometryEngine
end # module Na__AssemblyRunSystem
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
