# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - ASSEMBLY RUN SYSTEM - COLUMN LIBRARY
# =============================================================================
#
# FILE       : Na__AssemblyStudio__AssemblyRun__ColumnLibrary__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__AssemblyRunSystem
# MODULE     : Na__ColumnLibrary
# AUTHOR     : Noble Architecture
# PURPOSE    : Adam's library columns inside the plugin: where their files
#              are, loading one into the model, and making the height variant
#              a run needs (the shaft stretched, base and capital kept).
# CREATED    : 16-Nov-2026 (V2.7.0)
#
# THE FILES
# - 04__Data__AssetLibrary/AssemblyRun__Columns__/ holds a copy of each
#   library column's .skp (the 260 and 290 standard columns, inline and
#   corner) and an index naming the library file each came from. The library
#   keeps the master; the plugin loads its own copy so it works on any PC.
#
# HEIGHT VARIANTS (the rule of the Vale orangery work, 06-Nov-2026)
# - Every library column is 2000 tall. Another height is its own definition,
#   named <library name>h<H>: every vertex above z 1000 moves up or down by
#   H - 2000, so the base and capital keep their shape.
# - THE TRAP: ComponentInstance#make_unique gives a copy that still SHARES
#   its nested groups' definitions with the source, and a later load of the
#   same file reuses those by GUID. Stretching the copy as it stands would
#   stretch every later load. Each nested group is made unique first, while
#   the source still holds its own instances.
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__DebugTools__'
require_relative '../02__AppData/Na__AssemblyStudio__AppData__ConfigLoader__'
require_relative 'Na__AssemblyStudio__AssemblyRun__Defaults__'

module Na__AssemblyStudio
module Na__AssemblyRunSystem
    module Na__ColumnLibrary

# -----------------------------------------------------------------------------
# REGION | Module References
# -----------------------------------------------------------------------------

        DebugTools   = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools
        ConfigLoader = Na__AssemblyStudio::Na__AppData::Na__ConfigLoader
        Defaults     = Na__AssemblyStudio::Na__AssemblyRunSystem::Na__Defaults

        NA_MODULES_ROOT = File.expand_path('../..', __dir__)

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Files
# -----------------------------------------------------------------------------

        # FUNCTION | The Folder Holding the Column Files
        # ------------------------------------------------------------
        def self.na_folder
            root   = ConfigLoader.na_get_or("04__Data__AssetLibrary", 'assetLibrary', 'rootFolder')
            bucket = ConfigLoader.na_get_or(Defaults::NA_LIBRARY_COLUMN_FOLDER, 'assetLibrary', 'assemblyRun', 'columns')
            File.join(NA_MODULES_ROOT, root.to_s, bucket.to_s)
        rescue StandardError
            File.join(NA_MODULES_ROOT, "04__Data__AssetLibrary", Defaults::NA_LIBRARY_COLUMN_FOLDER)
        end
        # ---------------------------------------------------------------

        # FUNCTION | The File of One Column
        # ------------------------------------------------------------
        # @param kind [String] "Vale260" | "Vale290"
        # @param role [Symbol] :inline | :corner
        # @return [String] absolute path
        def self.na_file(kind, role)
            column = Defaults::NA_LIBRARY_COLUMNS[kind]
            raise ArgumentError, "'#{kind}' is not a library column (#{Defaults::NA_LIBRARY_COLUMNS.keys.join(', ')})." unless column
            File.join(na_folder, role == :corner ? column[:corner_file] : column[:inline_file])
        end
        # ---------------------------------------------------------------

        # FUNCTION | Every Library Column, as the Dialog and Agents List Them
        # ------------------------------------------------------------
        # @return [Array<Hash>] string-keyed rows
        def self.na_list
            Defaults::NA_LIBRARY_COLUMNS.map do |kind, column|
                inline = na_file(kind, :inline)
                corner = na_file(kind, :corner)
                {
                    "kind"          => kind,
                    "label"         => column[:label],
                    "width_mm"      => column[:width_mm],
                    "corner_leg_mm" => column[:corner_leg_mm],
                    "backing_mm"    => column[:backing_mm],
                    "proud_mm"      => column[:proud_mm],
                    "inline_file"   => File.basename(inline),
                    "corner_file"   => File.basename(corner),
                    "available"     => File.exist?(inline) && File.exist?(corner)
                }
            end
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Height Variants
# -----------------------------------------------------------------------------

        # FUNCTION | A Library Column at a Height, as Its Own Definition
        # ------------------------------------------------------------
        # Call inside the caller's operation. A variant already in the model
        # is used again; the library file's own definition is never edited.
        # @param height_mm [Float] the height the column must stand
        # @return [Sketchup::ComponentDefinition]
        def self.na_variant(model, kind, role, height_mm)
            path = na_file(kind, role)
            raise "The column file is missing: #{path}" unless File.exist?(path)
            if height_mm < Defaults::NA_LIBRARY_COLUMN_MIN_MM
                raise "A library column cannot be #{height_mm.round}mm tall: below #{Defaults::NA_LIBRARY_COLUMN_MIN_MM.round} its shaft folds into its base."
            end

            had_backer_tag = !model.layers[Defaults::NA_COLUMN_BACKER_TAG].nil?
            before         = model.definitions.to_a
            source         = model.definitions.load(path)
            fresh          = !before.include?(source)
            na_hide_new_backer_tag(model) unless had_backer_tag

            name    = "#{source.name.sub(/#\d+\z/, '').sub(/_*\z/, '__')}h#{height_mm.round}"
            variant = model.definitions[name]
            if variant && (na_height_mm(variant) - height_mm).abs < 0.5
                model.definitions.remove(source) if fresh && source.instances.empty?
                return variant
            end

            library_height = na_height_mm(source)
            unless (library_height - Defaults::NA_LIBRARY_COLUMN_HEIGHT_MM).abs < 0.5
                raise "#{source.name} is #{library_height.round(1)}mm tall in this model, not the library's #{Defaults::NA_LIBRARY_COLUMN_HEIGHT_MM.round}: " \
                      "an edited copy carries the library name. Purge or rename it, then build again."
            end
            variant = na_copy_definition(model, source, fresh)
            variant.name = name
            na_stretch(variant, height_mm - na_height_mm(variant))
            got = na_height_mm(variant)
            raise "#{name} came out #{got.round(2)}mm tall, not #{height_mm}." unless (got - height_mm).abs < 0.05
            DebugTools.na_debug_geometry("Library column variant #{name}")
            variant
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | A Definition's Height in mm
        # ------------------------------------------------------------
        def self.na_height_mm(definition)
            bounds = definition.bounds
            (bounds.max.z - bounds.min.z).to_mm
        end
        private_class_method :na_height_mm
        # ---------------------------------------------------------------

        # HELPER FUNCTION | A Deep, Unshared Copy of the Library Definition
        # ------------------------------------------------------------
        # Two instances are placed for a moment in the active context: one
        # keeps the source's nested groups in use, the other is made unique.
        def self.na_copy_definition(model, source, fresh)
            entities = model.active_entities
            keeper   = entities.add_instance(source, Geom::Transformation.new)
            working  = entities.add_instance(source, Geom::Transformation.new)
            working.make_unique
            copy = working.definition
            raise "make_unique did not copy #{source.name}." if copy == source

            na_unique_deep(copy.entities)
            shared = na_nested_definitions(copy.entities) & na_nested_definitions(source.entities)
            raise "#{copy.name}: its nested groups are still shared with the library column." unless shared.empty?

            working.erase!
            keeper.erase!
            model.definitions.remove(source) if fresh && source.instances.empty?
            copy
        end
        private_class_method :na_copy_definition
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Make Every Nested Group Unique, at Any Depth
        # ------------------------------------------------------------
        def self.na_unique_deep(entities)
            entities.grep(Sketchup::Group).each do |group|
                group.make_unique if group.definition.instances.length > 1
                na_unique_deep(group.definition.entities)
            end
        end
        private_class_method :na_unique_deep
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Every Group Definition Nested in Some Entities
        # ------------------------------------------------------------
        def self.na_nested_definitions(entities)
            entities.grep(Sketchup::Group).flat_map { |group| [group.definition] + na_nested_definitions(group.definition.entities) }
        end
        private_class_method :na_nested_definitions
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Move Everything Above the Stretch Line by dz
        # ------------------------------------------------------------
        def self.na_stretch(definition, dz_mm)
            return if dz_mm.abs < 0.01
            if definition.entities.grep(Sketchup::Face).any? || definition.entities.grep(Sketchup::ComponentInstance).any?
                raise "#{definition.name} holds loose faces or nested components: its shaft cannot be stretched safely."
            end
            na_stretch_groups(definition.entities, Geom::Transformation.new, dz_mm, definition.name)
        end
        private_class_method :na_stretch
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Stretch the Groups of One Level, Then Their Children
        # ------------------------------------------------------------
        def self.na_stretch_groups(entities, to_column, dz_mm, label)
            line = Defaults::NA_LIBRARY_COLUMN_STRETCH_Z_MM
            entities.grep(Sketchup::Group).each do |group|
                group_to_column = to_column * group.transformation
                inner           = group.entities
                raise "#{label}: a component nested in the column stops its shaft being stretched." if inner.grep(Sketchup::ComponentInstance).any?

                vertices = inner.grep(Sketchup::Edge).flat_map(&:vertices).uniq
                unless vertices.empty?
                    heights   = vertices.map { |vertex| vertex.position.transform(group_to_column).z.to_mm }
                    moving    = vertices.zip(heights).select { |_vertex, z| z > line }.map(&:first)
                    fixed_top = heights.select { |z| z <= line }.max || -1.0e9
                    low_moved = heights.select { |z| z > line }.min || 1.0e9
                    raise "#{label}: a stretch of #{dz_mm.round}mm would fold the shaft." if low_moved + dz_mm <= fixed_top + 1.0
                    unless moving.empty?
                        vector = Geom::Vector3d.new(0, 0, dz_mm.mm).transform(group_to_column.inverse)
                        inner.transform_by_vectors(moving, Array.new(moving.length, vector))
                    end
                end
                na_stretch_groups(inner, group_to_column, dz_mm, label)
            end
        end
        private_class_method :na_stretch_groups
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Hide the Backers' Tag When Loading Just Made It
        # ------------------------------------------------------------
        # Adam keeps the column backers hidden in his models: they are red
        # utility solids on the framework face. A tag the model already had
        # is left as he set it.
        def self.na_hide_new_backer_tag(model)
            tag = model.layers[Defaults::NA_COLUMN_BACKER_TAG]
            tag.visible = false if tag
        end
        private_class_method :na_hide_new_backer_tag
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__ColumnLibrary
end # module Na__AssemblyRunSystem
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
