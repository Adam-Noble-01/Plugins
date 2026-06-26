# =============================================================================
# VALEDESIGNSUITE - VALEVISION CLOUD SYNC PROJECT PATH MAPPER
# =============================================================================
#
# FILE       : Na__ValeVisionCloudSync__ProjectPathMapper__.rb
# NAMESPACE  : Na__ValeVisionCloudSync::Na__ProjectPathMapper
# PURPOSE    : Derive project root from model path; map all fixed subfolders;
#              read/write path override from the ValeVision__CloudExport dict
# CREATED    : 25-Jun-2026
#
# DESCRIPTION:
# - Vale projects are structured as:
#     C:/01__ValeProjects/{code}__{Name}/02__SketchUp/01__MainModel/Model.skp
#   Walking two levels up from the model file gives the project root.
# - A saved override in the model dictionary takes priority over the derived
#   path so models stored elsewhere can still be synced.
# - All fixed subfolder paths are derived once from the resolved root.
#
# -----------------------------------------------------------------------------
#
# DEVELOPMENT LOG:
# 25-Jun-2026 - Version 1.0.0
# - Initial project root derivation and path override from model dictionary.
#
# 25-Jun-2026 - Version 1.1.0
# - Na__ValeVisionCloudSync__ReadFirstSyncComplete / MarkFirstSyncComplete:
#   persists first_sync_complete in model dictionary for Update-button lock state.
# - BuildPathDisplayData now includes first_sync_complete for HtmlDialog bridge.
#
# =============================================================================

module Na__ValeVisionCloudSync
    module Na__ProjectPathMapper

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

        # FUNCTION | Resolve the active project root for a given model
        # ------------------------------------------------------------
        def self.Na__ValeVisionCloudSync__ResolveProjectRoot(model = nil)
            model ||= Sketchup.active_model
            return nil unless model

            override = na_read_path_override(model)
            return override unless override.to_s.empty?

            self.Na__ValeVisionCloudSync__DeriveProjectRoot(model)
        end

        # FUNCTION | Derive project root by walking up from model file path
        # ------------------------------------------------------------
        def self.Na__ValeVisionCloudSync__DeriveProjectRoot(model = nil)
            model ||= Sketchup.active_model
            return nil unless model

            model_path = model.path.to_s
            return nil if model_path.empty?

            # Model lives at: .../ProjectRoot/02__SketchUp/01__MainModel/file.skp
            # Two parent directories = 02__SketchUp, one more = ProjectRoot
            model_dir   = File.dirname(model_path)       # <-- .../01__MainModel
            sketchup_dir = File.dirname(model_dir)       # <-- .../02__SketchUp
            project_root = File.dirname(sketchup_dir)    # <-- .../ProjectRoot

            return na_normalize_path(project_root) if File.directory?(project_root)

            # <-- Fallback: model may be one level shallower (directly in 02__SketchUp)
            fallback_root = File.dirname(model_dir)
            File.directory?(fallback_root) ? na_normalize_path(fallback_root) : nil
        end

        # FUNCTION | Resolve root + all subfolders as a single paths hash
        # ------------------------------------------------------------
        # Composes ResolveProjectRoot and MapProjectSubfolders into the single
        # paths hash consumed by Na__SyncOrchestrator (:project_root) and
        # Na__GlbExportBridge (:glb_sync), plus all other mapped subfolders.
        # ---------------------------------------------------------------
        def self.Na__ValeVisionCloudSync__GetProjectPaths(model = nil)
            model ||= Sketchup.active_model                                      # <-- Default to active model
            root    = self.Na__ValeVisionCloudSync__ResolveProjectRoot(model)    # <-- Override-aware root
            return { project_root: nil } if root.to_s.empty?                     # <-- Bail if unresolved

            subfolders = self.Na__ValeVisionCloudSync__MapProjectSubfolders(root) # <-- Map fixed subfolders
            { project_root: root }.merge(subfolders)                             # <-- Combine into one hash
        end

        # FUNCTION | Return hash of all mapped subfolder absolute paths
        # ------------------------------------------------------------
        def self.Na__ValeVisionCloudSync__MapProjectSubfolders(project_root)
            return {} unless project_root && File.directory?(project_root)

            subfolder_config = Na__ConfigLoader.Na__ValeVisionCloudSync__ProjectSubfolders
            root_normalised  = na_normalize_path(project_root)               # <-- Forward slashes so Dir.glob works on Windows

            subfolder_config.each_with_object({}) do |(key, relative_path), paths|
                full_path = na_normalize_path(File.join(root_normalised, relative_path))  # <-- Keep slashes consistent
                paths[key.to_sym] = full_path
            end
        end

        # FUNCTION | Build full path display data hash for the dialog
        # ------------------------------------------------------------
        def self.Na__ValeVisionCloudSync__BuildPathDisplayData(model = nil)
            model ||= Sketchup.active_model

            unless model
                return {
                    model_name:       '(No active model)',
                    model_path:       '',
                    derived_root:     '',
                    override_path:    '',
                    active_path:      '',
                    has_override:        false,
                    img_scene_count:     0,
                    first_sync_complete: false,
                    subfolders:          {},
                    subfolders_exist:    {}
                }
            end

            override_path = na_read_path_override(model)
            has_override  = !override_path.to_s.empty?
            derived_root  = self.Na__ValeVisionCloudSync__DeriveProjectRoot(model).to_s
            active_root   = has_override ? override_path : derived_root
            subfolders    = active_root.empty? ? {} : self.Na__ValeVisionCloudSync__MapProjectSubfolders(active_root)

            prefix_regex  = Na__ConfigLoader.Na__ValeVisionCloudSync__ScenePrefixRegex
            img_count     = na_count_img_scenes(model, prefix_regex)

            {
                model_name:       File.basename(model.path.to_s, '.skp'),
                model_path:       model.path.to_s,
                derived_root:     derived_root,
                override_path:    override_path.to_s,
                active_path:         active_root,
                has_override:        has_override,
                img_scene_count:     img_count,
                first_sync_complete: self.Na__ValeVisionCloudSync__ReadFirstSyncComplete(model),
                subfolders:          subfolders,
                subfolders_exist:    na_check_subfolders_exist(subfolders)
            }
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Model Dictionary Read/Write
# -----------------------------------------------------------------------------

        def self.Na__ValeVisionCloudSync__SavePathOverride(model, path_value)
            return { success: false, message: 'No active model.' } unless model

            dict = model.attribute_dictionary(
                Na__ConfigLoader.Na__ValeVisionCloudSync__ModelDictionaryName, true
            )
            dict['project_path_override'] = path_value.to_s.strip
            { success: true, message: 'Project path override saved.' }
        end

        def self.Na__ValeVisionCloudSync__ClearPathOverride(model)
            return { success: false, message: 'No active model.' } unless model

            dict = model.attribute_dictionary(
                Na__ConfigLoader.Na__ValeVisionCloudSync__ModelDictionaryName, false
            )
            dict&.delete_key('project_path_override')
            { success: true, message: 'Project path override cleared.' }
        end

        def self.Na__ValeVisionCloudSync__ReadPathOverride(model)
            na_read_path_override(model)
        end

        # FUNCTION | Read Whether This Model Has Completed A First Successful Sync
        # ------------------------------------------------------------
        # Drives the dialog's update-button lock: the three "Update ..." cards stay
        # greyed out until a full sync has succeeded at least once for this model.
        # ---------------------------------------------------------------
        def self.Na__ValeVisionCloudSync__ReadFirstSyncComplete(model)
            return false unless model

            dict = model.attribute_dictionary(
                Na__ConfigLoader.Na__ValeVisionCloudSync__ModelDictionaryName, false
            )
            return false unless dict

            dict['na_first_sync_complete'] == true              # <-- Strict true; absent/false stays locked
        end

        # FUNCTION | Mark This Model As Having Completed A First Successful Sync
        # ------------------------------------------------------------
        def self.Na__ValeVisionCloudSync__MarkFirstSyncComplete(model)
            return { success: false, message: 'No active model.' } unless model

            dict = model.attribute_dictionary(
                Na__ConfigLoader.Na__ValeVisionCloudSync__ModelDictionaryName, true
            )
            dict['na_first_sync_complete'] = true               # <-- Persisted with the .skp file
            { success: true, message: 'First sync state recorded.' }
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Edition Folder Resolution
# -----------------------------------------------------------------------------

        # FUNCTION | Resolve or create the current edition folder under content_delivered
        # ------------------------------------------------------------
        def self.Na__ValeVisionCloudSync__ResolveEditionFolder(content_delivered_path)
            return nil unless content_delivered_path && File.directory?(content_delivered_path)

            content_delivered_path = na_normalize_path(content_delivered_path)  # <-- Forward slashes for Dir.glob
            prefix   = Na__ConfigLoader.Na__ValeVisionCloudSync__EditionFolderPrefix
            date_str = na_today_date_string

            existing_editions = Dir.glob(File.join(content_delivered_path, "#{prefix}*Edition*"))
                                   .select { |path| File.directory?(path) }

            if existing_editions.empty?
                new_name = "#{prefix}FirstEdition__#{date_str}"
            else
                new_name = "#{prefix}SecondEdition__#{date_str}"
            end

            target_path = File.join(content_delivered_path, new_name)
            FileUtils.mkdir_p(target_path)
            target_path
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Private Helpers
# -----------------------------------------------------------------------------

        def self.na_read_path_override(model)
            return '' unless model

            dict = model.attribute_dictionary(
                Na__ConfigLoader.Na__ValeVisionCloudSync__ModelDictionaryName, false
            )
            return '' unless dict

            raw = dict['project_path_override'].to_s
            raw.empty? ? '' : na_normalize_path(raw)   # <-- Normalise so Dir.glob does not treat '\' as escape
        end

        # HELPER FUNCTION | Normalise A Filesystem Path To Forward Slashes
        # ---------------------------------------------------------------
        # Ruby's Dir.glob treats '\' as an escape character, so backslash
        # Windows paths silently match nothing. Forward slashes work for
        # File.*, Dir.glob and FileUtils on Windows, so we normalise once
        # at the source and keep all downstream paths consistent.
        # ---------------------------------------------------------------
        def self.na_normalize_path(path_value)
            path_value.to_s.tr('\\', '/')
        end

        def self.na_count_img_scenes(model, prefix_regex)
            model.pages.count { |page| page.name.to_s.match?(prefix_regex) }
        rescue
            0
        end

        def self.na_check_subfolders_exist(subfolders)
            subfolders.each_with_object({}) do |(key, path), result|
                result[key] = File.directory?(path)
            end
        end

        def self.na_today_date_string
            t = Time.now
            months = %w[Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec]
            "#{t.day.to_s.rjust(2, '0')}-#{months[t.month - 1]}-#{t.year}"
        end

# endregion -------------------------------------------------------------------

    end # module Na__ProjectPathMapper
end # module Na__ValeVisionCloudSync

# =============================================================================
# END OF FILE
# =============================================================================
