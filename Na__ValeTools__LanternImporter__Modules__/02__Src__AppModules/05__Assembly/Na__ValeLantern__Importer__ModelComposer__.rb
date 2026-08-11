# =============================================================================
# VALE LANTERN IMPORTER - MODEL COMPOSER
# =============================================================================
#
# FILE       : Na__ValeLantern__Importer__ModelComposer__.rb
# NAMESPACE  : Na__ValeLantern::Na__Importer
# MODULE     : Na__ModelComposer
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Turn a validated payload into the group hierarchy in the model.
#
# DESCRIPTION:
# - Owns the SHAPE of the imported model and nothing about how a face is made.
#   The prism and mesh builders make geometry; this file decides what goes
#   inside what and what it is called.
# - Three levels, and no more:
#
#       ValeLantern__3010__Kitchen_Lantern      one group for the whole lantern
#         01__BaseAssembly                      one group per assembly
#           HeadBeam__Front                     one group per physical part
#           HeadBeam__Right
#           ...
#
#   Three is enough to select a whole lantern, a whole system or one length of
#   head beam, and shallow enough that the outliner is still readable. A fourth
#   level would be nesting for its own sake.
#
# -----------------------------------------------------------------------------
#
# WHY THE WHOLE IMPORT IS ONE OPERATION:
#
# start_operation with the disable-UI flag set turns four hundred separate group
# creations into one undo step and stops SketchUp redrawing between each of
# them. On a divided lantern that is the difference between a couple of seconds
# and most of a minute. It also means a failure part way through can abort the
# whole thing and leave the model exactly as it was, rather than leaving half a
# lantern for the user to clean up by hand.
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

            DebugTools      = Na__ValeLantern::Na__Importer::Na__DebugTools
            PayloadReader   = Na__ValeLantern::Na__Importer::Na__PayloadReader
            TagManager      = Na__ValeLantern::Na__Importer::Na__TagManager
            MaterialManager = Na__ValeLantern::Na__Importer::Na__MaterialManager
            PrismBuilder    = Na__ValeLantern::Na__Importer::Na__PrismBuilder
            MeshBuilder     = Na__ValeLantern::Na__Importer::Na__MeshBuilder
            LineBuilder     = Na__ValeLantern::Na__Importer::Na__LineBuilder

            NA_ATTRIBUTE_DICTIONARY = 'VghLantern'.freeze
            NA_OPERATION_NAME       = 'Import Vale Lantern'.freeze
            NA_KIND_PRISM           = 'prism'.freeze
            NA_KIND_INSTANCE        = 'instance'.freeze
            NA_KIND_LINEWORK        = 'linework'.freeze

            NA_ROLE_SETTING_OUT     = 'settingOut'.freeze                                           # <-- Assemblies carrying this Role are construction linework, not metal

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Composition — Public API
# -----------------------------------------------------------------------------

            # FUNCTION | Build one validated payload into the active model
            # ------------------------------------------------------------
            # @param payload [Hash] A payload the reader has already validated
            # @param choices [Hash] { :BuildModel, :BuildSettingOut } - what to build
            # @return [Sketchup::Group, nil] The root lantern group, or nil
            def self.na_compose(payload, choices = {})
                model = Sketchup.active_model
                return nil unless model

                model_block = payload['Model']
                options     = model_block['Options'].is_a?(Hash) ? model_block['Options'] : {}
                wanted      = na_resolve_choices(choices)

                assemblies  = na_admitted_assemblies(model_block['Assemblies'], wanted)
                if assemblies.empty?
                    DebugTools.na_error('Nothing was selected to build.')
                    return nil
                end

                DebugTools.na_reset_tally
                model.start_operation(NA_OPERATION_NAME, true)

                begin
                    na_apply_model_options(model, options)

                    TagManager.na_prepare_tags(model_block['Tags'])
                    MaterialManager.na_prepare_materials(model_block['Materials'])
                    MeshBuilder.na_prepare_definitions(model_block['Definitions']) if wanted[:BuildModel]

                    root = na_build_root_group(model, payload, model_block)
                    na_stamp(root, 'BuiltModel',      wanted[:BuildModel])
                    na_stamp(root, 'BuiltSettingOut', wanted[:BuildSettingOut])
                    na_build_assemblies(root, assemblies, options)

                    model.commit_operation
                    DebugTools.na_report_summary(na_expected_for_choices(assemblies))
                    root

                rescue StandardError => e
                    model.abort_operation
                    DebugTools.na_error("Import aborted (#{e.class}): #{e.message}")
                    DebugTools.na_error(e.backtrace.first(6).join("\n    ")) if e.backtrace
                    nil
                end
            end
            # ---------------------------------------------------------------

            # HELPER FUNCTION | Normalise the caller's build choices
            # ------------------------------------------------------------
            # Defaults to the metal alone, which is what an import means to
            # anyone who has not asked for anything else.
            def self.na_resolve_choices(choices)
                given = choices.is_a?(Hash) ? choices : {}
                {
                    :BuildModel      => given.fetch(:BuildModel, true) != false,
                    :BuildSettingOut => given.fetch(:BuildSettingOut, false) == true
                }
            end
            private_class_method :na_resolve_choices

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
# REGION | Internal — Group Hierarchy
# -----------------------------------------------------------------------------

            # HELPER FUNCTION | Create the single top level lantern group
            # ------------------------------------------------------------
            # Stamped with the project and lantern identity so a model holding
            # three lanterns can be read back to the job each one came from
            # without anyone having to trust the group name.
            def self.na_build_root_group(model, payload, model_block)
                root      = model.active_entities.add_group
                root.name = model_block['RootGroupName'].to_s

                meta    = payload['Meta']    || {}
                project = payload['Project'] || {}
                lantern = payload['Lantern'] || {}

                na_stamp(root, 'RecordType',    'ValeLanternRoot')
                na_stamp(root, 'SchemaVersion', meta['SchemaVersion'])
                na_stamp(root, 'AppVersion',    meta['AppVersion'])
                na_stamp(root, 'ExportedAtIso', meta['ExportedAtIso'])
                na_stamp(root, 'ExportedBy',    meta['ExportedBy'])
                na_stamp(root, 'ProjectCode',   project['Code'])
                na_stamp(root, 'ProjectName',   project['Name'])
                na_stamp(root, 'ClientName',    project['ClientName'])
                na_stamp(root, 'LanternId',     lantern['Id'])
                na_stamp(root, 'LanternTitle',  lantern['Title'])
                na_stamp(root, 'RoofForm',      lantern['RoofForm'])
                na_stamp(root, 'WidthMm',       lantern['WidthMm'])
                na_stamp(root, 'DepthMm',       lantern['DepthMm'])
                na_stamp(root, 'PitchDegrees',  lantern['PitchDegrees'])
                na_stamp(root, 'Quantity',      lantern['Quantity'])

                DebugTools.na_info("Root group: #{root.name}")
                root
            end
            private_class_method :na_build_root_group

            # HELPER FUNCTION | Build every assembly group and the parts inside it
            # ------------------------------------------------------------
            # An assembly that produced nothing is erased again rather than left
            # as an empty group, because SketchUp counts an empty group as an
            # entity the user then has to find and delete. The payload having
            # sent it is still recorded in the console.
            def self.na_build_assemblies(root, assemblies, options)
                return unless assemblies.is_a?(Array)

                sorted = assemblies.sort_by { |assembly| assembly['SortOrder'].to_i }

                sorted.each do |assembly|
                    parts = assembly['Parts']
                    name  = assembly['Name'].to_s

                    if !parts.is_a?(Array) || parts.empty?
                        DebugTools.na_info("Assembly '#{name}': nothing to build.")
                        next
                    end

                    group      = root.entities.add_group
                    group.name = name
                    na_stamp(group, 'RecordType',  'ValeLanternAssembly')
                    na_stamp(group, 'AssemblyKey', assembly['Key'])
                    na_stamp(group, 'AssemblyRole', assembly['Role'])
                    na_stamp_all(group, assembly['Attributes'])                                     # <-- Where the setting out datum checks land

                    built = na_build_parts(group, parts, options)

                    if built.zero?
                        DebugTools.na_warn("Assembly '#{name}': every part was refused - group removed.")
                        group.erase! if group.valid?
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
            # A part carrying a GroupKey is nested one level deeper, in a group
            # created on first use. That is what turns forty glaze bar
            # centrelines into one collapsible outliner entry instead of forty
            # siblings, and it is driven entirely by the data - this file carries
            # no list of what the intermediate groups should be.
            def self.na_build_parts(assembly_group, parts, options)
                built     = 0
                subgroups = {}

                parts.each do |part|
                    next unless part.is_a?(Hash)

                    entities = na_entities_for_part(assembly_group, part, subgroups)

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

                na_prune_empty_subgroups(subgroups)
                built
            end
            private_class_method :na_build_parts

            # HELPER FUNCTION | The entities a part should be built into
            # ------------------------------------------------------------
            # The assembly's own entities when the part names no group, or a
            # lazily created intermediate group when it does.
            def self.na_entities_for_part(assembly_group, part, subgroups)
                group_key = part['GroupKey']
                return assembly_group.entities if group_key.nil? || group_key.to_s.empty?

                key = group_key.to_s
                unless subgroups.key?(key)
                    subgroup      = assembly_group.entities.add_group
                    subgroup.name = (part['GroupName'] || key).to_s
                    na_stamp(subgroup, 'RecordType', 'ValeLanternPartGroup')
                    na_stamp(subgroup, 'GroupKey',   key)
                    subgroups[key] = subgroup
                end

                subgroups[key].entities
            end
            private_class_method :na_entities_for_part

            # HELPER FUNCTION | Remove intermediate groups nothing was built into
            # ------------------------------------------------------------
            # A subgroup is created before its first part is attempted, so a
            # class whose every part was refused would otherwise leave an empty
            # group behind for the user to find and delete.
            def self.na_prune_empty_subgroups(subgroups)
                subgroups.each_value do |subgroup|
                    next unless subgroup && subgroup.valid?
                    next unless subgroup.entities.length.zero?

                    DebugTools.na_detail("Removed empty group '#{subgroup.name}'")
                    subgroup.erase!
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
