# =============================================================================
# VALE LANTERN IMPORTER - CONFIG LOADER
# =============================================================================
#
# FILE       : Na__ValeLantern__Importer__ConfigLoader__.rb
# NAMESPACE  : Na__ValeLantern::Na__Importer
# MODULE     : Na__ConfigLoader
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Read Na__ValeLantern__Importer__Config.json once and hand its
#              values out by key path, with a fallback that keeps an import
#              working when the file is missing.
#
# DESCRIPTION:
# - The plugin's own build decisions - edge softening, component versus group,
#   definition sharing, reload behaviour - live in that JSON file rather than in
#   Ruby constants, so they can be changed and re-read without a code edit.
# - Everything about the LANTERN still comes from the payload. This file is the
#   line between the two: a decision about the lantern belongs in the exporter's
#   config, a decision about how SketchUp should present it belongs here.
#
# -----------------------------------------------------------------------------
#
# WHY A MISSING CONFIG FILE DOES NOT STOP AN IMPORT:
#
# A config file that has been moved, renamed or corrupted must not cost somebody
# their import. The fallback below therefore carries the STRUCTURAL defaults -
# containers as components, sharing on, reload behaviour - so the plugin still
# builds a correct lantern.
#
# What the fallback deliberately does NOT carry is the softening table. That
# table is a set of decisions about how each of twenty four part families should
# look, and duplicating it here would guarantee the two copies drift apart. With
# the file missing every part imports with hard edges, which is what the importer
# did before version 1.4.0, and the console says loudly which file it could not
# find. A visibly unsoftened lantern and a named error beat a silently
# half-correct table.
#
# NAMING CONVENTION:
# - Importer namespace Na__Importer / na_ prefixes.
#
# =============================================================================

require 'json'

module Na__ValeLantern
    module Na__Importer
        module Na__ConfigLoader

# -----------------------------------------------------------------------------
# REGION | Module References and Constants
# -----------------------------------------------------------------------------

            DebugTools = Na__ValeLantern::Na__Importer::Na__DebugTools

            NA_CONFIG_FILE_NAME = 'Na__ValeLantern__Importer__Config.json'.freeze

            NA_BLOCK_SOFTEN       = 'Na__ValeLantern__Importer__Config__SoftenEdges'.freeze
            NA_BLOCK_CONTAINERS   = 'Na__ValeLantern__Importer__Config__Containers'.freeze
            NA_BLOCK_RELOAD       = 'Na__ValeLantern__Importer__Config__Reload'.freeze
            NA_BLOCK_CONTEXT_MENU = 'Na__ValeLantern__Importer__Config__ContextMenu'.freeze

            # Structural defaults only. See the header for why the softening table
            # is not mirrored here.
            NA_FALLBACK_CONFIG = {
                NA_BLOCK_SOFTEN => {
                    'Enabled'     => false,
                    'DefaultRule' => { 'Soften' => false, 'AngleDegrees' => 22.5, 'SmoothNormals' => true, 'SoftenCoplanar' => false },
                    'Rules'       => []
                },
                NA_BLOCK_CONTAINERS => {
                    'RootAsComponent'           => true,
                    'AssemblyAsComponent'       => true,
                    'PartGroupAsComponent'      => true,
                    'PartAsComponent'           => true,
                    'LineworkAsComponent'       => false,
                    'ShareCongruentDefinitions' => true,
                    'ShareMirroredInstances'    => true,
                    'SignatureDecimals'         => 4,
                    'DefinitionNameTemplate'    => '{RootToken}__{Family}__{Index}',
                    'ContainerNameTemplate'     => '{RootToken}__{Name}'
                },
                NA_BLOCK_RELOAD => {
                    'RebuildInPlace'             => true,
                    'ConfirmOnDifferentLantern'  => true,
                    'PreserveBuildChoices'       => true,
                    'RemoveOrphanedDefinitions'  => true,
                    'RememberSourceFile'         => true
                },
                NA_BLOCK_CONTEXT_MENU => {
                    'Enabled' => true
                }
            }.freeze

            # The four container levels, and the config key each one reads.
            NA_CONTAINER_LEVEL_KEYS = {
                :Root      => 'RootAsComponent',
                :Assembly  => 'AssemblyAsComponent',
                :PartGroup => 'PartGroupAsComponent',
                :Part      => 'PartAsComponent'
            }.freeze

            @na_config       = nil                                                                  # <-- Parsed JSON, or the fallback
            @na_soften_index = nil                                                                  # <-- TagKey to rule row, built on first ask
            @na_from_file    = false                                                                # <-- False when the fallback is in use

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Loading — Public API
# -----------------------------------------------------------------------------

            # FUNCTION | Absolute path of the config file
            # ------------------------------------------------------------
            def self.na_config_path
                File.join(__dir__, NA_CONFIG_FILE_NAME)
            end
            # ---------------------------------------------------------------

            # FUNCTION | The parsed config, read from disk on first ask
            # ------------------------------------------------------------
            # Cached, because a softening rule is asked for once per part and a
            # divided lantern has several hundred of them.
            def self.na_load
                return @na_config if @na_config

                path = na_config_path
                unless File.exist?(path)
                    DebugTools.na_error("Importer config not found at #{path} - edge softening is OFF and structural defaults are in use.")
                    @na_from_file = false
                    return (@na_config = NA_FALLBACK_CONFIG)
                end

                text = File.read(path, :encoding => 'UTF-8')
                text = text[1..-1] if !text.empty? && text[0].ord == 0xFEFF                          # <-- A BOM is invisible and breaks JSON.parse on character one
                parsed = JSON.parse(text)

                unless parsed.is_a?(Hash)
                    DebugTools.na_error("#{NA_CONFIG_FILE_NAME} is not a config object - structural defaults are in use.")
                    @na_from_file = false
                    return (@na_config = NA_FALLBACK_CONFIG)
                end

                @na_from_file = true
                @na_config    = parsed

            rescue StandardError => e
                DebugTools.na_error("#{NA_CONFIG_FILE_NAME} could not be read (#{e.class}): #{e.message} - structural defaults are in use.")
                @na_from_file = false
                @na_config    = NA_FALLBACK_CONFIG
            end
            # ---------------------------------------------------------------

            # FUNCTION | Forget the cached config so the next ask re-reads the file
            # ------------------------------------------------------------
            # Called by the module chain loader, so re-pasting the one line loader
            # picks up an edit to the JSON exactly as it picks up an edit to a
            # Ruby module.
            def self.na_reset
                @na_config       = nil
                @na_soften_index = nil
                @na_from_file    = false
            end
            # ---------------------------------------------------------------

            # FUNCTION | Whether the live config came from the file or the fallback
            # ------------------------------------------------------------
            def self.na_from_file?
                na_load
                @na_from_file == true
            end
            # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Value Access — Public API
# -----------------------------------------------------------------------------

            # FUNCTION | Walk a key path into the config
            # ------------------------------------------------------------
            # @param key_path [Array<String>] Block name then keys
            # @return [Object, nil] nil when any step of the path is absent
            def self.na_get(*key_path)
                node = na_load
                key_path.each do |key|
                    return nil unless node.is_a?(Hash)
                    node = node[key.to_s]
                end
                node
            end
            # ---------------------------------------------------------------

            # FUNCTION | Walk a key path, falling back to a given value
            # ------------------------------------------------------------
            # Falls back through the STRUCTURAL defaults first, so a key added to
            # the fallback but missing from an older on-disk config still answers
            # correctly rather than dropping to the call site's guess.
            def self.na_get_or(default_value, *key_path)
                value = na_get(*key_path)
                return value unless value.nil?

                node = NA_FALLBACK_CONFIG
                key_path.each do |key|
                    node = node.is_a?(Hash) ? node[key.to_s] : nil
                end
                node.nil? ? default_value : node
            end
            # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Edge Softening — Public API
# -----------------------------------------------------------------------------

            # FUNCTION | Whether edge softening is switched on at all
            # ------------------------------------------------------------
            def self.na_soften_enabled?
                na_get_or(false, NA_BLOCK_SOFTEN, 'Enabled') == true
            end
            # ---------------------------------------------------------------

            # FUNCTION | The softening rule for one part family
            # ------------------------------------------------------------
            # Keyed on the payload's own TagKey, which is the family - there are
            # twenty four of those against several hundred part names.
            #
            # Returns the DefaultRule for a key the table does not carry, so a
            # part family added to the exporter arrives with hard edges and is
            # visibly unconfigured rather than quietly softened by somebody
            # else's rule.
            #
            # @param tag_key [String, nil] The part's TagKey
            # @return [Hash] Always a rule hash, never nil
            def self.na_soften_rule_for(tag_key)
                return na_default_soften_rule unless na_soften_enabled?

                index = na_soften_index
                rule  = index[tag_key.to_s]
                rule.nil? ? na_default_soften_rule : rule
            end
            # ---------------------------------------------------------------

            # HELPER FUNCTION | The DefaultRule row, with hard coded backstops
            # ------------------------------------------------------------
            def self.na_default_soften_rule
                row = na_get(NA_BLOCK_SOFTEN, 'DefaultRule')
                return { 'Soften' => false, 'AngleDegrees' => 22.5, 'SmoothNormals' => true, 'SoftenCoplanar' => false } unless row.is_a?(Hash)
                row
            end
            private_class_method :na_default_soften_rule

            # HELPER FUNCTION | The Rules array indexed by its Key column
            # ------------------------------------------------------------
            # The config stores rules as an array of rows with a Key, matching the
            # house style of the exporter's own config, and this turns that into
            # the lookup the builders actually want. Built once.
            def self.na_soften_index
                return @na_soften_index if @na_soften_index

                index = {}
                rows  = na_get(NA_BLOCK_SOFTEN, 'Rules')
                if rows.is_a?(Array)
                    rows.each do |row|
                        next unless row.is_a?(Hash)
                        key = row['Key']
                        next if key.nil? || key.to_s.empty?
                        index[key.to_s] = row
                    end
                end

                @na_soften_index = index
            end
            private_class_method :na_soften_index

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Container and Sharing — Public API
# -----------------------------------------------------------------------------

            # FUNCTION | Whether one level of the hierarchy is a component
            # ------------------------------------------------------------
            # @param level [Symbol] :Root, :Assembly, :PartGroup or :Part
            def self.na_container_is_component?(level)
                key = NA_CONTAINER_LEVEL_KEYS[level]
                return true if key.nil?                                                             # <-- An unknown level gets the documented default
                na_get_or(true, NA_BLOCK_CONTAINERS, key) != false
            end
            # ---------------------------------------------------------------

            # FUNCTION | Whether construction linework is a component
            # ------------------------------------------------------------
            # Defaults FALSE where every other level defaults true, which is a
            # deliberate exception rather than an oversight. See the config note:
            # nothing in a setting out set repeats, so there is no definition to
            # share, and one-off definitions for several dozen datums would fill
            # the Component browser with entries nobody selects from there.
            def self.na_linework_is_component?
                na_get_or(false, NA_BLOCK_CONTAINERS, 'LineworkAsComponent') == true
            end
            # ---------------------------------------------------------------

            # FUNCTION | Whether congruent parts share one definition
            # ------------------------------------------------------------
            # Sharing needs the part level to be a component at all - a group
            # cannot carry a second instance - so the two switches are read
            # together rather than leaving a contradictory pair to the caller.
            def self.na_share_definitions?
                return false unless na_container_is_component?(:Part)
                na_get_or(true, NA_BLOCK_CONTAINERS, 'ShareCongruentDefinitions') != false
            end
            # ---------------------------------------------------------------

            # FUNCTION | Whether mirror image parts share with their opposite hand
            # ------------------------------------------------------------
            def self.na_share_mirrored?
                return false unless na_share_definitions?
                na_get_or(true, NA_BLOCK_CONTAINERS, 'ShareMirroredInstances') != false
            end
            # ---------------------------------------------------------------

            # FUNCTION | Decimal places the congruence signature rounds to
            # ------------------------------------------------------------
            def self.na_signature_decimals
                value = na_get_or(4, NA_BLOCK_CONTAINERS, 'SignatureDecimals').to_i
                return 4 if value < 1 || value > 9                                                  # <-- Outside this a signature is either meaningless or unmatchable
                value
            end
            # ---------------------------------------------------------------

            # FUNCTION | Name template for a shared part definition
            # ------------------------------------------------------------
            def self.na_definition_name_template
                na_get_or('{RootToken}__{Family}__{Index}', NA_BLOCK_CONTAINERS, 'DefinitionNameTemplate').to_s
            end
            # ---------------------------------------------------------------

            # FUNCTION | Name template for a container definition
            # ------------------------------------------------------------
            def self.na_container_name_template
                na_get_or('{RootToken}__{Name}', NA_BLOCK_CONTAINERS, 'ContainerNameTemplate').to_s
            end
            # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Reload — Public API
# -----------------------------------------------------------------------------

            # FUNCTION | Whether a reload may replace geometry in place
            # ------------------------------------------------------------
            def self.na_reload_in_place?
                na_get_or(true, NA_BLOCK_RELOAD, 'RebuildInPlace') != false
            end
            # ---------------------------------------------------------------

            # FUNCTION | Whether a reload asks before crossing lantern identities
            # ------------------------------------------------------------
            def self.na_reload_confirms_different_lantern?
                na_get_or(true, NA_BLOCK_RELOAD, 'ConfirmOnDifferentLantern') != false
            end
            # ---------------------------------------------------------------

            # FUNCTION | Whether a reload rebuilds what the import built
            # ------------------------------------------------------------
            def self.na_reload_preserves_choices?
                na_get_or(true, NA_BLOCK_RELOAD, 'PreserveBuildChoices') != false
            end
            # ---------------------------------------------------------------

            # FUNCTION | Whether a reload removes the previous build's definitions
            # ------------------------------------------------------------
            def self.na_reload_removes_orphans?
                na_get_or(true, NA_BLOCK_RELOAD, 'RemoveOrphanedDefinitions') != false
            end
            # ---------------------------------------------------------------

            # FUNCTION | Whether the source file path is stamped on the root
            # ------------------------------------------------------------
            def self.na_remembers_source_file?
                na_get_or(true, NA_BLOCK_RELOAD, 'RememberSourceFile') != false
            end
            # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Context Menu — Public API
# -----------------------------------------------------------------------------

            # FUNCTION | Whether the reload appears on the right click menu
            # ------------------------------------------------------------
            # Read on EVERY right click in SketchUp, which the cached config makes
            # a hash lookup rather than a file read. It is the first thing the
            # context menu builder asks, so turning this off costs one lookup per
            # right click and nothing else.
            def self.na_context_menu_enabled?
                na_get_or(true, NA_BLOCK_CONTEXT_MENU, 'Enabled') != false
            end
            # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

        end
    end
end
