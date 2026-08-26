# =============================================================================
# NA NOBLE3D MODELLING TOOLS - SCENE DATA TRANSFER - STYLE FACTORY
# =============================================================================
#
# FILE       : Na__SceneDataTransfer__StyleFactory__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__SceneDataTransfer__StyleFactory
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Create genuine named in-model Sketchup::Style entries in the
#              target model, so imported scenes bind to a real style rather
#              than only carrying loose rendering options.
# CREATED    : 2026
#
# CAN YOU CREATE A STYLE FROM RUBY? UNTIL RECENTLY, NO. NOW, YES.
#
#   SketchUp/api-issue-tracker issue #1026 - "Create new style or duplicate
#   style (to create scenes with distinct rendering)" - is the long-standing
#   request for exactly this. For most of the API's life the answer was that
#   there is no way to duplicate a loaded style or create one from scratch;
#   the GUI's "Save as a new Style" had no API equivalent, and the only
#   workaround was to ship pre-made .style files and load them.
#
#   SKETCHUP 2026.2 ADDED Sketchup::Style#duplicate.
#     "The #duplicate method creates a copy of the style with all its
#      properties." -> returns the newly created Sketchup::Style.
#   That is the missing primitive. Combined with Styles#update_selected_style,
#   a brand new named style can finally be built from Ruby.
#
# THE FOUR TIERS, TRIED IN ORDER:
#
#   1. BIND EXISTING     - a style of that name is already in the target model.
#                          Nothing to create; just use it.
#   2. LOAD FROM FILE    - Style#path (2025.0+) recorded where the source style
#                          was loaded from. If that file still exists,
#                          Styles#add_style(path, false) creates a genuine
#                          style. From 2026.0 add_style returns the new Style
#                          rather than a Boolean.
#   3. DUPLICATE + COMMIT - SketchUp 2026.2+. Duplicate any existing style to
#                          get a new Style object, select it, replay the
#                          captured rendering options onto the model, then
#                          Styles#update_selected_style to commit them into it.
#   4. OPTIONS ONLY      - older SketchUp. The scene still looks right because
#                          its own rendering options carry the appearance, but
#                          no named style is created. Reported, not hidden.
#
# WHY THE SELECTED STYLE MUST BE SAVED AND RESTORED:
#   update_selected_style commits to whichever style is CURRENTLY SELECTED, so
#   tier 3 has to select the new style first. Selecting a style also changes
#   what the user is looking at. The original selection is therefore captured
#   before any of this and restored afterwards, so the import does not leave the
#   model displaying an imported style.
#
# ACTIVE STYLE VERSUS SELECTED STYLE:
#   Styles#selected_style is the style selected in the Styles Browser.
#   Styles#active_style is a temporary working copy that holds uncommitted
#   edits. Writing model.rendering_options edits the ACTIVE style; nothing is
#   persisted into a real style until update_selected_style is called. Note
#   also that selected_style= raises ArgumentError if handed the active_style.
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__SceneDataTransfer__StyleFactory

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_TIER_EXISTING  = 'bound_existing'.freeze
        NA_TIER_FILE      = 'loaded_from_file'.freeze
        NA_TIER_DUPLICATE = 'created_by_duplicate'.freeze
        NA_TIER_NONE      = 'options_only'.freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Capture
# -----------------------------------------------------------------------------

        # FUNCTION | Build the Distinct Style Inventory Across Every Scene
        # ------------------------------------------------------------
        # Captured once per run. Scenes usually share a handful of styles, so
        # this collapses them to one record per style name, each carrying the
        # full rendering option set needed to rebuild it.
        def self.Na__SceneDataTransfer__CaptureModelStyles(model)
            return nil unless model

            rendering = Na__SceneDataTransfer__RenderingDomain
            inventory = {}

            model.pages.each do |page|
                style_name = na_page_style_name(page)
                next if style_name.empty?
                next if inventory.key?(style_name)

                captured = rendering.Na__SceneDataTransfer__CaptureStyle(page)
                next unless captured

                inventory[style_name] = {
                    'name'        => style_name,
                    'description' => captured['style_description'].to_s,
                    'path'        => na_page_style_path(page),
                    'options'     => captured['options']
                }
            end

            { 'styles' => inventory.values }
        rescue => error
            puts "[Na__SceneDataTransfer] Style inventory capture error: #{error.class}: #{error.message}"
            nil
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Read a Page's Bound Style Name
        # ------------------------------------------------------------
        def self.na_page_style_name(page)
            style = page.style
            style ? style.name.to_s : ''
        rescue
            ''
        end
        private_class_method :na_page_style_name
        # ------------------------------------------------------------

        # HELPER FUNCTION | Read Where a Page's Style Was Loaded From
        # ------------------------------------------------------------
        # Style#path is SketchUp 2025.0+. A style built in the GUI rather than
        # loaded from a .style file will report nothing useful here, which is
        # exactly why tier 3 exists.
        def self.na_page_style_path(page)
            style = page.style
            return '' unless style && style.respond_to?(:path)

            style.path.to_s
        rescue
            ''
        end
        private_class_method :na_page_style_path
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Rebuild
# -----------------------------------------------------------------------------

        # FUNCTION | Create Every Captured Style That the Target Model Lacks
        # ------------------------------------------------------------
        # Called ONCE per import, in the prepare phase, before any page is built.
        # Returns { applied, warnings, lookup } where lookup maps the SOURCE
        # style name to the live Sketchup::Style in this model.
        def self.Na__SceneDataTransfer__EnsureModelStyles(model, inventory_hash)
            return na_result(false, ['No model supplied.'], {})           unless model
            return na_result(false, ['No style inventory supplied.'], {}) unless inventory_hash.is_a?(Hash)

            records = Array(inventory_hash['styles'])
            return na_result(true, [], {}) if records.empty?

            original_selected = na_selected_style(model)                            # <-- Restored at the end, always
            warnings          = []
            lookup            = {}
            tally             = Hash.new(0)

            begin
                records.each do |style_record|
                    style_name = style_record['name'].to_s
                    next if style_name.empty?

                    created_style, tier = na_obtain_style(model, style_record, warnings)
                    tally[tier] += 1

                    lookup[style_name] = created_style if created_style
                end
            ensure
                na_restore_selected_style(model, original_selected)                 # <-- Never leave an imported style showing
            end

            na_result(true, na_summarise(tally, warnings), lookup)
        rescue => error
            na_result(false, ["Style creation failed: #{error.class}: #{error.message}"], {})
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Work Down the Four Tiers Until a Style Is Obtained
        # ------------------------------------------------------------
        def self.na_obtain_style(model, style_record, warnings)
            style_name = style_record['name'].to_s

            existing = na_find_style(model, style_name)                             # <-- Tier 1
            return [existing, NA_TIER_EXISTING] if existing

            from_file = na_add_style_from_file(model, style_record, warnings)       # <-- Tier 2
            return [from_file, NA_TIER_FILE] if from_file

            duplicated = na_create_by_duplicate(model, style_record, warnings)      # <-- Tier 3
            return [duplicated, NA_TIER_DUPLICATE] if duplicated

            warnings << na_options_only_message(style_name)                          # <-- Tier 4
            [nil, NA_TIER_NONE]
        end
        private_class_method :na_obtain_style
        # ------------------------------------------------------------

        # HELPER FUNCTION | Tier 2 - Load the Style From Its Original .style File
        # ------------------------------------------------------------
        # From SketchUp 2026.0 add_style returns the added Style. Older releases
        # return a Boolean, so the collection is re-searched by name instead.
        def self.na_add_style_from_file(model, style_record, warnings)
            style_path = style_record['path'].to_s
            return nil if style_path.empty?
            return nil unless File.exist?(style_path)
            return nil unless File.extname(style_path).downcase == '.style'

            outcome = model.styles.add_style(style_path, false)
            return outcome if outcome.is_a?(Sketchup::Style)

            na_find_style(model, style_record['name'].to_s)
        rescue => error
            warnings << "Could not load style '#{style_record['name']}' from #{style_record['path']}: #{error.message}"
            nil
        end
        private_class_method :na_add_style_from_file
        # ------------------------------------------------------------

        # HELPER FUNCTION | Tier 3 - Duplicate, Select, Replay, Commit
        # ------------------------------------------------------------
        # The only route that creates a genuinely new named in-model style, and
        # it needs SketchUp 2026.2 for Style#duplicate.
        def self.na_create_by_duplicate(model, style_record, warnings)
            donor = na_duplicate_donor(model)
            return nil unless donor && donor.respond_to?(:duplicate)

            new_style = donor.duplicate
            return nil unless new_style.is_a?(Sketchup::Style)

            na_name_style(new_style, style_record)

            model.styles.selected_style = new_style                                 # <-- update_selected_style commits to THIS
            na_replay_options(model, style_record['options'], warnings)
            model.styles.update_selected_style                                      # <-- Persist the working copy into it

            new_style
        rescue => error
            warnings << "Could not create style '#{style_record['name']}': #{error.class}: #{error.message}"
            nil
        end
        private_class_method :na_create_by_duplicate
        # ------------------------------------------------------------

        # HELPER FUNCTION | Pick a Style to Duplicate From
        # ------------------------------------------------------------
        # Any style will do - duplicate only supplies the new object, and every
        # visible property is overwritten by the replayed rendering options.
        def self.na_duplicate_donor(model)
            selected = na_selected_style(model)
            return selected if selected

            model.styles.first
        rescue
            nil
        end
        private_class_method :na_duplicate_donor
        # ------------------------------------------------------------

        # HELPER FUNCTION | Name and Describe a Freshly Created Style
        # ------------------------------------------------------------
        def self.na_name_style(new_style, style_record)
            new_style.name = style_record['name'].to_s if new_style.respond_to?(:name=)

            description = style_record['description'].to_s
            new_style.description = description if !description.empty? && new_style.respond_to?(:description=)
        rescue => error
            puts "[Na__SceneDataTransfer] Style naming warning: #{error.message}"
        end
        private_class_method :na_name_style
        # ------------------------------------------------------------

        # HELPER FUNCTION | Write the Captured Options Onto the Model's Live Options
        # ------------------------------------------------------------
        # This edits the ACTIVE style, which is a temporary working copy. Nothing
        # is persisted until update_selected_style runs.
        def self.na_replay_options(model, encoded_options, warnings)
            return unless encoded_options.is_a?(Hash)

            codec           = Na__SceneDataTransfer__ValueCodec
            target_options  = model.rendering_options
            return unless target_options

            target_keys = na_live_keys(target_options)

            encoded_options.each do |option_key, encoded_value|
                next unless target_keys.include?(option_key.to_s)

                decoded_value = codec.Na__SceneDataTransfer__Decode(encoded_value)
                next if decoded_value.nil?

                begin
                    target_options[option_key.to_s] = decoded_value
                rescue ArgumentError
                    next                                                            # <-- 2024.0+ rejects some values; skip quietly
                rescue => error
                    warnings << "Style option '#{option_key}' failed: #{error.message}"
                end
            end
        end
        private_class_method :na_replay_options
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Small Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Find a Style by Exact Name
        # ------------------------------------------------------------
        def self.na_find_style(model, style_name)
            return nil if style_name.to_s.empty?

            model.styles.find { |style| style.name.to_s == style_name.to_s }
        rescue
            nil
        end
        private_class_method :na_find_style
        # ------------------------------------------------------------

        # HELPER FUNCTION | Read the Currently Selected Style Defensively
        # ------------------------------------------------------------
        def self.na_selected_style(model)
            model.styles.selected_style
        rescue
            nil
        end
        private_class_method :na_selected_style
        # ------------------------------------------------------------

        # HELPER FUNCTION | Put the User's Own Style Selection Back
        # ------------------------------------------------------------
        def self.na_restore_selected_style(model, original_style)
            return unless original_style && original_style.valid?

            model.styles.selected_style = original_style
        rescue => error
            puts "[Na__SceneDataTransfer] Style selection restore warning: #{error.message}"
        end
        private_class_method :na_restore_selected_style
        # ------------------------------------------------------------

        # HELPER FUNCTION | Enumerate the Live Rendering Option Keys
        # ------------------------------------------------------------
        def self.na_live_keys(rendering_options)
            return rendering_options.keys.map(&:to_s) if rendering_options.respond_to?(:keys)

            collected = []
            rendering_options.each_key { |option_key| collected << option_key.to_s }
            collected
        rescue
            []
        end
        private_class_method :na_live_keys
        # ------------------------------------------------------------

        # HELPER FUNCTION | Explain Why No Named Style Could Be Created
        # ------------------------------------------------------------
        def self.na_options_only_message(style_name)
            "Style '#{style_name}' could not be created as a named style. Creating a style from Ruby needs " \
            "SketchUp 2026.2 or newer, which added Sketchup::Style#duplicate. The scene still looks correct " \
            'because its own rendering options carry the appearance, but it is not a named style in the ' \
            'Styles browser.'
        end
        private_class_method :na_options_only_message
        # ------------------------------------------------------------

        # HELPER FUNCTION | Turn the Per-Tier Tally Into One Readable Line
        # ------------------------------------------------------------
        def self.na_summarise(tally, warnings)
            parts = []
            parts << "#{tally[NA_TIER_DUPLICATE]} style(s) created in this model" if tally[NA_TIER_DUPLICATE] > 0
            parts << "#{tally[NA_TIER_FILE]} style(s) loaded from their .style file" if tally[NA_TIER_FILE] > 0
            parts << "#{tally[NA_TIER_EXISTING]} style(s) already present" if tally[NA_TIER_EXISTING] > 0

            warnings.unshift("Styles: #{parts.join(', ')}.") unless parts.empty?
            warnings
        end
        private_class_method :na_summarise
        # ------------------------------------------------------------

        # HELPER FUNCTION | Build the Standard Result Hash
        # ------------------------------------------------------------
        def self.na_result(applied_flag, warnings, lookup)
            { 'applied' => !!applied_flag, 'warnings' => Array(warnings), 'lookup' => lookup || {} }
        end
        private_class_method :na_result
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__SceneDataTransfer__StyleFactory
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
