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
require 'zlib'                                                            # <-- Pure-Ruby zip archive writing

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

        # FUNCTION | The Site Plan Variants A Project Can Hold
        # ---------------------------------------------------------------
        # A project may carry an EXISTING site plan and a PROPOSED one, because a
        # scheme that re-cuts the ground - a new lake, new woodland, new contours
        # - cannot be told with layers alone. Most jobs use only Proposed.
        #
        # The folder names keep the SitePlan__DrawingData stem on purpose:
        #   * one prefix finds every variant AND the legacy single folder, so
        #     discovery is a prefix test rather than a rewritten list;
        #   * a project exported before this existed keeps working untouched.
        # A bare SitePlan__DrawingData is read as Proposed - it is what every
        # single-store project already holds.
        # ---------------------------------------------------------------
        def self.Na__PortalMapper__SitePlanVariants
            [
                { variant_id: 'existing', label: 'Existing Site Plan',
                  folder_name: 'SitePlan__DrawingData__Existing',
                  note: 'The site as found - the survey, the base map, what is there now.' },
                { variant_id: 'proposed', label: 'Proposed Site Plan',
                  folder_name: 'SitePlan__DrawingData__Proposed',
                  note: 'The scheme - new buildings, new landscape, new levels.' }
            ]
        end
        # ---------------------------------------------------------------

        # FUNCTION | Identify A Site Plan Folder, Legacy Names Included
        # ---------------------------------------------------------------
        def self.Na__PortalMapper__IdentifySitePlanFolder(folder_name)
            name = folder_name.to_s
            return nil unless name.start_with?('SitePlan__DrawingData')

            variant = self.Na__PortalMapper__SitePlanVariants.find { |v| v[:folder_name] == name }
            return variant.merge(is_legacy: false) if variant

            # The original single-store folder. Read as Proposed, never renamed:
            # live TrueVision projects and published R2 keys point at this name.
            if name == 'SitePlan__DrawingData'
                return self.Na__PortalMapper__SitePlanVariants
                           .find { |v| v[:variant_id] == 'proposed' }
                           .merge(folder_name: name, label: 'Proposed Site Plan (original folder)', is_legacy: true)
            end

            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | List The Site Plan Folders A Project Holds
        # ---------------------------------------------------------------
        def self.Na__PortalMapper__ListSitePlanFolders(project_root)
            content_root = File.join(project_root.to_s, self.Na__PortalMapper__ContentFolderName)
            return [] unless Dir.exist?(content_root)

            Dir.entries(content_root).sort.each_with_object([]) do |entry, list|
                next if entry.start_with?('.')
                path = File.join(content_root, entry)
                next unless File.directory?(path)

                variant = self.Na__PortalMapper__IdentifySitePlanFolder(entry)
                next unless variant

                list << self.Na__PortalMapper__DescribeFolder(path, entry).merge(
                    variant_id:   variant[:variant_id],
                    variant_label: variant[:label],
                    is_legacy:    variant[:is_legacy] == true
                )
            end
        rescue => e
            Na__Log__Warn "[PortalMapper] Could not list the site plan folders: #{e.message}"
            []
        end
        # ---------------------------------------------------------------

        # FUNCTION | Create A Site Plan Folder For One Variant
        # ---------------------------------------------------------------
        def self.Na__PortalMapper__CreateSitePlanFolder(project_root, variant_id)
            variant = self.Na__PortalMapper__SitePlanVariants.find { |v| v[:variant_id] == variant_id.to_s }
            return { success: false, message: "Unknown site plan variant: #{variant_id}." } unless variant

            path = self.Na__PortalMapper__PhaseFolderPath(project_root, variant[:folder_name])

            if Dir.exist?(path)
                return { success: true, created: false, folder_name: variant[:folder_name], folder_path: path,
                         message: "#{variant[:label]} already exists." }
            end

            FileUtils.mkdir_p(path)
            { success: true, created: true, folder_name: variant[:folder_name], folder_path: path,
              message: "Created #{variant[:folder_name]}." }
        rescue => e
            Na__Log__Warn "[PortalMapper] Could not create the site plan folder: #{e.message}"
            { success: false, message: "#{e.class}: #{e.message}" }
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
    # REGION | Project Structure Tree
    # -----------------------------------------------------------------------------

        # FUNCTION | Describe The Project's TrueVision Folder Tree
        # ---------------------------------------------------------------
        # Rows are { depth, label, meta, kind, marker }. The UI renders them as a
        # tree, and the confirmation modals show the same rows so a destructive
        # action is read in the context of the whole project, not on its own.
        #
        # `marker` tags a row for emphasis:
        #   'target'  - the folder the model exports into
        #   'affected'- the folder this action is about to change
        # ---------------------------------------------------------------
        def self.Na__PortalMapper__BuildStructureTree(project_root, target_folder: nil, affected_folder: nil)
            rows = []
            return rows if project_root.to_s.empty? || !Dir.exist?(project_root.to_s)

            rows << { depth: 0, label: File.basename(project_root.to_s), meta: '', kind: 'project', marker: '' }

            content_name = self.Na__PortalMapper__ContentFolderName
            content_path = File.join(project_root.to_s, content_name)
            unless Dir.exist?(content_path)
                rows << { depth: 1, label: content_name, meta: '(missing)', kind: 'missing', marker: '' }
                return rows
            end

            rows << { depth: 1, label: content_name, meta: '', kind: 'content', marker: '' }

            self.Na__PortalMapper__ListPhaseFolders(project_root).each do |folder|
                marker = if folder[:folder_name] == affected_folder.to_s then 'affected'
                         elsif folder[:folder_name] == target_folder.to_s then 'target'
                         else ''
                         end

                meta = "#{folder[:glb_count]} GLB#{folder[:glb_count] == 1 ? '' : 's'}"
                meta += " · #{folder[:last_written]}" unless folder[:last_written].to_s.empty?
                meta += ' · legacy name' if folder[:is_alias]

                rows << {
                    depth:  2,
                    label:  folder[:folder_name],
                    meta:   meta,
                    kind:   'phase',
                    marker: marker
                }
            end

            # The site plan store and the archive are shown for context, greyed out
            siteplan_name = self.Na__PortalMapper__Config.dig('TrueVisionContent', 'SitePlanFolderName').to_s
            siteplan_path = File.join(content_path, siteplan_name)
            if !siteplan_name.empty? && Dir.exist?(siteplan_path)
                count = Dir.glob(File.join(siteplan_path, '*.glb')).length
                rows << { depth: 2, label: siteplan_name, meta: "#{count} GLB#{count == 1 ? '' : 's'} · not a design phase", kind: 'aside', marker: '' }
            end

            archive_name = self.Na__PortalMapper__Config.dig('TrueVisionContent', 'ArchiveFolderName').to_s
            archive_path = File.join(content_path, archive_name)
            if !archive_name.empty? && Dir.exist?(archive_path)
                entries = Dir.entries(archive_path).reject { |e| e == '.' || e == '..' }.length
                rows << { depth: 2, label: archive_name, meta: "#{entries} item(s) · skipped by the build", kind: 'aside', marker: '' }
            end

            rows
        rescue => e
            Na__Log__Warn "[PortalMapper] Could not build the structure tree: #{e.message}"
            []
        end
        # ---------------------------------------------------------------

        # FUNCTION | Pick The Scheme A Newly Linked Model Should Target
        # ---------------------------------------------------------------
        # The most common action is re-exporting over the latest concept scheme,
        # so the default target is the most recently written folder. Ties and
        # never-written folders fall back to the highest scheme number.
        # ---------------------------------------------------------------
        def self.Na__PortalMapper__SuggestTargetFolder(project_root)
            folders = self.Na__PortalMapper__ListPhaseFolders(project_root)
            return nil if folders.empty?

            written = folders.reject { |folder| folder[:last_written].to_s.empty? }
            pool    = written.any? ? written : folders

            pool.max_by do |folder|
                path  = folder[:folder_path]
                mtime = Dir.glob(File.join(path, '*.glb')).map { |f| File.mtime(f) rescue nil }.compact.max
                [mtime ? mtime.to_i : 0, folder[:scheme_number].to_i]
            end
        rescue
            nil
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

        # FUNCTION | Delete A Design Phase Folder
        # ---------------------------------------------------------------
        # Archiving is the default and the safe path: the folder moves into the
        # content folder's 00__Archive, which the build script skips, so the
        # scheme disappears from TrueVision__ProjectData__.json while the files
        # stay recoverable on disk. `permanent` really does remove it.
        #
        # NOTE | Neither mode touches Cloudflare R2. The sync only uploads; the
        # sole remote deletion path is CloudflareR2__ModelSync__Main__.py --purge,
        # which is interactive and purges every GLB for a project code. Files
        # already pushed stay in the bucket, orphaned but invisible to the app.
        # ---------------------------------------------------------------
        def self.Na__PortalMapper__DeletePhaseFolder(project_root, folder_name, permanent: false)
            name = folder_name.to_s
            return { success: false, message: 'No folder name given.' } if name.empty?

            folder_path = self.Na__PortalMapper__PhaseFolderPath(project_root, name)
            unless Dir.exist?(folder_path)
                return { success: false, message: "#{name} does not exist." }
            end

            glb_count = Dir.glob(File.join(folder_path, '*.glb')).length

            if permanent
                FileUtils.rm_rf(folder_path)
                return {
                    success:   true,
                    permanent: true,
                    message:   "#{name} permanently deleted (#{glb_count} GLB file(s)). Any copies already in R2 remain there until purged."
                }
            end

            archive_name = self.Na__PortalMapper__Config.dig('TrueVisionContent', 'ArchiveFolderName') || '00__Archive'
            stamp        = Time.now.strftime('%Y-%m-%d_%H%M%S')
            archive_root = File.join(project_root.to_s, self.Na__PortalMapper__ContentFolderName, archive_name, "Deleted__#{stamp}")

            FileUtils.mkdir_p(archive_root)
            FileUtils.mv(folder_path, File.join(archive_root, name))

            {
                success:   true,
                permanent: false,
                message:   "#{name} moved into #{archive_name}/Deleted__#{stamp} (#{glb_count} GLB file(s)). Any copies already in R2 remain there until purged.",
                path:      archive_root.tr('\\', '/')
            }
        rescue => e
            Na__Log__Warn "[PortalMapper] Could not delete the phase folder: #{e.message}"
            { success: false, message: "#{e.class}: #{e.message}" }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Zip A Folder's Existing GLBs Into Its 00__Archive
        # ---------------------------------------------------------------
        # Called before an overwrite the user confirmed, so the previous export
        # is recoverable rather than simply gone. The GLBs are compressed into a
        # single dated zip and the loose originals removed, which keeps the live
        # folder clean and the archive small.
        #
        # NOTE | The archive is LOCAL ONLY. It lands in 00__Archive, which the
        # build script skips, so it never becomes a model group and is never
        # uploaded to Cloudflare R2.
        # ---------------------------------------------------------------
        # `only_files`, when given, limits which originals are REMOVED after the
        # zip is written. The zip itself always captures the whole folder, so the
        # archive stays a complete snapshot of what was there. This is what keeps
        # a partial export - "just the furniture" - from deleting everything else.
        def self.Na__PortalMapper__ArchiveFolderContents(folder_path, project_code: '', stage_name: '', only_files: nil)
            glb_files = Dir.glob(File.join(folder_path.to_s, '*.glb'))
            return { success: true, archived: 0, message: 'Nothing to archive.' } if glb_files.empty?

            archive_name = self.Na__PortalMapper__Config.dig('TrueVisionContent', 'ArchiveFolderName') || '00__Archive'
            archive_dir  = File.join(folder_path.to_s, archive_name)
            FileUtils.mkdir_p(archive_dir)

            zip_name = self.Na__PortalMapper__BuildArchiveFileName(
                project_code: project_code,
                stage_name:   stage_name.to_s.empty? ? File.basename(folder_path.to_s) : stage_name
            )
            zip_path = File.join(archive_dir, zip_name)
            zip_path = self.Na__PortalMapper__UniquePath(zip_path)

            self.Na__PortalMapper__WriteZipArchive(zip_path, glb_files)

            # Only clear the originals once the archive is safely on disk
            unless File.exist?(zip_path) && File.size(zip_path) > 0
                return { success: false, archived: 0, message: 'The archive could not be written, so nothing was removed.' }
            end

            # Remove only what is about to be rewritten; anything toggled off stays
            removable = if only_files.nil?
                glb_files
            else
                wanted = Array(only_files).each_with_object({}) { |name, hash| hash[name.to_s] = true }
                glb_files.select { |file| wanted[File.basename(file)] }
            end
            removable.each { |file| File.delete(file) }

            kept = glb_files.length - removable.length
            note = kept.zero? ? '' : " #{kept} toggled-off file(s) left in place."

            {
                success:  true,
                archived: glb_files.length,
                message:  "#{glb_files.length} previous GLB(s) zipped into #{archive_name}/#{File.basename(zip_path)} " \
                          "(local only, never uploaded).#{note}",
                path:     zip_path.tr('\\', '/')
            }
        rescue => e
            Na__Log__Warn "[PortalMapper] Could not archive the folder contents: #{e.message}"
            { success: false, archived: 0, message: "#{e.class}: #{e.message}" }
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Build The Dated Archive File Name
        # ---------------------------------------------------------------
        #   {ProjectCode}__TrueVision__ArchivedModels__{Stage}__Archived__19-Sep-2026.zip
        # ---------------------------------------------------------------
        def self.Na__PortalMapper__BuildArchiveFileName(project_code: '', stage_name: '')
            code  = project_code.to_s.strip
            code  = 'Project' if code.empty?
            stage = stage_name.to_s.strip
            stage = 'Models' if stage.empty?
            date  = Time.now.strftime('%d-%b-%Y')

            "#{code}__TrueVision__ArchivedModels__#{stage}__Archived__#{date}.zip"
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Avoid Clobbering An Archive Made Earlier Today
        # ---------------------------------------------------------------
        def self.Na__PortalMapper__UniquePath(path)
            return path unless File.exist?(path)

            dir  = File.dirname(path)
            ext  = File.extname(path)
            base = File.basename(path, ext)

            (2..99).each do |index|
                candidate = File.join(dir, "#{base}__#{index}#{ext}")
                return candidate unless File.exist?(candidate)
            end

            File.join(dir, "#{base}__#{Time.now.strftime('%H%M%S')}#{ext}")
        end
        # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | ZIP Archive Writing
    # -----------------------------------------------------------------------------
    #
    # A minimal PKZIP writer built on Ruby's bundled zlib, so archiving needs no
    # external gem and no shelling out. Ported from the ValeVision Cloud Sync
    # GLB archiver, which has been writing these archives in production.
    #
    # -----------------------------------------------------------------------------

        # HELPER FUNCTION | Write A ZIP Archive From A List Of File Paths
        # ---------------------------------------------------------------
        # Each entry is deflated individually, then the central directory and the
        # end-of-central-directory record are appended.
        # ---------------------------------------------------------------
        def self.Na__PortalMapper__WriteZipArchive(archive_path, file_paths)
            central_directory = []

            File.open(archive_path, 'wb') do |zip_io|
                file_paths.each do |file_path|
                    next unless File.exist?(file_path)

                    local_file_name = File.basename(file_path)
                    file_data       = File.binread(file_path)
                    crc32           = Zlib.crc32(file_data)
                    compressed_data = Zlib::Deflate.deflate(file_data, Zlib::DEFAULT_COMPRESSION)

                    local_header_offset = zip_io.tell

                    zip_io.write(
                        self.Na__PortalMapper__ZipLocalHeader(
                            local_file_name, file_data.bytesize, compressed_data.bytesize, crc32
                        )
                    )
                    zip_io.write(compressed_data)

                    central_directory << {
                        name:              local_file_name,
                        offset:            local_header_offset,
                        crc32:             crc32,
                        compressed_size:   compressed_data.bytesize,
                        uncompressed_size: file_data.bytesize
                    }
                end

                central_dir_offset = zip_io.tell
                central_directory.each do |entry|
                    zip_io.write(self.Na__PortalMapper__ZipCentralEntry(entry))
                end
                central_dir_size = zip_io.tell - central_dir_offset

                zip_io.write(
                    self.Na__PortalMapper__ZipEndOfCentralDirectory(
                        central_directory.size, central_dir_size, central_dir_offset
                    )
                )
            end
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Build A Local File Header (PK\x03\x04)
        # ---------------------------------------------------------------
        def self.Na__PortalMapper__ZipLocalHeader(name, uncompressed_size, compressed_size, crc32)
            name_bytes    = name.encode('UTF-8').b
            mtime_dostime = self.Na__PortalMapper__ZipDosMtime

            [
                0x04034b50,          # Local file header signature
                20,                  # Version needed: 2.0
                0,                   # General purpose bit flag
                8,                   # Compression method: deflate
                mtime_dostime[0],    # Last mod file time
                mtime_dostime[1],    # Last mod file date
                crc32,               # CRC-32
                compressed_size,     # Compressed size
                uncompressed_size,   # Uncompressed size
                name_bytes.bytesize, # File name length
                0                    # Extra field length
            ].pack('VvvvvVVVvv') + name_bytes
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Build A Central Directory Entry (PK\x01\x02)
        # ---------------------------------------------------------------
        def self.Na__PortalMapper__ZipCentralEntry(entry)
            name_bytes    = entry[:name].encode('UTF-8').b
            mtime_dostime = self.Na__PortalMapper__ZipDosMtime

            [
                0x02014b50,                # Central directory signature
                20,                        # Version made by (MS-DOS 2.0)
                20,                        # Version needed to extract
                0,                         # General purpose bit flag
                8,                         # Compression method: deflate
                mtime_dostime[0],          # Last mod file time
                mtime_dostime[1],          # Last mod file date
                entry[:crc32],             # CRC-32
                entry[:compressed_size],   # Compressed size
                entry[:uncompressed_size], # Uncompressed size
                name_bytes.bytesize,       # File name length
                0,                         # Extra field length
                0,                         # File comment length
                0,                         # Disk number start
                0,                         # Internal file attributes
                0,                         # External file attributes
                entry[:offset]             # Relative offset of local header
            ].pack('VvvvvvvVVVvvvvvVV') + name_bytes
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Build The End Of Central Directory Record (PK\x05\x06)
        # ---------------------------------------------------------------
        def self.Na__PortalMapper__ZipEndOfCentralDirectory(count, central_dir_size, central_dir_offset)
            [
                0x06054b50,      # End of central directory signature
                0,               # Disk number
                0,               # Disk where central directory starts
                count,           # Number of entries on this disk
                count,           # Total entries
                central_dir_size,
                central_dir_offset,
                0                # Comment length
            ].pack('VvvvvVVv')
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Current Time As An MS-DOS Time / Date Pair
        # ---------------------------------------------------------------
        def self.Na__PortalMapper__ZipDosMtime
            now      = Time.now
            dos_time = ((now.hour << 11) | (now.min << 5) | (now.sec / 2))
            dos_date = (((now.year - 1980) << 9) | (now.month << 5) | now.mday)
            [dos_time, dos_date]
        end
        # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

    end  # module GlbBuilderUtility
end  # module TrueVision3D

# =============================================================================
# END OF FILE
# =============================================================================
