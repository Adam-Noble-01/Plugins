# =============================================================================
# NA PAINTERLYNPR ASSETS - APP UTILS - SAFE FILE WRITER
# =============================================================================
#
# FILE       : Na__PainterlyAssets__AppUtils__SafeFileWriter__.rb
# NAMESPACE  : Na__PainterlyAssets::Na__SafeFileWriter
# PURPOSE    : Transactional writes (`<target>.part`, then a rename over the
#              target) and JSON written exactly as PainterlyNPR's Python writes
#              it, so a DAT record this plugin touches diffs only where it
#              changed.
# CREATED    : 30-Oct-2026
#
# WHY NOT JSON.pretty_generate:
#   PainterlyNPR's build utility and local server write every DAT with
#   json.dumps(indent=4, ensure_ascii=False) plus a newline. Ruby's own pretty
#   printer opens an empty object over two lines ("Params": {\n}) where Python
#   writes "Params": {}, so 8 of the 26 seeded DATs came back different
#   (measured 30-Oct-2026 on SketchUp 2026's Ruby). This writer reproduces
#   Python's form: empty {} and [] inline, ": " and "," separators, non-ASCII
#   kept as it is, control characters as \u00XX, floats in Python's shortest
#   form (1e-05, never Ruby's 1.0e-05).
#
# =============================================================================

module Na__PainterlyAssets
    module Na__SafeFileWriter

    # -------------------------------------------------------------------------
    # REGION | Constants
    # -------------------------------------------------------------------------

        NA_JSON_ESCAPES = {
            '"'  => '\\"',  '\\' => '\\\\', "\n" => '\\n', "\r" => '\\r',
            "\t" => '\\t',  "\b" => '\\b',  "\f" => '\\f'
        }.freeze unless defined?(NA_JSON_ESCAPES)

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Public Surface
    # -------------------------------------------------------------------------

        # FUNCTION | Write Text Atomically
        # ------------------------------------------------------------
        # A failure leaves either the old file or none, never half of one.
        def self.Na__SafeFile__WriteText(path, text)
            FileUtils.mkdir_p(File.dirname(path))
            temp_path = "#{path}.part"
            File.open(temp_path, 'wb') { |file| file.write(text) }
            self.na_replace(temp_path, path)
            path
        ensure
            File.delete(temp_path) if temp_path && File.exist?(temp_path)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Write JSON in Python's Form (indent spaces, a newline at the end)
        # ------------------------------------------------------------
        def self.Na__SafeFile__WriteJson(path, data, indent = 4)
            self.Na__SafeFile__WriteText(path, self.Na__Json__Python(data, indent) + "\n")
        end
        # ---------------------------------------------------------------

        # FUNCTION | Read a JSON Object, or nil
        # ------------------------------------------------------------
        def self.Na__SafeFile__ReadJson(path)
            return nil unless File.file?(path)
            parsed = JSON.parse(File.read(path, encoding: 'bom|utf-8'))
            parsed.is_a?(Hash) ? parsed : nil
        rescue JSON::ParserError, SystemCallError => error
            Na__DebugTools.Na__Debug__Warn("Could not read #{File.basename(path)}: #{error.message}")
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | JSON Text as Python's json.dumps(value, indent=N, ensure_ascii=False)
        # ------------------------------------------------------------
        def self.Na__Json__Python(value, indent = 4)
            self.na_json_value(value, ' ' * indent, 0)
        end
        # ---------------------------------------------------------------

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Internals
    # -------------------------------------------------------------------------

        def self.na_json_value(value, pad, level)
            case value
            when Hash
                return '{}' if value.empty?
                inner = pad * (level + 1)
                items = value.map { |key, item| "#{inner}#{self.na_json_string(key.to_s)}: #{self.na_json_value(item, pad, level + 1)}" }
                "{\n#{items.join(",\n")}\n#{pad * level}}"
            when Array
                return '[]' if value.empty?
                inner = pad * (level + 1)
                items = value.map { |item| "#{inner}#{self.na_json_value(item, pad, level + 1)}" }
                "[\n#{items.join(",\n")}\n#{pad * level}]"
            when String, Symbol then self.na_json_string(value.to_s)
            when nil   then 'null'
            when true  then 'true'
            when false then 'false'
            when Integer then value.to_s
            else
                return self.na_json_float(value.to_f) if value.respond_to?(:to_f)          # <-- Float, and SketchUp's Length
                raise TypeError, "#{value.class} cannot be written to JSON"
            end
        end

        def self.na_json_float(number)
            raise ArgumentError, "#{number} is not a finite number" unless number.finite?
            number.to_s.sub(/\.0e/, 'e')                                                    # <-- Ruby writes 1.0e-05 where Python writes 1e-05
        end

        def self.na_json_string(text)
            clean = text.to_s.dup.force_encoding('UTF-8')
            clean = clean.scrub('?') unless clean.valid_encoding?
            body  = clean.gsub(/["\\\x00-\x1f]/) { |char| NA_JSON_ESCAPES[char] || format('\\u%04x', char.ord) }
            "\"#{body}\""
        end

        # Windows rename refuses to replace an open or locked target on some
        # setups; fall back to delete-then-rename so the write still lands.
        def self.na_replace(temp_path, path)
            File.rename(temp_path, path)
        rescue SystemCallError
            File.delete(path) if File.exist?(path)
            File.rename(temp_path, path)
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
