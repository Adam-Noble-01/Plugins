# =============================================================================
# NA NOBLE3D MODELLING TOOLS - PDF VECTOR IMPORTER - PDF READER
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__PdfVectorImporter__PdfReader__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__PdfVectorImporter__PdfReader
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Read a PDF file, locate page content streams, decode them, and
#              return decoded per-page content text for the content parser.
# CREATED    : 2026
#
# DESCRIPTION:
# - Reads the file as binary and scans every indirect object (xref-independent).
# - Extracts and decodes stream bodies (FlateDecode, ASCII85, ASCIIHex, raw).
# - Decodes /Type /ObjStm object streams so PDF 1.5+ page dictionaries are found.
# - Resolves the page order via the catalog page tree, with scan fallbacks.
#
# SUPPORTED  : FlateDecode, ASCII85Decode, ASCIIHexDecode, uncompressed streams.
# UNSUPPORTED: Encrypted PDFs and LZWDecode streams (reported as no vector data).
#
# =============================================================================

require 'zlib'

module Na__Noble3dModellingTools
    module Na__PdfVectorImporter__PdfReader

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        STREAM_KEYWORD_LENGTH = 'stream'.length
        ENDOBJ_KEYWORD_LENGTH = 'endobj'.length
        MAX_PAGE_TREE_DEPTH   = 50

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public Entry Point
# -----------------------------------------------------------------------------

        # FUNCTION | Read a PDF File and Return Decoded Per-Page Content
        # ------------------------------------------------------------
        def self.Na__PdfVectorImporter__ReadPages(file_path)
            raw = File.binread(file_path)
            raw.force_encoding(Encoding::ASCII_8BIT)
            return { pages: [], message: 'The selected file is empty.' } if raw.empty?
            unless raw[0, 1024].include?('%PDF')
                return { pages: [], message: 'The selected file does not appear to be a valid PDF.' }
            end
            if na_is_encrypted?(raw)
                return { pages: [], message: 'This PDF is encrypted, which is not supported.' }
            end

            objects = na_scan_indirect_objects(raw)
            na_merge_object_streams(objects)

            page_ids = na_resolve_page_order(raw, objects)
            page_ids = na_fallback_page_scan(objects) if page_ids.empty?

            pages = page_ids.map { |page_id| na_assemble_page_content(objects, page_id) }
            pages = pages.reject { |content| content.nil? || content.empty? }

            if pages.empty?
                merged = na_gather_all_content_streams(objects)
                pages  = [merged] unless merged.empty?
            end

            message = pages.empty? ? 'No decodable page content was found in this PDF.' : 'OK'
            { pages: pages, message: message }
        rescue => error
            { pages: [], message: "Failed to read PDF: #{error.class}: #{error.message}" }
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Indirect Object Scanning
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Scan All "N G obj ... endobj" Indirect Objects
        # ------------------------------------------------------------
        def self.na_scan_indirect_objects(raw)
            objects    = {}
            header_re  = /(\d+)\s+(\d+)\s+obj/n
            scan_pos   = 0

            while (match = header_re.match(raw, scan_pos))
                object_number = match[1].to_i
                body_start    = match.end(0)
                stream_at     = raw.index('stream', body_start)
                endobj_at     = raw.index('endobj', body_start)

                if stream_at && (endobj_at.nil? || stream_at < endobj_at)
                    dictionary = raw[body_start...stream_at]
                    data_start = stream_at + STREAM_KEYWORD_LENGTH
                    data_start += 1 if raw.getbyte(data_start) == 13      # CR
                    data_start += 1 if raw.getbyte(data_start) == 10      # LF
                    endstream_at = raw.index('endstream', data_start) || raw.length
                    objects[object_number] = {
                        dict:       dictionary,
                        has_stream: true,
                        data_start: data_start,
                        endstream:  endstream_at,
                        stream:     nil
                    }
                    after_endstream = raw.index('endobj', endstream_at) || endstream_at
                    scan_pos        = after_endstream + ENDOBJ_KEYWORD_LENGTH
                else
                    dictionary = endobj_at ? raw[body_start...endobj_at] : raw[body_start..]
                    objects[object_number] = { dict: dictionary, has_stream: false }
                    scan_pos = (endobj_at || raw.length) + ENDOBJ_KEYWORD_LENGTH
                end
            end

            objects.each_value do |record|
                next unless record[:has_stream]
                record[:stream] = na_extract_stream_bytes(raw, record, objects)
            end
            objects
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Slice the Raw Bytes of a Single Stream Object
        # ------------------------------------------------------------
        def self.na_extract_stream_bytes(raw, record, objects)
            length = na_dictionary_length(record[:dict], objects)
            if length && length >= 0 && (record[:data_start] + length) <= raw.length
                tail = raw[record[:data_start] + length, 20] || ''
                return raw[record[:data_start], length] if tail.include?('endstream')
            end
            slice = raw[record[:data_start]...record[:endstream]] || ''
            slice.sub(/\r?\n\z/n, '')
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Resolve a Stream Dictionary /Length (direct or indirect)
        # ------------------------------------------------------------
        def self.na_dictionary_length(dictionary, objects)
            if dictionary =~ /\/Length\s+(\d+)\s+(\d+)\s+R/n
                referenced = objects[$1.to_i]
                return referenced[:dict][/\d+/].to_i if referenced && referenced[:dict] =~ /\d/
                nil
            elsif dictionary =~ /\/Length\s+(\d+)/n
                $1.to_i
            end
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Object Stream Merging (PDF 1.5+)
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Decode /Type /ObjStm Streams into Individual Objects
        # ------------------------------------------------------------
        def self.na_merge_object_streams(objects)
            object_stream_ids = objects.select do |_, record|
                record[:has_stream] && record[:dict] =~ /\/Type\s*\/ObjStm/n
            end.keys

            object_stream_ids.each do |stream_id|
                record  = objects[stream_id]
                decoded = na_decode_stream(record[:dict], record[:stream])
                next unless decoded

                count = (record[:dict][/\/N\s+(\d+)/n, 1] || '0').to_i
                first = (record[:dict][/\/First\s+(\d+)/n, 1] || '0').to_i
                next if count <= 0 || first <= 0

                header = decoded[0, first] || ''
                pairs  = header.scan(/(\d+)\s+(\d+)/n).first(count)

                pairs.each_with_index do |(number, offset), index|
                    start_at = first + offset.to_i
                    stop_at  = index + 1 < pairs.length ? first + pairs[index + 1][1].to_i : decoded.length
                    body     = decoded[start_at...stop_at]
                    next if body.nil?
                    objects[number.to_i] ||= { dict: body, has_stream: false }
                end
            end
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Stream Decoding
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Decode a Stream Through its Filter Chain
        # ------------------------------------------------------------
        def self.na_decode_stream(dictionary, bytes)
            return nil if bytes.nil?
            data = bytes
            na_dictionary_filters(dictionary).each do |filter|
                case filter
                when 'FlateDecode', 'Fl'
                    data = na_inflate(data)
                    data = na_apply_predictor(dictionary, data) if dictionary =~ /\/Predictor/n
                when 'ASCII85Decode', 'A85'
                    data = na_ascii85_decode(data)
                when 'ASCIIHexDecode', 'AHx'
                    data = na_asciihex_decode(data)
                else
                    return nil                                        # <-- LZW / image / unsupported filter
                end
                return nil if data.nil?
            end
            data
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Return the Ordered Filter Names of a Dictionary
        # ------------------------------------------------------------
        def self.na_dictionary_filters(dictionary)
            filter_part = dictionary[/\/Filter\s*(\[[^\]]*\]|\/[A-Za-z0-9]+)/n, 1]
            return [] unless filter_part
            filter_part.scan(/\/([A-Za-z0-9]+)/n).flatten
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Inflate Flate / Zlib Data Tolerantly
        # ------------------------------------------------------------
        def self.na_inflate(data)
            return '' if data.nil? || data.empty?
            [Zlib::MAX_WBITS, -Zlib::MAX_WBITS, Zlib::MAX_WBITS + 32].each do |window_bits|
                begin
                    inflater = Zlib::Inflate.new(window_bits)
                    output   = inflater.inflate(data)
                    output << inflater.finish rescue nil
                    inflater.close
                    return output unless output.empty?
                rescue
                    next
                end
            end
            (Zlib::Inflate.inflate(data) rescue '')
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Apply PNG / TIFF Predictor Post-Inflate
        # ------------------------------------------------------------
        def self.na_apply_predictor(dictionary, data)
            params    = dictionary[/\/DecodeParms\s*<<(.*?)>>/mn, 1] || dictionary
            predictor = (params[/\/Predictor\s+(\d+)/n, 1] || '1').to_i
            return data if predictor <= 1

            colors  = (params[/\/Colors\s+(\d+)/n, 1] || '1').to_i
            bpc     = (params[/\/BitsPerComponent\s+(\d+)/n, 1] || '8').to_i
            columns = (params[/\/Columns\s+(\d+)/n, 1] || '1').to_i
            bpp     = [((colors * bpc) + 7) / 8, 1].max
            row_len = ((colors * bpc * columns) + 7) / 8
            return data if row_len <= 0

            bytes  = data.bytes
            output = []

            if predictor == 2
                index = 0
                while index < bytes.length
                    row = bytes[index, row_len]
                    break if row.nil? || row.empty?
                    (bpp...row.length).each { |k| row[k] = (row[k] + row[k - bpp]) & 0xFF }
                    output.concat(row)
                    index += row_len
                end
                return output.pack('C*')
            end

            previous = Array.new(row_len, 0)
            stride   = row_len + 1
            index    = 0
            while index < bytes.length
                filter_type = bytes[index]
                break if filter_type.nil?
                row = bytes[index + 1, row_len] || []
                row << 0 while row.length < row_len
                na_unfilter_png_row(row, previous, filter_type, bpp, row_len)
                output.concat(row)
                previous = row
                index += stride
            end
            output.pack('C*')
        rescue
            data
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Reverse One PNG Predictor Row In Place
        # ------------------------------------------------------------
        def self.na_unfilter_png_row(row, previous, filter_type, bpp, row_len)
            case filter_type
            when 1                                                    # Sub
                (0...row_len).each { |k| row[k] = (row[k] + (k >= bpp ? row[k - bpp] : 0)) & 0xFF }
            when 2                                                    # Up
                (0...row_len).each { |k| row[k] = (row[k] + previous[k]) & 0xFF }
            when 3                                                    # Average
                (0...row_len).each do |k|
                    left = k >= bpp ? row[k - bpp] : 0
                    row[k] = (row[k] + ((left + previous[k]) >> 1)) & 0xFF
                end
            when 4                                                    # Paeth
                (0...row_len).each do |k|
                    left       = k >= bpp ? row[k - bpp] : 0
                    upper      = previous[k]
                    upper_left = k >= bpp ? previous[k - bpp] : 0
                    row[k] = (row[k] + na_paeth_predictor(left, upper, upper_left)) & 0xFF
                end
            end
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Paeth Predictor Selection
        # ------------------------------------------------------------
        def self.na_paeth_predictor(left, upper, upper_left)
            estimate = left + upper - upper_left
            da = (estimate - left).abs
            db = (estimate - upper).abs
            dc = (estimate - upper_left).abs
            return left  if da <= db && da <= dc
            return upper if db <= dc
            upper_left
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Decode ASCII85 Encoded Data
        # ------------------------------------------------------------
        def self.na_ascii85_decode(data)
            text = data.gsub(/\s/n, '')
            text = text[2..] if text.start_with?('<~')
            text = text[0...-2] if text.end_with?('~>')
            output = +''.b
            index  = 0
            while index < text.length
                if text[index] == 'z'
                    output << "\x00\x00\x00\x00".b
                    index += 1
                    next
                end
                chunk   = text[index, 5]
                break if chunk.nil? || chunk.empty?
                padding = 5 - chunk.length
                chunk   = chunk + ('u' * padding)
                value   = 0
                chunk.each_char { |character| value = (value * 85) + (character.ord - 33) }
                quad = [(value >> 24) & 0xFF, (value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF]
                output << quad[0, 4 - padding].pack('C*')
                index += 5
            end
            output
        rescue
            nil
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Decode ASCIIHex Encoded Data
        # ------------------------------------------------------------
        def self.na_asciihex_decode(data)
            hex = data.gsub(/\s/n, '')
            hex = hex.split('>').first || ''
            hex = hex + '0' if hex.length.odd?
            [hex].pack('H*')
        rescue
            nil
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Page Resolution
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Resolve Page Order from the Catalog Page Tree
        # ------------------------------------------------------------
        def self.na_resolve_page_order(raw, objects)
            root_id = na_find_root_id(raw, objects)
            return [] unless root_id
            catalog = objects[root_id]
            return [] unless catalog
            pages_id = na_dictionary_ref(catalog[:dict], 'Pages')
            return [] unless pages_id

            order   = []
            visited = {}
            na_collect_page_leaves(objects, pages_id, order, visited, 0)
            order
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Locate the Catalog (Root) Object Number
        # ------------------------------------------------------------
        def self.na_find_root_id(raw, objects)
            trailer_roots = raw.scan(/trailer\b.*?\/Root\s+(\d+)\s+\d+\s+R/mn)
            return trailer_roots.last[0].to_i if trailer_roots && !trailer_roots.empty?

            objects.each do |_, record|
                if record[:dict] =~ /\/Type\s*\/XRef/n && record[:dict] =~ /\/Root\s+(\d+)\s+\d+\s+R/n
                    return $1.to_i
                end
            end

            objects.each { |object_id, record| return object_id if record[:dict] =~ /\/Type\s*\/Catalog/n }
            nil
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Recursively Collect Page Leaf Object Numbers
        # ------------------------------------------------------------
        def self.na_collect_page_leaves(objects, node_id, order, visited, depth)
            return if depth > MAX_PAGE_TREE_DEPTH || visited[node_id]
            visited[node_id] = true
            node = objects[node_id]
            return unless node
            dictionary = node[:dict]

            if dictionary =~ /\/Type\s*\/Pages\b/n
                na_dictionary_refs(dictionary, 'Kids').each do |kid_id|
                    na_collect_page_leaves(objects, kid_id, order, visited, depth + 1)
                end
            elsif dictionary =~ /\/Type\s*\/Page\b/n
                order << node_id
            elsif dictionary =~ /\/Kids\s*\[/n
                na_dictionary_refs(dictionary, 'Kids').each do |kid_id|
                    na_collect_page_leaves(objects, kid_id, order, visited, depth + 1)
                end
            elsif dictionary =~ /\/Contents\b/n || dictionary =~ /\/MediaBox\b/n
                order << node_id
            end
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Fallback Scan for Page Leaf Objects
        # ------------------------------------------------------------
        def self.na_fallback_page_scan(objects)
            objects.select { |_, record| record[:dict] =~ /\/Type\s*\/Page\b/n }.keys.sort
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Assemble and Decode All Content Streams of a Page
        # ------------------------------------------------------------
        def self.na_assemble_page_content(objects, page_id)
            page = objects[page_id]
            return nil unless page
            content_ids = na_dictionary_refs(page[:dict], 'Contents')
            return nil if content_ids.empty?

            parts = []
            content_ids.each do |content_id|
                record = objects[content_id]
                next unless record && record[:has_stream]
                decoded = na_decode_stream(record[:dict], record[:stream])
                parts << decoded if decoded
            end
            return nil if parts.empty?
            parts.join("\n")
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Last-Resort Gather of All Content-Like Streams
        # ------------------------------------------------------------
        def self.na_gather_all_content_streams(objects)
            parts = []
            objects.each_value do |record|
                next unless record[:has_stream]
                next if record[:dict] =~ /\/Type\s*\/ObjStm/n
                next if record[:dict] =~ /\/Subtype\s*\/Image/n
                decoded = na_decode_stream(record[:dict], record[:stream])
                next unless decoded
                parts << decoded if na_looks_like_content?(decoded)
            end
            parts.join("\n")
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Dictionary Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Return a Single Indirect Reference for a Key
        # ------------------------------------------------------------
        def self.na_dictionary_ref(dictionary, key)
            $1.to_i if dictionary =~ /\/#{key}\s+(\d+)\s+(\d+)\s+R/n
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Return All Indirect References for a Key
        # ------------------------------------------------------------
        def self.na_dictionary_refs(dictionary, key)
            array_match = dictionary.match(/\/#{key}\s*\[([^\]]*)\]/mn)
            if array_match
                return array_match[1].scan(/(\d+)\s+\d+\s+R/n).flatten.map(&:to_i)
            end
            single = na_dictionary_ref(dictionary, key)
            single ? [single] : []
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Detect Whether Decoded Text Looks Like Page Content
        # ------------------------------------------------------------
        def self.na_looks_like_content?(text)
            return false if text.nil?
            !!(text =~ /[\d.]\s+(?:re|m|l|c|v|y)\b/n)
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Detect an Encrypted PDF
        # ------------------------------------------------------------
        def self.na_is_encrypted?(raw)
            !!(raw =~ /trailer\b[^>]*?\/Encrypt\b/mn) || !!(raw =~ /\/Encrypt\s+\d+\s+\d+\s+R/n)
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__PdfVectorImporter__PdfReader
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
