# =============================================================================
# TRUEVISION3D - GLB BUILDER UTILITY - PROJECT PORTAL MAPPER
# =============================================================================
#
# FILE       : Na__TrueVision__GlbBuilder__ProjectPortalMapper__.rb
# NAMESPACE  : TrueVision3D::GlbBuilderUtility
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Resolve a project code to its portal folder, and read / create
#              the design phase folders the exporter writes into
# CREATED    : 19-Sep-2026
#
# DESCRIPTION:
# - Finds the na-project-portal root, reads the ProjectVision master index, and
#   turns a code such as RB05 into a full path plus the project's rich admin data.
# - Lists the design phase folders under 30__TrueVision__AppContent with their
#   GLB counts and last-written dates, for version management in the dialog.
# - Owns the CANONICAL folder naming, and the ALIASES that let an older folder
#   name still be recognised as the phase it always was. It never renames a
#   folder that already exists: live TrueVision projects read those names.
#
# DATA SOURCES:
#   Na__TrueVision__GlbBuilder__ProjectPortalConfig__.json   (naming + paths)
#   na-apps/.../ProjectVision__MasterProjectIndex__Core__.json (code -> folder)
#   {project}/10__ProjectAdmin__AppContent/ProjectAdmin__ProjectConfig__.json
#
# -----------------------------------------------------------------------------
#
# DEVELOPMENT LOG:
# 19-Sep-2026 - Version 2.9.0
# - Initial portal mapper.
#
# =============================================================================

require 'json'
require 'fileutils'

module TrueVision3D
    module GlbBuilderUtility

    # -----------------------------------------------------------------------------
    # REGION | Configuration Loading
    # -----------------------------------------------------------------------------

        # FUNCTION | Resolve The Portal Config File Path
        # ---------------------------------------------------------------
        def self.Na__PortalMapper__ConfigFilePath
            File.join(self.Na__PathResolver__ModulesRoot, 'Na__TrueVision__GlbBuilder__ProjectPortalConfig__.json')
        end
        # ---------------------------------------------------------------

        # FUNCTION | Load The Portal Config, Cached For The Session
        # ---------------------------------------------------------------
        def self.Na__PortalMapper__Config
            @na_portal_config ||= self.Na__PortalMapper__LoadConfigFromDisk
        end
        # ---------------------------------------------------------------

        # FUNCTION | Force A Config Reload (Called By Reload Scripts)
        # ---------------------------------------------------------------
        def self.Na__PortalMapper__ForceReload
            @na_portal_config = nil
            @na_master_index  = nil
            self.Na__PortalMapper__Config
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Read And Parse The Config File
        # ---------------------------------------------------------------
        def self.Na__PortalMapper__LoadConfigFromDisk
            path = self.Na__PortalMapper__ConfigFilePath
            unless File.exist?(path)
                Na__Log__Warn "[PortalMapper] Config not found at #{path} - project features disabled."
                return self.Na__PortalMapper__FallbackConfig
            end

            JSON.parse(File.read(path))
        rescue => e
            Na__Log__Warn "[PortalMapper] Could not parse the portal config: #{e.message}"
            self.Na__PortalMapper__FallbackConfig
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Minimal Config Used When The File Is Unreadable
        # ---------------------------------------------------------------
        def self.Na__PortalMapper__FallbackConfig
            {
                'PortalRoots'       => { 'SearchPaths' => [], 'YearFolderPattern' => '^(\\d{2})-Projects$' },
                'MasterIndex'       => {},
                'TrueVisionContent' => {
                    'ContentFolderName'   => '30__TrueVision__AppContent',
                    'ProjectDataFileName' => 'TrueVision__ProjectData__.json',
                    'SitePlanFolderName'  => 'SitePlan__DrawingData',
                    'ArchiveFolderName'   => '00__Archive',
                    'SkipFolderPrefixes'  => ['.', '00__']
                },
                'DesignPhases'      => [],
                'BuildPipeline'     => {},
                'Python'            => {}
            }
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Read The TrueVision Content Folder Name
        # ---------------------------------------------------------------
        def self.Na__PortalMapper__ContentFolderName
            self.Na__PortalMapper__Config.dig('TrueVisionContent', 'ContentFolderName') || '30__TrueVision__AppContent'
        end
        # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Portal Root Discovery
    # -----------------------------------------------------------------------------

        # FUNCTION | Find The na-project-portal Root
        # ---------------------------------------------------------------
        # A stored override on the model wins; otherwise the configured search
        # paths are tried in order. A path only counts when it actually holds a
        # {NN}-Projects folder, so a stale drive letter cannot match.
        # ---------------------------------------------------------------
        def self.Na__PortalMapper__ResolvePortalRoot(override_path = nil)
            candidates = []
            candidates << override_path.to_s unless override_path.to_s.strip.empty?
            candidates.concat(Array(self.Na__PortalMapper__Config.dig('PortalRoots', 'SearchPaths')))

            candidates.each do |candidate|
                path = candidate.to_s.tr('\\', '/')
                next if path.empty?
                next unless Dir.exist?(path)
                next unless self.Na__PortalMapper__YearFolders(path).any?

                return path
            end

            nil
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | List The {NN}-Projects Folders In A Portal Root
        # ---------------------------------------------------------------
        def self.Na__PortalMapper__YearFolders(portal_root)
            pattern = Regexp.new(self.Na__PortalMapper__Config.dig('PortalRoots', 'YearFolderPattern') || '^(\\d{2})-Projects$')

            Dir.entries(portal_root)
                .select { |entry| entry =~ pattern }
                .select { |entry| Dir.exist?(File.join(portal_root, entry)) }
                .sort
                .reverse                                                        # <-- Newest year first
        rescue
            []
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Resolve The Repo Root (Parent Of The Portal Root)
        # ---------------------------------------------------------------
        def self.Na__PortalMapper__RepoRoot(portal_root)
            File.expand_path(File.join(portal_root.to_s, '..')).tr('\\', '/')
        end
        # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Project Code Resolution
    # -----------------------------------------------------------------------------

        # FUNCTION | Resolve A Project Code To Its Folder And Admin Data
        # ---------------------------------------------------------------
        # Tries the ProjectVision master index first, then falls back to scanning
        # the year folders for a directory whose name starts with the code. The
        # fallback matters for a project created since the last index build.
        # ---------------------------------------------------------------
        def self.Na__PortalMapper__ResolveProjectCode(raw_code, portal_override = nil)
            code = self.Na__ProjectLink__NormaliseCode(raw_code)
            return { success: false, message: "'#{raw_code}' is not a project code. Expected two letters and two digits, such as RB05." } unless code

            portal_root = self.Na__PortalMapper__ResolvePortalRoot(portal_override)
            unless portal_root
                return {
                    success: false,
                    message: 'Could not find the na-project-portal folder. Set the portal root in the Project tab.'
                }
            end

            entry = self.Na__PortalMapper__LookupInMasterIndex(code, portal_root) ||
                    self.Na__PortalMapper__ScanYearFoldersForCode(code, portal_root)

            unless entry
                return {
                    success: false,
                    message: "Project #{code} was not found in the portal. Check the code, or run the ProjectVision build to refresh the index."
                }
            end

            project_root = File.join(portal_root, "#{entry[:project_year]}-Projects", entry[:project_folder]).tr('\\', '/')
            unless Dir.exist?(project_root)
                return {
                    success: false,
                    message: "The index points at #{project_root}, but that folder does not exist."
                }
            end

            {
                success:        true,
                message:        "#{code} - #{entry[:project_name]}",
                project_code:   code,
                project_folder: entry[:project_folder],
                project_name:   entry[:project_name],
                project_year:   entry[:project_year],
                portal_root:    portal_root,
                project_root:   project_root,
                admin_data:     self.Na__PortalMapper__ReadProjectAdminData(project_root)
            }
        rescue => e
            Na__Log__Warn "[PortalMapper] Resolve failed: #{e.message}"
            { success: false, message: "#{e.class}: #{e.message}" }
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Look A Code Up In The ProjectVision Master Index
        # ---------------------------------------------------------------
        def self.Na__PortalMapper__LookupInMasterIndex(code, portal_root)
            index = self.Na__PortalMapper__MasterIndex(portal_root)
            return nil unless index

            entry = index.dig('projects', code)
            return nil unless entry

            {
                project_folder: entry['projectFolder'].to_s,
                project_name:   entry['projectName'].to_s,
                project_year:   entry['projectYear'].to_s
            }
        rescue
            nil
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Read The Master Index, Cached For The Session
        # ---------------------------------------------------------------
        def self.Na__PortalMapper__MasterIndex(portal_root)
            return @na_master_index if @na_master_index

            rel  = self.Na__PortalMapper__Config.dig('MasterIndex', 'RelativePath').to_s
            return nil if rel.empty?

            path = File.join(self.Na__PortalMapper__RepoRoot(portal_root), rel).tr('\\', '/')
            return nil unless File.exist?(path)

            @na_master_index = JSON.parse(File.read(path))
        rescue => e
            Na__Log__Warn "[PortalMapper] Could not read the master index: #{e.message}"
            nil
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Scan The Year Folders For A Project Code
        # ---------------------------------------------------------------
        # The index is rebuilt by ProjectVision, so a brand new project folder
        # may not be in it yet. Folder names are {CODE}__{Name} or {CODE}_-_{Name}.
        # ---------------------------------------------------------------
        def self.Na__PortalMapper__ScanYearFoldersForCode(code, portal_root)
            self.Na__PortalMapper__YearFolders(portal_root).each do |year_folder|
                year_path = File.join(portal_root, year_folder)
                year_code = year_folder[/\A(\d{2})/, 1].to_s

                Dir.entries(year_path).sort.each do |entry|
                    next unless entry =~ /\A#{Regexp.escape(code)}(?:__|_-_)(.+)\z/
                    next unless Dir.exist?(File.join(year_path, entry))

                    return {
                        project_folder: entry,
                        project_name:   Regexp.last_match(1).to_s.gsub(/([a-z])([A-Z])/, '\1 \2'),
                        project_year:   year_code
                    }
                end
            end

            nil
        rescue
            nil
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Read The Project's Rich Admin Data
        # ---------------------------------------------------------------
        # Returns only the fields worth showing in the dialog. Never returns the
        # project PIN or any contract signature data.
        # ---------------------------------------------------------------
        def self.Na__PortalMapper__ReadProjectAdminData(project_root)
            rel  = self.Na__PortalMapper__Config.dig('MasterIndex', 'ProjectConfigRel').to_s
            return {} if rel.empty?

            path = File.join(project_root, rel).tr('\\', '/')
            return {} unless File.exist?(path)

            config = JSON.parse(File.read(path))
            {
                project_name:  config['projectName'].to_s,
                brief_concise: config['projectBriefConcise'].to_s,
                created_date:  config['createdDate'].to_s,
                last_modified: config['lastModified'].to_s
            }
        rescue => e
            Na__Log__Warn "[PortalMapper] Could not read the project admin data: #{e.message}"
            {}
        end
        # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Design Phase Catalogue and Folder Naming
    # -----------------------------------------------------------------------------

        # FUNCTION | List The Canonical Design Phases
        # ---------------------------------------------------------------
        def self.Na__PortalMapper__DesignPhases
            Array(self.Na__PortalMapper__Config['DesignPhases'])
        end
        # ---------------------------------------------------------------

        # FUNCTION | Build A Canonical Folder Name For A Phase And Scheme
        # ---------------------------------------------------------------
        # {NN} in the template becomes a zero-padded scheme number. A phase that
        # does not support schemes ignores the number entirely.
        # ---------------------------------------------------------------
        def self.Na__PortalMapper__BuildFolderName(phase_id, scheme_number = 1)
            phase = self.Na__PortalMapper__DesignPhases.find { |p| p['PhaseId'].to_s == phase_id.to_s }
            return nil unless phase

            template = phase['FolderTemplate'].to_s
            return template unless phase['SupportsSchemes']

            template.gsub('{NN}', format('%02d', scheme_number.to_i))
        end
        # ---------------------------------------------------------------

        # FUNCTION | Identify Which Phase A Folder Name Belongs To
        # ---------------------------------------------------------------
        # Matches the canonical template first, then the phase's aliases. This is
        # what keeps DesignPhase01__ConceptDesign__ExistingBuilding recognised as
        # Existing Conditions without renaming anything on disk.
        # ---------------------------------------------------------------
        def self.Na__PortalMapper__IdentifyPhase(folder_name)
            name = folder_name.to_s

            self.Na__PortalMapper__DesignPhases.each do |phase|
                template = phase['FolderTemplate'].to_s

                if phase['SupportsSchemes']
                    regex = Regexp.new('\A' + Regexp.escape(template).gsub('\{NN\}', '(\d{1,3})') + '\z')
                    if (match = name.match(regex))
                        return {
                            phase_id:      phase['PhaseId'].to_s,
                            label:         phase['Label'].to_s,
                            scheme_number: match[1].to_i,
                            is_alias:      false
                        }
                    end
                elsif name == template
                    return { phase_id: phase['PhaseId'].to_s, label: phase['Label'].to_s, scheme_number: 0, is_alias: false }
                end

                next unless Array(phase['Aliases']).include?(name)

                return {
                    phase_id:      phase['PhaseId'].to_s,
                    label:         phase['Label'].to_s,
                    scheme_number: 0,
                    is_alias:      true
                }
            end

            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Suggest The Next Free Scheme Number For A Phase
        # ---------------------------------------------------------------
        def self.Na__PortalMapper__NextSchemeNumber(project_root, phase_id)
            used = self.Na__PortalMapper__ListPhaseFolders(project_root)
                .select { |folder| folder[:phase_id] == phase_id.to_s }
                .map    { |folder| folder[:scheme_number].to_i }

            return 1 if used.empty?

            (used.max + 1)
        end
        # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Phase Folder Discovery
    # -----------------------------------------------------------------------------

        # FUNCTION | List The Design Phase Folders Under TrueVision Content
        # ---------------------------------------------------------------
        # Applies the same skip rules as ProjectVision__BuildScript__.py, so what
        # the dialog lists is what the build will publish. Unlike the build, a
        # folder with no GLBs is still listed - an empty scheme folder is a real
        # thing the user needs to see when managing versions.
        # ---------------------------------------------------------------
        def self.Na__PortalMapper__ListPhaseFolders(project_root)
            content_path = File.join(project_root.to_s, self.Na__PortalMapper__ContentFolderName).tr('\\', '/')
            return [] unless Dir.exist?(content_path)

            skip_prefixes = Array(self.Na__PortalMapper__Config.dig('TrueVisionContent', 'SkipFolderPrefixes'))
            siteplan_name = self.Na__PortalMapper__Config.dig('TrueVisionContent', 'SitePlanFolderName').to_s

            folders = []
            Dir.entries(content_path).sort.each do |entry|
                next if entry == '.' || entry == '..'
                next if entry == siteplan_name
                next if skip_prefixes.any? { |prefix| entry.start_with?(prefix.to_s) }

                folder_path = File.join(content_path, entry)
                next unless Dir.exist?(folder_path)

                folders << self.Na__PortalMapper__DescribeFolder(folder_path, entry)
            end

            folders
        rescue => e
            Na__Log__Warn "[PortalMapper] Could not list the phase folders: #{e.message}"
            []
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Describe One Phase Folder For The Dialog
        # ---------------------------------------------------------------
        def self.Na__PortalMapper__DescribeFolder(folder_path, folder_name)
            glb_files  = Dir.glob(File.join(folder_path, '*.glb'))
            phase      = self.Na__PortalMapper__IdentifyPhase(folder_name)
            newest     = glb_files.map { |f| File.mtime(f) rescue nil }.compact.max

            {
                folder_name:   folder_name,
                folder_path:   folder_path.tr('\\', '/'),
                glb_count:     glb_files.length,
                last_written:  newest ? newest.strftime('%d-%b-%Y %H:%M') : '',
                phase_id:      phase ? phase[:phase_id]      : '',
                phase_label:   phase ? phase[:label]         : 'Unrecognised folder',
                scheme_number: phase ? phase[:scheme_number] : 0,
                is_alias:      phase ? phase[:is_alias]      : false,
                recognised:    !phase.nil?
            }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Resolve The Full Path A Phase Folder Would Occupy
        # ---------------------------------------------------------------
        def self.Na__PortalMapper__PhaseFolderPath(project_root, folder_name)
            File.join(project_root.to_s, self.Na__PortalMapper__ContentFolderName, folder_name.to_s).tr('\\', '/')
        end
        # ---------------------------------------------------------------

        # FUNCTION | Report What An Export Into A Folder Would Overwrite
        # ---------------------------------------------------------------
        # The caller shows this before writing. `exists` false means the folder
        # would be created, which needs no confirmation.
        # ---------------------------------------------------------------
        def self.Na__PortalMapper__InspectTargetFolder(project_root, folder_name)
            path = self.Na__PortalMapper__PhaseFolderPath(project_root, folder_name)

            unless Dir.exist?(path)
                return { exists: false, glb_count: 0, last_written: '', folder_path: path, folder_name: folder_name.to_s }
            end

            described = self.Na__PortalMapper__DescribeFolder(path, folder_name.to_s)
            described.merge(exists: true)
        end
        # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Scheme Creation
    # -----------------------------------------------------------------------------

        # FUNCTION | Create A New Design Phase / Scheme Folder
        # ---------------------------------------------------------------
        # Refuses to create a folder that already exists rather than silently
        # handing back a folder full of someone else's GLBs.
        # ---------------------------------------------------------------
        def self.Na__PortalMapper__CreatePhaseFolder(project_root, phase_id, scheme_number = nil)
            phase = self.Na__PortalMapper__DesignPhases.find { |p| p['PhaseId'].to_s == phase_id.to_s }
            return { success: false, message: "Unknown design phase: #{phase_id}" } unless phase

            number      = scheme_number || self.Na__PortalMapper__NextSchemeNumber(project_root, phase_id)
            folder_name = self.Na__PortalMapper__BuildFolderName(phase_id, number)
            folder_path = self.Na__PortalMapper__PhaseFolderPath(project_root, folder_name)

            if Dir.exist?(folder_path)
                return {
                    success:     false,
                    message:     "#{folder_name} already exists. Pick it as the target, or create the next scheme.",
                    folder_name: folder_name,
                    folder_path: folder_path
                }
            end

            # An existing-conditions alias folder already covers this phase
            if !phase['SupportsSchemes']
                alias_folder = self.Na__PortalMapper__ListPhaseFolders(project_root)
                    .find { |folder| folder[:phase_id] == phase_id.to_s }
                if alias_folder
                    return {
                        success:     false,
                        message:     "#{phase['Label']} already exists in this project as #{alias_folder[:folder_name]}. Use that folder rather than creating a second one.",
                        folder_name: alias_folder[:folder_name],
                        folder_path: alias_folder[:folder_path]
                    }
                end
            end

            FileUtils.mkdir_p(folder_path)

            {
                success:     true,
                message:     "Created #{folder_name}.",
                folder_name: folder_name,
                folder_path: folder_path
            }
        rescue => e
            Na__Log__Warn "[PortalMapper] Could not create the phase folder: #{e.message}"
            { success: false, message: "#{e.class}: #{e.message}" }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Duplicate An Existing Scheme Into The Next Scheme Number
        # ---------------------------------------------------------------
        # Copies the GLB files so the new scheme starts from the old one, which
        # is what "make me a Scheme 2" usually means in practice.
        # ---------------------------------------------------------------
        def self.Na__PortalMapper__DuplicateScheme(project_root, source_folder_name)
            phase = self.Na__PortalMapper__IdentifyPhase(source_folder_name)
            return { success: false, message: "#{source_folder_name} is not a recognised design phase folder." } unless phase

            unless self.Na__PortalMapper__DesignPhases.find { |p| p['PhaseId'].to_s == phase[:phase_id] }&.fetch('SupportsSchemes', false)
                return { success: false, message: "#{phase[:label]} does not carry schemes, so it cannot be duplicated." }
            end

            created = self.Na__PortalMapper__CreatePhaseFolder(project_root, phase[:phase_id])
            return created unless created[:success]

            source_path = self.Na__PortalMapper__PhaseFolderPath(project_root, source_folder_name)
            glb_files   = Dir.glob(File.join(source_path, '*.glb'))
            glb_files.each { |file| FileUtils.cp(file, created[:folder_path]) }

            created.merge(
                message: "Created #{created[:folder_name]} with #{glb_files.length} file(s) copied from #{source_folder_name}."
            )
        rescue => e
            Na__Log__Warn "[PortalMapper] Could not duplicate the scheme: #{e.message}"
            { success: false, message: "#{e.class}: #{e.message}" }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Move A Folder's Existing GLBs Into Its 00__Archive
        # ---------------------------------------------------------------
        # Called before an overwrite the user confirmed, so the previous export
        # is recoverable rather than simply gone.
        # ---------------------------------------------------------------
        def self.Na__PortalMapper__ArchiveFolderContents(folder_path)
            glb_files = Dir.glob(File.join(folder_path.to_s, '*.glb'))
            return { success: true, archived: 0, message: 'Nothing to archive.' } if glb_files.empty?

            archive_name = self.Na__PortalMapper__Config.dig('TrueVisionContent', 'ArchiveFolderName') || '00__Archive'
            stamp        = Time.now.strftime('%Y-%m-%d_%H%M%S')
            archive_path = File.join(folder_path.to_s, archive_name, stamp)

            FileUtils.mkdir_p(archive_path)
            glb_files.each { |file| FileUtils.mv(file, archive_path) }

            {
                success:  true,
                archived: glb_files.length,
                message:  "#{glb_files.length} previous GLB(s) moved into #{archive_name}/#{stamp}.",
                path:     archive_path.tr('\\', '/')
            }
        rescue => e
            Na__Log__Warn "[PortalMapper] Could not archive the folder contents: #{e.message}"
            { success: false, archived: 0, message: "#{e.class}: #{e.message}" }
        end
        # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

    end  # module GlbBuilderUtility
end  # module TrueVision3D

# =============================================================================
# END OF FILE
# =============================================================================
