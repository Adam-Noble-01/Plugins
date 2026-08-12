# =============================================================================
# VALE LANTERN IMPORTER - LINE BUILDER
# =============================================================================
#
# FILE       : Na__ValeLantern__Importer__LineBuilder__.rb
# NAMESPACE  : Na__ValeLantern::Na__Importer
# MODULE     : Na__LineBuilder
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Build one payload linework part into a named group of edges.
#
# DESCRIPTION:
# - The setting out counterpart of the prism builder. Datums, construction
#   triangles and member centrelines arrive as polylines and leave as edges in a
#   named, tagged group.
# - Edges only. No faces are made and no material is applied, because a datum is
#   not a thing that has a surface and an edge takes its colour from its tag.
#
# -----------------------------------------------------------------------------
#
# WHY EDGES RATHER THAN CONSTRUCTION GUIDES:
#
# SketchUp has a purpose built construction geometry type - Sketchup::ConstructionLine,
# what the UI calls a guide - and at first glance a datum is exactly that. It is
# not the right choice here, for three reasons:
#
#   1  A guide cannot carry a colour. The whole value of this linework is that a
#      ridge datum is red, an eaves datum magenta and a hip triangle green, so a
#      reviewer reads the class before reading the label. Guides are all one
#      colour and always will be.
#
#   2  Guides are wiped as a set. Edit > Delete Guides is a single command with
#      no filter, so one careless click removes every datum in the model along
#      with the user's own working guides.
#
#   3  Tags carry dash patterns. An edge on a tag styled Dash Dot renders as a
#      dash dot, which is what the setting out legend shows and what a drawing
#      convention expects.
#
# An edge on a dedicated, dash styled, switchable tag gets all of that. The cost
# is that these edges are real geometry and will be picked up by a section cut or
# an export, which is exactly why they are on their own tags to switch off.
#
# -----------------------------------------------------------------------------
#
# WHY THE EDGES ARE LEFT SOFT AND SMOOTH ALONE:
#
# A closed datum ring shares its endpoints, and SketchUp will happily find a face
# in any planar closed loop the moment another edge completes it. Nothing here
# creates faces, and the group boundary stops these edges interacting with the
# metal, so a datum ring stays a ring.
#
# NAMING CONVENTION:
# - Importer namespace Na__Importer / na_ prefixes.
#
# =============================================================================

require 'sketchup.rb'

module Na__ValeLantern
    module Na__Importer
        module Na__LineBuilder

# -----------------------------------------------------------------------------
# REGION | Module References and Constants
# -----------------------------------------------------------------------------

            DebugTools         = Na__ValeLantern::Na__Importer::Na__DebugTools
            Units              = Na__ValeLantern::Na__Importer::Na__Units
            TagManager         = Na__ValeLantern::Na__Importer::Na__TagManager
            DataLibBridge      = Na__ValeLantern::Na__Importer::Na__DataLibBridge
            ConfigLoader       = Na__ValeLantern::Na__Importer::Na__ConfigLoader
            DefinitionRegistry = Na__ValeLantern::Na__Importer::Na__DefinitionRegistry

            NA_ATTRIBUTE_DICTIONARY = 'VghLantern'.freeze
            NA_MIN_POLYLINE_POINTS  = 2
            NA_POINT_MERGE_INCH     = 0.0005                                                        # <-- Below SketchUp's own tolerance; a repeated point is not an edge

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Linework Construction — Public API
# -----------------------------------------------------------------------------

            # FUNCTION | Build one linework part into a named container
            # ------------------------------------------------------------
            # A group by default, or a component when Containers.LineworkAsComponent
            # is on. Either way the edges are built in WORLD coordinates at an
            # identity transform: a datum has no section to derive a frame from and
            # nothing in a setting out set repeats, so there is no definition to
            # share and nothing to gain from a local frame.
            #
            # @param parent_entities [Sketchup::Entities] Where the container is created
            # @param part [Hash] One payload part record of Kind 'linework'
            # @return [Sketchup::Group, Sketchup::ComponentInstance, nil]
            def self.na_build_linework(parent_entities, part)
                part_name = part['Name'].to_s
                polylines = part['Polylines']

                unless polylines.is_a?(Array) && !polylines.empty?
                    DebugTools.na_record_failure(part_name, 'no polylines')
                    return nil
                end

                container, entities, definition = na_open_container(parent_entities, part_name)
                if container.nil?
                    DebugTools.na_record_failure(part_name, 'no container could be created')
                    return nil
                end

                edge_count = 0
                polylines.each do |polyline|
                    edge_count += na_build_polyline(entities, polyline)
                end

                if edge_count.zero?
                    DebugTools.na_record_failure(part_name, 'every polyline was degenerate')
                    na_discard_container(container, definition)
                    return nil
                end

                TagManager.na_apply_tag(container, part['TagKey'])
                na_paint_edges(entities, part['StyleKey'])
                na_stamp_attributes(container, part['Attributes'])

                DebugTools.na_detail("Built linework '#{part_name}' (#{edge_count} edges)")
                DebugTools.na_count('Linework groups')
                container

            rescue StandardError => e
                DebugTools.na_record_failure(part['Name'].to_s, "#{e.class}: #{e.message}")
                na_discard_container(container, definition) if defined?(container)
                nil
            end
            # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal — Container Creation
# -----------------------------------------------------------------------------

            # HELPER FUNCTION | Open a group or a component to build the edges into
            # ------------------------------------------------------------
            # @return [Array] [container, entities, definition_or_nil]
            def self.na_open_container(parent_entities, part_name)
                unless ConfigLoader.na_linework_is_component?
                    group      = parent_entities.add_group
                    group.name = part_name
                    return [group, group.entities, nil]
                end

                model = Sketchup.active_model
                return [nil, nil, nil] unless model

                definition = DefinitionRegistry.na_create_container_definition(model, part_name)
                return [nil, nil, nil] if definition.nil?

                instance = parent_entities.add_instance(definition, Geom::Transformation.new)
                if instance.nil?
                    DefinitionRegistry.na_discard_definition(model, definition)
                    return [nil, nil, nil]
                end

                instance.name = part_name
                [instance, definition.entities, definition]

            rescue StandardError => e
                DebugTools.na_detail("Linework container refused: #{e.message}")
                [nil, nil, nil]
            end
            private_class_method :na_open_container

            # HELPER FUNCTION | Remove a container that produced nothing
            # ------------------------------------------------------------
            # A component's definition has to go as well as its instance, or an
            # empty entry is left in the Component browser forever.
            def self.na_discard_container(container, definition)
                container.erase! if container && container.valid?
                return if definition.nil?

                DefinitionRegistry.na_discard_definition(Sketchup.active_model, definition)
            rescue StandardError => e
                DebugTools.na_detail("Container could not be removed: #{e.message}")
            end
            private_class_method :na_discard_container

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal — Polyline Construction
# -----------------------------------------------------------------------------

            # HELPER FUNCTION | Build one polyline as a run of edges
            # ------------------------------------------------------------
            # add_edges takes the whole point run at once and returns the edges it
            # made, which is both faster than one add_line per segment and the
            # only form that reliably shares vertices along the run.
            def self.na_build_polyline(entities, polyline)
                return 0 unless polyline.is_a?(Hash)

                points = na_convert_points(polyline['Points'])
                return 0 if points.length < NA_MIN_POLYLINE_POINTS

                points = points + [points.first] if polyline['Closed'] == true && points.length > 2

                edges = entities.add_edges(points)
                edges.is_a?(Array) ? edges.length : 0

            rescue StandardError => e
                DebugTools.na_detail("Polyline refused: #{e.message}")
                0
            end
            private_class_method :na_build_polyline

            # HELPER FUNCTION | Convert and deduplicate a millimetre point run
            # ------------------------------------------------------------
            # A construction triangle whose rise is zero - a mono pitch run at
            # zero degrees, say - collapses two of its three corners onto each
            # other. Removing the duplicate leaves a single line rather than
            # handing add_edges a zero length segment to reject.
            def self.na_convert_points(raw_points)
                return [] unless raw_points.is_a?(Array)

                cleaned = []
                raw_points.each do |triple|
                    point = Units.na_point(triple)
                    next if point.nil?

                    previous = cleaned.last
                    next if previous && previous.distance(point) < NA_POINT_MERGE_INCH
                    cleaned << point
                end

                cleaned
            end
            private_class_method :na_convert_points

            # HELPER FUNCTION | Paint every edge with its MTE construction colour
            # ------------------------------------------------------------
            # Per EDGE, not on the group. A group material cascades to faces;
            # an edge takes its colour only from edge.material, which is the
            # same call Na__EdgeUtil__PaintDeepNestedEdges makes and the reason
            # an imported datum is recognisable to that tool afterwards.
            #
            # No material means DataLib could not answer for this class. The
            # edges stay SketchUp default black, which reads as unstyled rather
            # than as the wrong datum - and the tag colour is still there for
            # anyone working in Color By Tag.
            def self.na_paint_edges(entities, style_key)
                return 0 if style_key.nil? || style_key.to_s.empty?

                model    = Sketchup.active_model
                material = DataLibBridge.na_edge_material_for(model, style_key)
                return 0 unless material

                painted = 0
                entities.grep(Sketchup::Edge).each do |edge|
                    next unless edge.valid?
                    edge.material = material
                    painted += 1
                end

                DebugTools.na_detail("Painted #{painted} edge(s) with '#{material.name}'")
                painted
            rescue StandardError => e
                DebugTools.na_detail("Edge painting refused for '#{style_key}': #{e.message}")
                0
            end
            private_class_method :na_paint_edges

            # HELPER FUNCTION | Stamp the payload attributes onto the group
            # ------------------------------------------------------------
            # This is where a hip triangle's run, rise, hypotenuse and pitch land,
            # and where a datum's level above the top of the builders upstand
            # lands. Select the group in SketchUp and the numbers are in Entity
            # Info's attribute list.
            def self.na_stamp_attributes(entity, attributes)
                return unless attributes.is_a?(Hash)

                attributes.each do |key, value|
                    next if value.nil?
                    begin
                        entity.set_attribute(NA_ATTRIBUTE_DICTIONARY, key.to_s, value)
                    rescue StandardError => e
                        DebugTools.na_detail("Attribute '#{key}' refused: #{e.message}")
                    end
                end
            end
            private_class_method :na_stamp_attributes

# endregion -------------------------------------------------------------------

        end
    end
end
