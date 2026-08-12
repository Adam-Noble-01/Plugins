# =============================================================================
# VALE LANTERN IMPORTER - MODEL COMPOSER
# =============================================================================
#
# FILE       : Na__ValeLantern__Importer__ModelComposer__.rb
# NAMESPACE  : Na__ValeLantern::Na__Importer
# MODULE     : Na__ModelComposer
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Turn a validated payload into the container hierarchy in the model.
#
# DESCRIPTION:
# - Owns the SHAPE of the imported model and nothing about how a face is made.
#   The prism and mesh builders make geometry; this file decides what goes
#   inside what and what it is called.
# - Three levels, and no more:
#
#       ValeLantern__3010__Kitchen_Lantern      one container for the whole lantern
#         01__BaseAssembly                      one container per assembly
#           HeadBeam__Front                     one container per physical part
#           HeadBeam__Right
#           ...
#
#   Three is enough to select a whole lantern, a whole system or one length of
#   head beam, and shallow enough that the outliner is still readable. A fourth
#   level would be nesting for its own sake.
#
# -----------------------------------------------------------------------------
#
# WHY EVERY LEVEL IS A COMPONENT AND NOT A GROUP:
#
# A group and a component are the same object underneath - a group IS a
# ComponentDefinition carrying one instance with group? set true - but three
# differences decide it here:
#
#   1  SHARING. A definition can carry many instances that genuinely share one
#      copy of the geometry. Four hip beams become one definition and four
#      placements: one hip's faces in the file rather than four, and one place to
#      edit if a modeller wants to change all four. A group cannot do this;
#      SketchUp silently makes a copied group unique the moment it is edited.
#
#   2  IDENTITY. A component appears in the Component browser by name, can be
#      counted and reported there, and can be swapped. A group appears nowhere.
#
#   3  REGENERATION, which is what makes the reload possible at all. A
#      definition's contents can be replaced wholesale while every instance keeps
#      its own transform. That IS regenerating a lantern in place: clear the root
#      definition, build the new payload into it, and the lantern and every copy
#      the user has made update where they stand.
#
# Every level is switchable back to a group in the plugin config, because a part
# that has come out wrong is easier to pick apart as a group.
#
# -----------------------------------------------------------------------------
#
# WHY THE WHOLE IMPORT IS ONE OPERATION:
#
# start_operation with the disable-UI flag set turns four hundred separate
# container creations into one undo step and stops SketchUp redrawing between
# each of them. On a divided lantern that is the difference between a couple of
# seconds and most of a minute. It also means a failure part way through can
# abort the whole thing and leave the model exactly as it was, rather than
# leaving half a lantern for the user to clean up by hand.
#
# The REBUILD path does not open its own operation. Na__LanternReloader has to
# clear the old geometry, sweep the definitions it left behind and build the new
# payload as one undoable step, so the operation belongs to the caller there.
#
# NAMING CONVENTION:
# - Importer namespace Na__Importer / na_ prefixes.
#
# =============================================================================

require 'sketchup.rb'

module Na__ValeLantern
    module Na__Importer
        module Na__ModelComposer

# -----------------------------------------------------------------------------
# REGION | Module References and Constants
# -----------------------------------------------------------------------------

            DebugTools         = Na__ValeLantern::Na__Importer::Na__DebugTools
            PayloadReader      = Na__ValeLantern::Na__Importer::Na__PayloadReader
            TagManager         = Na__ValeLantern::Na__Importer::Na__TagManager
            MaterialManager    = Na__ValeLantern::Na__Importer::Na__MaterialManager
            ConfigLoader       = Na__ValeLantern::Na__Importer::Na__ConfigLoader
            DefinitionRegistry = Na__ValeLantern::Na__Importer::Na__DefinitionRegistry
            PrismBuilder       = Na__ValeLantern::Na__Importer::Na__PrismBuilder
            MeshBuilder        = Na__ValeLantern::Na__Importer::Na__MeshBuilder
            LineBuilder        = Na__ValeLantern::Na__Importer::Na__LineBuilder

            NA_ATTRIBUTE_DICTIONARY = 'VghLantern'.freeze
            NA_OPERATION_NAME       = 'Import Vale Lantern'.freeze
            NA_KIND_PRISM           = 'prism'.freeze
            NA_KIND_INSTANCE        = 'instance'.freeze
            NA_KIND_LINEWORK        = 'linework'.freeze

            NA_ROLE_SETTING_OUT     = 'settingOut'.freeze                                           # <-- Assemblies carrying this Role are construction linework, not metal

            NA_RECORD_ROOT          = 'ValeLanternRoot'.freeze
            NA_RECORD_ASSEMBLY      = 'ValeLanternAssembly'.freeze
            NA_RECORD_PART_GROUP    = 'ValeLanternPartGroup'.freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Composition — Public API
# -----------------------------------------------------------------------------

            # FUNCTION | Build one validated payload into the active model
            # ------------------------------------------------------------
            # @param payload [Hash] A payload the reader has already validated
            # @param choices [Hash] { :BuildModel, :BuildSettingOut, :SourceFilePath }
            # @return [Sketchup::ComponentInstance, Sketchup::Group, nil]
            #         The root lantern container, or nil
            def self.na_compose(payload, choices = {})
                model = Sketchup.active_model
                return nil unless model

                model_block = payload['Model']
                wanted      = na_resolve_choices(choices)
                assemblies  = na_admitted_assemblies(model_block['Assemblies'], wanted)

                if assemblies.empty?
                    DebugTools.na_error('Nothing was selected to build.')
                    return nil
                end

                DebugTools.na_reset_tally
                model.start_operation(NA_OPERATION_NAME, true)

                begin
                    root_definition, root_container = na_create_root(model, model_block)
                    if root_definition.nil? || root_container.nil?
                        model.abort_operation
                        DebugTools.na_error('The root lantern container could not be created.')
                        return nil
                    end

                    na_fill_root(model, root_definition, root_container, payload, assemblies, wanted)

                    model.commit_operation
                    DebugTools.na_report_summary(na_expected_for_choices(assemblies))
                    root_container

                rescue StandardError => e
                    model.abort_operation
                    DebugTools.na_error("Import aborted (#{e.class}): #{e.message}")
                    DebugTools.na_error(e.backtrace.first(6).join("\n    ")) if e.backtrace
                    nil
                end
            end
            # ---------------------------------------------------------------

            # FUNCTION | Build a payload into an EXISTING root definition
            # ------------------------------------------------------------
            # The reload path. Assumes the caller has already opened an operation,
            # emptied the definition and swept the definitions the previous build
            # left behind, because all three have to succeed or fail together with
            # this and the caller is the only one that can see all four.
            #
            # @param root_definition [Sketchup::ComponentDefinition] Emptied already
            # @param root_container [Sketchup::ComponentInstance, Sketchup::Group]
            #        One instance of it, for the identity stamps
            # @param payload [Hash]
            # @param choices [Hash]
            # @return [Integer, nil] The payload part count that was attempted
            def self.na_rebuild(root_definition, root_container, payload, choices = {})
                model = Sketchup.active_model
                return nil unless model
                return nil unless root_definition && !root_definition.deleted?

                model_block = payload['Model']
                wanted      = na_resolve_choices(choices)
                assemblies  = na_admitted_assemblies(model_block['Assemblies'], wanted)

                if assemblies.empty?
                    DebugTools.na_error('Nothing was selected to build.')
                    return nil
                end

                na_fill_root(model, root_definition, root_container, payload, assemblies, wanted)
                na_expected_for_choices(assemblies)
            end
            # ---------------------------------------------------------------

            # HELPER FUNCTION | Normalise the caller's build choices
            # ------------------------------------------------------------
            # Defaults to the metal alone, which is what an import means to
            # anyone who has not asked for anything else. Both entry points run
            # their choices through here, so a reload can never interpret the
            # same hash differently from an import.
            def self.na_resolve_choices(choices)
                given = choices.is_a?(Hash) ? choices : {}
                {
                    :BuildModel      => given.fetch(:BuildModel, true) != false,
                    :BuildSettingOut => given.fetch(:BuildSettingOut, false) == true,
                    :SourceFilePath  => given[:SourceFilePath]
                }
            end
            private_class_method :na_resolve_choices

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal — Shared Fill Path
# -----------------------------------------------------------------------------

            # HELPER FUNCTION | Everything both an import and a reload do
            # ------------------------------------------------------------
            # Tag and material tables, mesh definitions, the registry reset, the
            # identity stamps and the assemblies themselves. Kept in one place so a
            # reload can never drift into building something an import would not.
            def self.na_fill_root(model, root_definition, root_container, payload, assemblies, wanted)
                model_block = payload['Model']
                options     = model_block['Options'].is_a?(Hash) ? model_block['Options'] : {}

                na_apply_model_options(model, options)

                TagManager.na_prepare_tags(model_block['Tags'])
                MaterialManager.na_prepare_materials(model_block['Materials'])
                MeshBuilder.na_prepare_definitions(model_block['Definitions']) if wanted[:BuildModel]

                DefinitionRegistry.na_begin_import(root_definition.name)                            # <-- Every definition this build creates sorts under the lantern's own name

                na_stamp_root(root_definition, payload, model_block, wanted)
                na_stamp_root(root_container,  payload, model_block, wanted)                        # <-- Both: the definition is what a reload finds, the instance is what Entity Info shows

                na_build_assemblies(model, root_definition, assemblies, options)
                na_report_sharing
            end
            private_class_method :na_fill_root

            # HELPER FUNCTION | Report what definition sharing achieved
            # ------------------------------------------------------------
            # Worth a headline line rather than a detail: it is the one number
            # that says whether the four hips of this lantern actually collapsed
            # onto one definition or quietly did not.
            def self.na_report_sharing
                return unless ConfigLoader.na_share_definitions?

                shared = DefinitionRegistry.na_shared_hit_count
                DebugTools.na_info(
                    "Part definitions: #{DefinitionRegistry.na_definition_count} distinct, " \
                    "#{shared} placement(s) shared (#{DefinitionRegistry.na_mirror_hit_count} mirrored)"
                )
            end
            private_class_method :na_report_sharing

            # HELPER FUNCTION | The assemblies the choices admit
            # ------------------------------------------------------------
            # Filtered on the assembly's own Role rather than on its key, so the
            # exporter can add a second class of linework later without this
            # plugin needing to learn its name.
            def self.na_admitted_assemblies(assemblies, wanted)
                return [] unless assemblies.is_a?(Array)

                assemblies.select do |assembly|
                    if assembly['Role'].to_s == NA_ROLE_SETTING_OUT
                        wanted[:BuildSettingOut]
                    else
                        wanted[:BuildModel]
                    end
                end
            end
            private_class_method :na_admitted_assemblies

            # HELPER FUNCTION | How many parts the admitted assemblies carry
            # ------------------------------------------------------------
            # The payload's own total counts everything it holds, which would
            # report a setting out only import as having dropped four hundred
            # parts. Counting what was actually asked for is the honest figure.
            def self.na_expected_for_choices(assemblies)
                assemblies.inject(0) do |sum, assembly|
                    parts = assembly['Parts']
                    sum + (parts.is_a?(Array) ? parts.length : 0)
                end
            end
            private_class_method :na_expected_for_choices

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal — Model Level Options
# -----------------------------------------------------------------------------

            # HELPER FUNCTION | Apply the model wide options the payload asks for
            # ------------------------------------------------------------
            # Both of these edit the user's own document rather than the lantern
            # inside it, so both default OFF in the exporter and are only ever on
            # because somebody turned them on.
            def self.na_apply_model_options(model, options)
                if options['SetModelUnitsToMillimetres'] == true
                    begin
                        model.options['UnitsOptions']['LengthUnit']   = Length::Millimeter
                        model.options['UnitsOptions']['LengthFormat'] = Length::Decimal
                        DebugTools.na_info('Model length units set to millimetres.')
                    rescue StandardError => e
                        DebugTools.na_warn("Model units could not be set: #{e.message}")
                    end
                end

                return unless options['PurgeUnusedBeforeImport'] == true

                begin
                    model.definitions.purge_unused
                    model.materials.purge_unused
                    model.layers.purge_unused
                    DebugTools.na_info('Unused definitions, materials and tags purged.')
                rescue StandardError => e
                    DebugTools.na_warn("Purge refused: #{e.message}")
                end
            end
            private_class_method :na_apply_model_options

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal — Container Hierarchy
# -----------------------------------------------------------------------------

            # HELPER FUNCTION | Open a container at one level of the hierarchy
            # ------------------------------------------------------------
            # The one place the component-versus-group decision is made, so no
            # caller carries a branch for it.
            #
            # The GROUP branch still returns a definition - every group has one -
            # which is what lets a lantern imported with RootAsComponent off still
            # be reloaded in place later.
            #
            # @return [Array] [container, entities, definition]
            def self.na_open_container(model, parent_entities, level, definition_name, instance_name, use_root_token = true)
                unless ConfigLoader.na_container_is_component?(level)
                    group      = parent_entities.add_group
                    group.name = instance_name.to_s
                    return [group, group.entities, na_definition_of(group)]
                end

                definition = DefinitionRegistry.na_create_container_definition(model, definition_name, use_root_token)
                return [nil, nil, nil] if definition.nil?

                instance = parent_entities.add_instance(definition, Geom::Transformation.new)
                if instance.nil?
                    DefinitionRegistry.na_discard_definition(model, definition)
                    return [nil, nil, nil]
                end

                instance.name = instance_name.to_s
                [instance, definition.entities, definition]

            rescue StandardError => e
                DebugTools.na_warn("Container '#{instance_name}' could not be created: #{e.message}")
                [nil, nil, nil]
            end
            private_class_method :na_open_container

            # HELPER FUNCTION | Remove a container that produced nothing
            # ------------------------------------------------------------
            # SketchUp counts an empty container as an entity the user then has to
            # find and delete, and an empty COMPONENT leaves an entry in the
            # Component browser as well, so both halves go.
            def self.na_close_empty_container(model, container, definition)
                container.erase! if container && container.valid?
                return if definition.nil?
                return if definition.deleted?
                return if definition.group?                                                         # <-- SketchUp reclaims a group's definition itself

                DefinitionRegistry.na_discard_definition(model, definition)
            rescue StandardError => e
                DebugTools.na_detail("Empty container could not be removed: #{e.message}")
            end
            private_class_method :na_close_empty_container

            # HELPER FUNCTION | The definition behind a group or an instance
            # ------------------------------------------------------------
            def self.na_definition_of(entity)
                return nil unless entity
                return nil unless entity.respond_to?(:definition)
                entity.definition
            rescue StandardError
                nil
            end
            private_class_method :na_definition_of

            # HELPER FUNCTION | Create the single top level lantern container
            # ------------------------------------------------------------
            # The root definition's name is the payload's RootGroupName, and it is
            # the token every other definition this import creates is prefixed
            # with, so one lantern's thirty definitions sort together in the
            # Component browser under the lantern they belong to.
            #
            # @return [Array] [definition, container]
            def self.na_create_root(model, model_block)
                root_name = model_block['RootGroupName'].to_s
                container, _entities, definition = na_open_container(
                    model, model.active_entities, :Root, root_name, root_name, false
                )                                                                                   # <-- use_root_token false: the root's name IS the token

                return [nil, nil] if container.nil?

                DebugTools.na_info("Root container: #{definition ? definition.name : root_name}")
                [definition, container]
            end
            private_class_method :na_create_root

            # HELPER FUNCTION | Write the lantern identity onto one entity
            # ------------------------------------------------------------
            # Stamped with the project and lantern identity so a model holding
            # three lanterns can be read back to the job each one came from
            # without anyone having to trust the container name.
            #
            # Written to the DEFINITION and to the INSTANCE. The definition is what
            # a reload searches for, and searching definitions rather than walking
            # every entity in the model is what makes finding a nested lantern
            # cheap. The instance is what Entity Info shows when somebody clicks
            # the lantern, which is where a modeller actually reads it.
            def self.na_stamp_root(entity, payload, model_block, wanted)
                return unless entity && !entity.deleted?

                meta    = payload['Meta']    || {}
                project = payload['Project'] || {}
                lantern = payload['Lantern'] || {}

                na_stamp(entity, 'RecordType',    NA_RECORD_ROOT)
                na_stamp(entity, 'SchemaVersion', meta['SchemaVersion'])
                na_stamp(entity, 'AppVersion',    meta['AppVersion'])
                na_stamp(entity, 'ExportedAtIso', meta['ExportedAtIso'])
                na_stamp(entity, 'ExportedBy',    meta['ExportedBy'])
                na_stamp(entity, 'ProjectCode',   project['Code'])
                na_stamp(entity, 'ProjectName',   project['Name'])
                na_stamp(entity, 'ClientName',    project['ClientName'])
                na_stamp(entity, 'LanternId',     lantern['Id'])
                na_stamp(entity, 'LanternTitle',  lantern['Title'])
                na_stamp(entity, 'RoofForm',      lantern['RoofForm'])
                na_stamp(entity, 'WidthMm',       lantern['WidthMm'])
                na_stamp(entity, 'DepthMm',       lantern['DepthMm'])
                na_stamp(entity, 'PitchDegrees',  lantern['PitchDegrees'])
                na_stamp(entity, 'Quantity',      lantern['Quantity'])

                na_stamp(entity, 'BuiltModel',      wanted[:BuildModel])
                na_stamp(entity, 'BuiltSettingOut', wanted[:BuildSettingOut])
                na_stamp(entity, 'BuiltAtLocal',    na_local_timestamp)

                return unless ConfigLoader.na_remembers_source_file?
                na_stamp(entity, 'SourceFilePath', wanted[:SourceFilePath])                         # <-- What the reload picker opens on
            end
            private_class_method :na_stamp_root

            # HELPER FUNCTION | A local timestamp, without requiring 'time'
            # ------------------------------------------------------------
            def self.na_local_timestamp
                Time.now.strftime('%Y-%m-%d %H:%M:%S')
            rescue StandardError
                nil
            end
            private_class_method :na_local_timestamp

            # HELPER FUNCTION | Build every assembly container and the parts inside it
            # ------------------------------------------------------------
            # An assembly that produced nothing is erased again rather than left
            # as an empty container. The payload having sent it is still recorded
            # in the console.
            def self.na_build_assemblies(model, root_definition, assemblies, options)
                return unless assemblies.is_a?(Array)

                sorted = assemblies.sort_by { |assembly| assembly['SortOrder'].to_i }

                sorted.each do |assembly|
                    parts = assembly['Parts']
                    name  = assembly['Name'].to_s

                    if !parts.is_a?(Array) || parts.empty?
                        DebugTools.na_info("Assembly '#{name}': nothing to build.")
                        next
                    end

                    container, entities, definition = na_open_container(
                        model, root_definition.entities, :Assembly, name, name
                    )
                    if container.nil?
                        DebugTools.na_warn("Assembly '#{name}': container could not be created - skipped.")
                        next
                    end

                    na_stamp(container, 'RecordType',   NA_RECORD_ASSEMBLY)
                    na_stamp(container, 'AssemblyKey',  assembly['Key'])
                    na_stamp(container, 'AssemblyRole', assembly['Role'])
                    na_stamp_all(container, assembly['Attributes'])                                 # <-- Where the setting out datum checks land

                    built = na_build_parts(model, entities, name, parts, options)

                    if built.zero?
                        DebugTools.na_warn("Assembly '#{name}': every part was refused - container removed.")
                        na_close_empty_container(model, container, definition)
                    else
                        DebugTools.na_info("Assembly '#{name}': #{built} of #{parts.length} part(s) built.")
                    end
                end
            end
            private_class_method :na_build_assemblies

            # HELPER FUNCTION | Build every part of one assembly
            # ------------------------------------------------------------
            # A part of an unknown Kind is counted and named rather than raised.
            # That is what lets a payload written by a newer application version
            # still import everything this plugin does understand.
            #
            # A part carrying a GroupKey is nested one level deeper, in a container
            # created on first use. That is what turns forty glaze bar centrelines
            # into one collapsible outliner entry instead of forty siblings, and it
            # is driven entirely by the data - this file carries no list of what
            # the intermediate containers should be.
            def self.na_build_parts(model, assembly_entities, assembly_name, parts, options)
                built     = 0
                subgroups = {}

                parts.each do |part|
                    next unless part.is_a?(Hash)

                    entities = na_entities_for_part(model, assembly_entities, assembly_name, part, subgroups)
                    next if entities.nil?

                    case part['Kind'].to_s
                    when NA_KIND_PRISM
                        built += 1 if PrismBuilder.na_build_prism(entities, part, options)
                    when NA_KIND_INSTANCE
                        built += 1 if MeshBuilder.na_place_instance(entities, part)
                    when NA_KIND_LINEWORK
                        built += 1 if LineBuilder.na_build_linework(entities, part)
                    else
                        DebugTools.na_record_failure(part['Name'].to_s, "unknown part kind '#{part['Kind']}'")
                    end
                end

                na_prune_empty_subgroups(model, subgroups)
                built
            end
            private_class_method :na_build_parts

            # HELPER FUNCTION | The entities a part should be built into
            # ------------------------------------------------------------
            # The assembly's own entities when the part names no group, or a
            # lazily created intermediate container when it does.
            def self.na_entities_for_part(model, assembly_entities, assembly_name, part, subgroups)
                group_key = part['GroupKey']
                return assembly_entities if group_key.nil? || group_key.to_s.empty?

                key = group_key.to_s
                unless subgroups.key?(key)
                    group_name = (part['GroupName'] || key).to_s
                    container, entities, definition = na_open_container(
                        model, assembly_entities, :PartGroup, "#{assembly_name}__#{group_name}", group_name
                    )
                    if container.nil?
                        DebugTools.na_warn("Part group '#{group_name}': container could not be created - parts go alongside it.")
                        subgroups[key] = nil
                        return assembly_entities
                    end

                    na_stamp(container, 'RecordType', NA_RECORD_PART_GROUP)
                    na_stamp(container, 'GroupKey',   key)
                    subgroups[key] = { :Container => container, :Entities => entities, :Definition => definition }
                end

                record = subgroups[key]
                record.nil? ? assembly_entities : record[:Entities]
            end
            private_class_method :na_entities_for_part

            # HELPER FUNCTION | Remove intermediate containers nothing was built into
            # ------------------------------------------------------------
            # A container is created before its first part is attempted, so a class
            # whose every part was refused would otherwise leave an empty one
            # behind for the user to find and delete.
            def self.na_prune_empty_subgroups(model, subgroups)
                subgroups.each_value do |record|
                    next if record.nil?

                    container = record[:Container]
                    next unless container && container.valid?
                    next unless record[:Entities] && record[:Entities].length.zero?

                    DebugTools.na_detail("Removed empty container '#{container.name}'")
                    na_close_empty_container(model, container, record[:Definition])
                end
            end
            private_class_method :na_prune_empty_subgroups

            # HELPER FUNCTION | Write one attribute, tolerating a refusal
            # ------------------------------------------------------------
            def self.na_stamp(entity, key, value)
                return if value.nil?
                entity.set_attribute(NA_ATTRIBUTE_DICTIONARY, key, value)
            rescue StandardError => e
                DebugTools.na_detail("Attribute '#{key}' refused: #{e.message}")
            end
            private_class_method :na_stamp

            # HELPER FUNCTION | Write a whole attribute block
            # ------------------------------------------------------------
            def self.na_stamp_all(entity, attributes)
                return unless attributes.is_a?(Hash)
                attributes.each { |key, value| na_stamp(entity, key.to_s, value) }
            end
            private_class_method :na_stamp_all

# endregion -------------------------------------------------------------------

        end
    end
end
