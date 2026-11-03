# =============================================================================
# NA PAINTERLYNPR ASSETS - NPR EXPORT - NAMING
# =============================================================================
#
# FILE       : Na__PainterlyAssets__NprExport__Naming__.rb
# NAMESPACE  : Na__PainterlyAssets::Na__NprExportNaming
# PURPOSE    : Where NPR Export's pictures go and what each is called: the
#              folder (beside the model, or one chosen), the file name from its
#              pattern, a number when a file is already there, and the pixel
#              size a resolution gives on the engine's sheet.
# CREATED    : 01-Nov-2026 (v0.3.0)
#
# DESCRIPTION:
# - THE FOLDER: 'besideModel' is a folder beside the .skp (subfolder, made when
#   the first picture is exported; empty: the model's own folder); 'chosen' is
#   kept relative to the model's folder whenever it is on the same drive, so it
#   still resolves on Adam's other PC, where the projects sit under another
#   root. A chosen folder that is not on this PC is said, never made.
# - THE NAME: the pattern's tokens ({model}, {view}, {dpi}, {date}, {time},
#   {seed}) are filled in, spaces become underscores, anything Windows refuses
#   becomes an underscore, then the format's extension. Adam's default:
#   {model}__{view}__PainterlyNPR__{dpi}dpi__ (the engine names its own
#   stills the same way: PainterlyNPR__PenAndWash__Seed<n>__<w>x<h>__<dpi>dpi__).
# - A FILE ALREADY THERE: 'number' adds __02, __03 ... before the name's
#   closing underscores; 'replace' writes over it. Two pictures of one export
#   never share a name either way.
# - Pure Ruby on plain data, so the offline suites check it whole.
#
# =============================================================================

require 'pathname'

module Na__PainterlyAssets
    module Na__NprExportNaming

    # -------------------------------------------------------------------------
    # REGION | Constants
    # -------------------------------------------------------------------------

        NA_EXTENSIONS = { 'png' => '.png', 'jpeg' => '.jpg', 'pdf' => '.pdf' }.freeze unless defined?(NA_EXTENSIONS)
        NA_TOKENS     = %w[model view dpi date time seed].freeze                         unless defined?(NA_TOKENS)
        NA_MAX_NAME   = 150                                                             unless defined?(NA_MAX_NAME)
        NA_MAX_NUMBER = 999                                                             unless defined?(NA_MAX_NUMBER)
        NA_SHEET_FALLBACK = { 'name' => 'A3', 'widthMm' => 420.0, 'heightMm' => 297.0 }.freeze unless defined?(NA_SHEET_FALLBACK)

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | The Folder
    # -------------------------------------------------------------------------

        # FUNCTION | The Folder the Pictures Go To: { 'path', 'exists', 'make', 'problem' }
        # ------------------------------------------------------------
        # make: it may be made (a folder beside the model); a chosen folder never is.
        def self.Na__Naming__Folder(model_path, settings)
            model_dir = model_path.to_s.empty? ? nil : File.dirname(model_path.to_s.tr('\\', '/'))
            if settings['folderMode'] == 'chosen'
                stored = settings['folder'].to_s
                return { 'path' => nil, 'exists' => false, 'make' => false, 'problem' => 'Choose a folder for the pictures.' } if stored.empty?
                absolute = self.na_absolute?(stored)
                if !absolute && model_dir.nil?
                    return { 'path' => nil, 'exists' => false, 'make' => false, 'problem' => 'The folder is kept beside the model, and this model is not saved yet. Save it, or choose the folder again.' }
                end
                path = absolute ? stored : File.expand_path(stored, model_dir).tr('\\', '/')
                exists = File.directory?(path)
                problem = exists ? nil : "That folder is not on this PC (#{path}). Choose another."
                return { 'path' => path, 'exists' => exists, 'make' => false, 'problem' => problem }
            end
            return { 'path' => nil, 'exists' => false, 'make' => false, 'problem' => 'Save the model first: the pictures go in a folder beside it. Or choose a folder.' } if model_dir.nil?
            sub  = settings['subfolder'].to_s
            path = sub.empty? ? model_dir : File.join(model_dir, sub)
            { 'path' => path, 'exists' => File.directory?(path), 'make' => true, 'problem' => nil }
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Chosen Folder as It Is Kept: relative to the model's folder on the same drive, else whole
        # ------------------------------------------------------------
        def self.Na__Naming__StoreFolder(model_path, chosen)
            chosen = File.expand_path(chosen.to_s).tr('\\', '/')
            return chosen if model_path.to_s.empty?
            model_dir = File.dirname(File.expand_path(model_path.to_s)).tr('\\', '/')
            return chosen unless self.na_drive(chosen).casecmp(self.na_drive(model_dir)).zero?
            relative = Pathname.new(chosen).relative_path_from(Pathname.new(model_dir)).to_s.tr('\\', '/')
            relative.empty? ? '.' : relative
        rescue ArgumentError
            chosen
        end
        # ---------------------------------------------------------------

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | The Name
    # -------------------------------------------------------------------------

        # FUNCTION | A File Name From Its Pattern (no folder): tokens filled, made safe, the extension added
        # ------------------------------------------------------------
        # @param values [Hash] 'model', 'view', 'dpi', 'date', 'time', 'seed'
        def self.Na__Naming__FileName(pattern, values, format)
            text = pattern.to_s.gsub(/\{([A-Za-z]+)\}/) do |whole|
                key = Regexp.last_match(1).downcase
                NA_TOKENS.include?(key) ? self.na_safe(values[key].to_s) : whole
            end
            stem = self.na_safe(text).gsub(/_{3,}/, '__').gsub(/\A[ ._]+(?=[^_])|[ .]+\z/, '')
            stem = 'PainterlyNPR' if stem.gsub('_', '').empty?
            stem = stem[0, NA_MAX_NAME]
            "#{stem}#{NA_EXTENSIONS[format] || '.png'}"
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Token Values for One Picture
        # ------------------------------------------------------------
        def self.Na__Naming__Values(model_title, view_name, dpi, seed, now = Time.now)
            {
                'model' => model_title.to_s.empty? ? 'Untitled' : model_title.to_s,
                'view'  => view_name.to_s,
                'dpi'   => dpi.to_i.to_s,
                'date'  => now.strftime('%Y-%m-%d'),
                'time'  => now.strftime('%H%M'),
                'seed'  => seed.nil? ? '' : seed.to_s
            }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Text as a Piece of a File Name (spaces to underscores, nothing Windows refuses)
        # ------------------------------------------------------------
        def self.Na__Naming__Safe(text)
            self.na_safe(text)
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Path a Picture Is Written To
        # ------------------------------------------------------------
        # @param taken [Hash] lower-case paths already given to this export's pictures
        # @param replace [Boolean] write over a file already there (never over another of this export)
        # @return [String, nil] nil when every number up to 999 is taken
        def self.Na__Naming__Target(folder, name, taken, replace)
            path = File.join(folder, name)
            return self.na_take(path, taken) if !taken.key?(path.downcase) && (replace || !File.exist?(path))
            ext   = File.extname(name)
            stem  = File.basename(name, ext)
            tail  = stem[/_+\z/].to_s
            core  = stem.sub(/_+\z/, '')
            (2..NA_MAX_NUMBER).each do |n|
                candidate = File.join(folder, "#{core}__#{format('%02d', n)}#{tail}#{ext}")
                next if taken.key?(candidate.downcase)
                next if File.exist?(candidate)
                return self.na_take(candidate, taken)
            end
            nil
        end
        # ---------------------------------------------------------------

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | The Sheet and Its Pixels
    # -------------------------------------------------------------------------

        # FUNCTION | The Engine's Sheet: { 'name', 'widthMm', 'heightMm' } (the engine's own config, else A3)
        # ------------------------------------------------------------
        # Read from the cached engine's AppConfig (PainterlyNPR__AppConfig__Main__.json,
        # PainterlyNPR__AppConfig__Main__Sheet), or the viewport's own word.
        def self.Na__Naming__Sheet(engine_folder, said_mm = nil)
            if said_mm.is_a?(Array) && said_mm.length == 2 && said_mm.all? { |v| v.to_f > 0 }
                return NA_SHEET_FALLBACK.merge('widthMm' => said_mm[0].to_f, 'heightMm' => said_mm[1].to_f, 'name' => self.na_sheet_name(engine_folder))
            end
            sheet = self.na_engine_sheet(engine_folder)
            return NA_SHEET_FALLBACK.dup unless sheet
            { 'name' => sheet['SheetName'].to_s, 'widthMm' => sheet['SheetWidthMm'].to_f, 'heightMm' => sheet['SheetHeightMm'].to_f }
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Pixels a Resolution Gives on the Sheet: [width, height]
        # ------------------------------------------------------------
        # The engine's own sizing (its SheetPixels) lands within a pixel or two of this.
        def self.Na__Naming__Pixels(sheet, dpi)
            per_mm = dpi.to_f / 25.4
            [(sheet['widthMm'].to_f * per_mm).round, (sheet['heightMm'].to_f * per_mm).round]
        end
        # ---------------------------------------------------------------

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Internals
    # -------------------------------------------------------------------------

        # Spaces to underscores; what Windows refuses in a name to underscores
        def self.na_safe(text)
            text.to_s.strip.gsub(/\s+/, '_').gsub(%r{[<>:"/\\|?*\x00-\x1f]}, '_')
        end

        def self.na_take(path, taken)
            taken[path.downcase] = true
            path
        end

        def self.na_absolute?(path)
            path.match?(%r{\A([A-Za-z]:[/\\]|[/\\]{2}|/)})
        end

        def self.na_drive(path)
            path.to_s[/\A[A-Za-z]:/].to_s
        end

        def self.na_engine_sheet(engine_folder)
            return nil if engine_folder.to_s.empty?
            file = File.join(engine_folder, '02__Src__AppModules', '02__AppData', 'PainterlyNPR__AppConfig__Main__.json')
            data = Na__SafeFileWriter.Na__SafeFile__ReadJson(file)
            main = data && data['PainterlyNPR__AppConfig__Main']
            sheet = main.is_a?(Hash) ? main['PainterlyNPR__AppConfig__Main__Sheet'] : nil
            sheet.is_a?(Hash) && sheet['SheetWidthMm'].to_f > 0 && sheet['SheetHeightMm'].to_f > 0 ? sheet : nil
        rescue StandardError
            nil
        end

        def self.na_sheet_name(engine_folder)
            sheet = self.na_engine_sheet(engine_folder)
            sheet ? sheet['SheetName'].to_s : NA_SHEET_FALLBACK['name']
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
