# =============================================================================
# TRUEVISION3D - GLB BUILDER UTILITY - PROJECT LINK (MODEL DICTIONARY)
# =============================================================================
#
# FILE       : Na__TrueVision__GlbBuilder__ProjectLink__.rb
# NAMESPACE  : TrueVision3D::GlbBuilderUtility
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Persist the Noble Architecture project a model belongs to, in the
#              model's own attribute dictionary
# CREATED    : 19-Sep-2026
#
# DESCRIPTION:
# - Stores the project code, resolved folder, portal root and chosen design
#   phase folder inside the .skp, so the link survives closing SketchUp and
#   travels with the file.
# - Everything here is OPTIONAL. A model with no link exports exactly as it
#   always did; the dialog simply offers a folder picker instead of a project.
# - `prompt_dismissed` records that the user cleared the link prompt for this
#   model, so the dialog asks once and then stays out of the way.
#
# DICTIONARY:
#   Name : Na__TrueVision__GlbBuilder__ProjectLink
#   Keys : project_code, project_folder, project_name, project_year,
#          portal_root, project_root, target_phase_folder, target_phase_id,
#          linked_at, prompt_dismissed
#
# -----------------------------------------------------------------------------
#
# DEVELOPMENT LOG:
# 19-Sep-2026 - Version 2.9.0
# - Initial project link dictionary.
#
# =============================================================================

module TrueVision3D
    module GlbBuilderUtility

    # -----------------------------------------------------------------------------
    # REGION | Dictionary Constants
    # -----------------------------------------------------------------------------

        # MODULE CONSTANTS | Dictionary Name, Keys and Validation
        # ------------------------------------------------------------
        # Guarded so a `load`-based hot reload does not emit "already
        # initialized constant" warnings for every key.
        # ------------------------------------------------------------
        unless defined?(NA_PROJECT_LINK_DICT)
            NA_PROJECT_LINK_DICT        = 'Na__TrueVision__GlbBuilder__ProjectLink'.freeze
            NA_PROJECT_CODE_PATTERN     = /\A[A-Z]{2}\d{2}\z/.freeze          # <-- RB05, EB03, AA00
            NA_PROJECT_LINK_KEYS        = %w[
                project_code project_folder project_name project_year
                portal_root project_root target_phase_folder target_phase_id
                linked_at prompt_dismissed
            ].freeze
        end
        # ------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Read
    # -----------------------------------------------------------------------------

        # FUNCTION | Read The Whole Project Link From A Model
        # ---------------------------------------------------------------
        # Always answers a hash with every key present, so callers never have to
        # nil-check individual fields. `linked` is false when no code is stored.
        # ---------------------------------------------------------------
        def self.Na__ProjectLink__Read(model = Sketchup.active_model)
            blank = self.Na__ProjectLink__BlankLink
            return blank unless model

            dict = model.attribute_dictionary(NA_PROJECT_LINK_DICT, false)
            return blank unless dict

            link = blank.dup
            NA_PROJECT_LINK_KEYS.each do |key|
                value = dict[key]
                link[key.to_sym] = value unless value.nil?
            end

            link[:prompt_dismissed] = (link[:prompt_dismissed].to_s == 'true')
            link[:linked]           = self.Na__ProjectLink__ValidCode?(link[:project_code])
            link
        rescue => e
            Na__Log__Warn "[ProjectLink] Could not read the project link: #{e.message}"
            self.Na__ProjectLink__BlankLink
        end
        # ---------------------------------------------------------------

        # FUNCTION | Report Whether A Model Carries A Valid Project Link
        # ---------------------------------------------------------------
        def self.Na__ProjectLink__Linked?(model = Sketchup.active_model)
            self.Na__ProjectLink__Read(model)[:linked] == true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Report Whether The Link Prompt Should Be Shown
        # ---------------------------------------------------------------
        # Shown when the model has no project link AND the user has not already
        # cleared the prompt for this model.
        # ---------------------------------------------------------------
        def self.Na__ProjectLink__ShouldPrompt?(model = Sketchup.active_model)
            link = self.Na__ProjectLink__Read(model)
            return false if link[:linked]
            return false if link[:prompt_dismissed]

            true
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | An Empty Link Hash With Every Key Present
        # ---------------------------------------------------------------
        def self.Na__ProjectLink__BlankLink
            {
                project_code:        '',
                project_folder:      '',
                project_name:        '',
                project_year:        '',
                portal_root:         '',
                project_root:        '',
                target_phase_folder: '',
                target_phase_id:     '',
                linked_at:           '',
                prompt_dismissed:    false,
                linked:              false
            }
        end
        # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Write
    # -----------------------------------------------------------------------------

        # FUNCTION | Write A Resolved Project Link Into The Model
        # ---------------------------------------------------------------
        # `resolution` is the hash produced by the portal mapper. Writing a link
        # always clears prompt_dismissed: the model is now linked, so there is
        # nothing left to prompt for.
        # ---------------------------------------------------------------
        def self.Na__ProjectLink__Write(model, resolution)
            return { success: false, message: 'No active model.' } unless model

            code = resolution[:project_code].to_s.strip.upcase
            unless self.Na__ProjectLink__ValidCode?(code)
                return { success: false, message: "'#{code}' is not a project code. Expected two letters and two digits, such as RB05." }
            end

            dict = model.attribute_dictionary(NA_PROJECT_LINK_DICT, true)
            dict['project_code']        = code
            dict['project_folder']      = resolution[:project_folder].to_s
            dict['project_name']        = resolution[:project_name].to_s
            dict['project_year']        = resolution[:project_year].to_s
            dict['portal_root']         = resolution[:portal_root].to_s
            dict['project_root']        = resolution[:project_root].to_s
            dict['linked_at']           = Time.now.strftime('%Y-%m-%d %H:%M:%S')
            dict['prompt_dismissed']    = 'false'

            # Only overwrite the chosen phase when the caller supplied one
            unless resolution[:target_phase_folder].to_s.empty?
                dict['target_phase_folder'] = resolution[:target_phase_folder].to_s
                dict['target_phase_id']     = resolution[:target_phase_id].to_s
            end

            { success: true, message: "Model linked to #{code} - #{resolution[:project_name]}." }
        rescue => e
            Na__Log__Warn "[ProjectLink] Could not write the project link: #{e.message}"
            { success: false, message: "#{e.class}: #{e.message}" }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Record The Design Phase Folder This Model Exports Into
        # ---------------------------------------------------------------
        def self.Na__ProjectLink__WriteTargetPhase(model, phase_folder, phase_id = '')
            return { success: false, message: 'No active model.' } unless model

            dict = model.attribute_dictionary(NA_PROJECT_LINK_DICT, true)
            dict['target_phase_folder'] = phase_folder.to_s
            dict['target_phase_id']     = phase_id.to_s

            { success: true, message: "Target folder set to #{phase_folder}." }
        rescue => e
            Na__Log__Warn "[ProjectLink] Could not write the target phase: #{e.message}"
            { success: false, message: "#{e.class}: #{e.message}" }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Read The Site Plan Folder This Model Exports Into
        # ---------------------------------------------------------------
        # Deliberately NOT a NA_PROJECT_LINK_KEYS entry. That constant lives
        # inside an `unless defined?` guard, so a hot reload keeps the old list
        # and a new key would silently never be read. Going at the dictionary
        # directly works on a reload as well as a restart.
        #
        # An empty answer means "not chosen yet", which the Project tab shows as
        # a prompt rather than guessing a variant.
        # ---------------------------------------------------------------
        def self.Na__ProjectLink__ReadSitePlanFolder(model = Sketchup.active_model)
            return '' unless model
            dict = model.attribute_dictionary(NA_PROJECT_LINK_DICT, false)
            return '' unless dict
            dict['siteplan_folder'].to_s
        rescue => e
            Na__Log__Warn "[ProjectLink] Could not read the site plan folder: #{e.message}"
            ''
        end
        # ---------------------------------------------------------------

        # FUNCTION | Record The Site Plan Folder This Model Exports Into
        # ---------------------------------------------------------------
        def self.Na__ProjectLink__WriteSitePlanFolder(model, folder_name)
            return { success: false, message: 'No active model.' } unless model

            dict = model.attribute_dictionary(NA_PROJECT_LINK_DICT, true)
            dict['siteplan_folder'] = folder_name.to_s

            { success: true, message: "Site plan target set to #{folder_name}." }
        rescue => e
            Na__Log__Warn "[ProjectLink] Could not write the site plan folder: #{e.message}"
            { success: false, message: "#{e.class}: #{e.message}" }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Record That The User Cleared The Link Prompt
        # ---------------------------------------------------------------
        # The escape hatch for a one-off export that belongs to no project. The
        # model stays unlinked and the dialog stops asking.
        # ---------------------------------------------------------------
        def self.Na__ProjectLink__DismissPrompt(model)
            return { success: false, message: 'No active model.' } unless model

            dict = model.attribute_dictionary(NA_PROJECT_LINK_DICT, true)
            dict['prompt_dismissed'] = 'true'

            { success: true, message: 'Export without a project link. The prompt will not show again for this model.' }
        rescue => e
            Na__Log__Warn "[ProjectLink] Could not dismiss the prompt: #{e.message}"
            { success: false, message: "#{e.class}: #{e.message}" }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Remove The Project Link From A Model
        # ---------------------------------------------------------------
        # Leaves prompt_dismissed set so unlinking does not immediately re-open
        # the prompt the user just stepped out of.
        # ---------------------------------------------------------------
        def self.Na__ProjectLink__Clear(model)
            return { success: false, message: 'No active model.' } unless model

            dict = model.attribute_dictionary(NA_PROJECT_LINK_DICT, false)
            return { success: true, message: 'This model was not linked to a project.' } unless dict

            NA_PROJECT_LINK_KEYS.each do |key|
                next if key == 'prompt_dismissed'
                dict.delete_key(key) if dict[key]
            end
            dict['prompt_dismissed'] = 'true'

            { success: true, message: 'Project link cleared.' }
        rescue => e
            Na__Log__Warn "[ProjectLink] Could not clear the project link: #{e.message}"
            { success: false, message: "#{e.class}: #{e.message}" }
        end
        # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Validation
    # -----------------------------------------------------------------------------

        # FUNCTION | Validate A Project Code String
        # ---------------------------------------------------------------
        def self.Na__ProjectLink__ValidCode?(code)
            !!(code.to_s.strip.upcase =~ NA_PROJECT_CODE_PATTERN)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Normalise User Input Into A Project Code
        # ---------------------------------------------------------------
        # Returns nil when the input cannot be a project code, so the caller can
        # report the problem rather than storing rubbish.
        # ---------------------------------------------------------------
        def self.Na__ProjectLink__NormaliseCode(raw_code)
            code = raw_code.to_s.strip.upcase.gsub(/[^A-Z0-9]/, '')
            return nil unless self.Na__ProjectLink__ValidCode?(code)

            code
        end
        # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

    end  # module GlbBuilderUtility
end  # module TrueVision3D

# =============================================================================
# END OF FILE
# =============================================================================
