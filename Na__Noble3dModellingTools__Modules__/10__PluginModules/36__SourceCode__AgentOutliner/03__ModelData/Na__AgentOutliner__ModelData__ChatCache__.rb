# =============================================================================
# NA AGENT OUTLINER - CHAT PICTURE CACHE
# =============================================================================
#
# FILE       : Na__AgentOutliner__ModelData__ChatCache__.rb
# NAMESPACE  : Na__AgentOutliner::Na__ChatCache
# MODULE     : Na Agent Outliner (Na Noble3d Modelling Tools)
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : The pictures pasted into the Chat tab, and the ones agents
#              send back: files in two folders on this PC, named from the
#              thread entries in the model.
# CREATED    : 11-Nov-2026 (0.1.6)
#
# DESCRIPTION:
# - WHERE: 91__UserConfig__LocalOnly/ChatCache (git-ignored, this PC only).
#   One flat folder for every model, so a Save As never orphans a picture.
#   Names are short (img_20261111_120501_a1b2.png): the folder sits about 190
#   characters deep, and SketchUp's Ruby cannot open a Windows path of 260 or
#   more (the 0.1.1 history lesson).
# - FROM AGENTS (0.1.9): pictures an agent sends Adam (a view_capture, say)
#   go in their own folder beside it, 91__UserConfig__LocalOnly/ChatFromAgents,
#   named agt_20261111_120501_a1b2.png, so what came in is never mixed with
#   what he pasted. The name's prefix says which folder a picture is in.
# - FROM THE DIALOG a picture arrives base64 in numbered pieces (at most
#   NA_PART_CHARS each; a callback string of several MB is a risk), is joined,
#   decoded, checked by its first bytes (PNG, JPEG, GIF or WebP, NA_MAX_BYTES
#   at most), written as a .part file and renamed, so a half-written picture
#   never carries a real name. The dialog hears 'chatUpload'.
# - IN THE MODEL a thread entry carries images: [{file, w, h, bytes, name}],
#   names only. Na__Chat__Attachments checks every name is a picture in this
#   folder before a comment is written.
# - FOR AGENTS every image in a thread payload also carries its path, which an
#   agent opens with its own image reader; Na__Chat__ImportFile copies a file
#   an agent sends into the agents' folder.
# - NOTHING IS DELETED automatically: an old comment still shows its picture.
#   Settings shows the folder and how much it holds.
#
# =============================================================================

require 'fileutils'

module Na__AgentOutliner
    module Na__ChatCache

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_FOLDER_NAME = 'ChatCache'.freeze unless defined?(NA_FOLDER_NAME)
        NA_AGENT_FOLDER = 'ChatFromAgents'.freeze unless defined?(NA_AGENT_FOLDER)        # <-- 0.1.9: pictures agents send, apart from Adam's own
        NA_AGENT_PREFIX = 'agt'.freeze unless defined?(NA_AGENT_PREFIX)
        NA_MAX_BYTES   = 15 * 1024 * 1024 unless defined?(NA_MAX_BYTES)                  # <-- One picture, after the dialog has shrunk it
        NA_PART_CHARS  = 600_000 unless defined?(NA_PART_CHARS)                          # <-- base64 characters in one piece
        NA_MAX_PARTS   = 48 unless defined?(NA_MAX_PARTS)
        NA_MAX_IMAGES  = 8 unless defined?(NA_MAX_IMAGES)                                # <-- Pictures on one message
        NA_UPLOAD_TTL  = 600 unless defined?(NA_UPLOAD_TTL)                              # <-- Seconds an unfinished upload is kept
        remove_const(:NA_NAME_RULE) if const_defined?(:NA_NAME_RULE, false)              # <-- Replaced on every load: 0.1.9 added agt_ names, and a reload must take them
        NA_NAME_RULE   = /\A(img|agt)_\d{8}_\d{6}_[0-9a-f]{4}\.(png|jpg|gif|webp)\z/.freeze

        @na_uploads = {} unless defined?(@na_uploads) && @na_uploads

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Where the Pictures Live
# -----------------------------------------------------------------------------

        # FUNCTION | The Cache Folder (made when the first picture is written)
        # ------------------------------------------------------------
        def self.Na__Chat__Folder
            File.join(Na__AgentOutliner::NA_LOCAL_ROOT, NA_FOLDER_NAME)
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Agents' Folder: Pictures They Send Adam (0.1.9)
        # ------------------------------------------------------------
        def self.Na__Chat__AgentFolder
            File.join(Na__AgentOutliner::NA_LOCAL_ROOT, NA_AGENT_FOLDER)
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Folder as a file:/// URL the Dialog Can Load Pictures From
        # ------------------------------------------------------------
        def self.Na__Chat__FolderUrl
            self.na_file_url(self.Na__Chat__Folder)
        end

        def self.Na__Chat__AgentFolderUrl
            self.na_file_url(self.Na__Chat__AgentFolder)
        end
        # ---------------------------------------------------------------

        # FUNCTION | One Picture's Full Path (only a cache name is accepted)
        # ------------------------------------------------------------
        # img_ names are in Adam's folder, agt_ names in the agents' (0.1.9).
        def self.Na__Chat__Path(file)
            name = file.to_s
            raise ArgumentError, "'#{name[0, 60]}' is not a chat picture name." unless name.match?(NA_NAME_RULE)

            File.join(name.start_with?("#{NA_AGENT_PREFIX}_") ? self.Na__Chat__AgentFolder : self.Na__Chat__Folder, name)
        end
        # ---------------------------------------------------------------

        # FUNCTION | What the Folders Hold (Settings and the chat list)
        # ------------------------------------------------------------
        # files and bytes count both folders; agent_files and agent_bytes the
        # pictures agents sent.
        def self.Na__Chat__Info
            files, bytes = self.na_folder_count(self.Na__Chat__Folder)
            agent_files, agent_bytes = self.na_folder_count(self.Na__Chat__AgentFolder)
            {
                'folder'       => self.Na__Chat__Folder,
                'url'          => self.Na__Chat__FolderUrl,
                'files'        => files + agent_files,
                'bytes'        => bytes + agent_bytes,
                'agent_folder' => self.Na__Chat__AgentFolder,
                'agent_url'    => self.Na__Chat__AgentFolderUrl,
                'agent_files'  => agent_files,
                'agent_bytes'  => agent_bytes
            }
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Uploads From the Dialog (pasted, dropped or chosen pictures)
# -----------------------------------------------------------------------------

        # FUNCTION | One Piece of an Upload; the Last Piece Writes the File
        # ------------------------------------------------------------
        # payload: upload (the dialog's id), index, total, data (base64), name,
        # w, h. Returns { 'upload', 'done' => false, 'got' } until every piece
        # is in, then { 'upload', 'done' => true, 'file', 'bytes', 'w', 'h',
        # 'name' }. A bad piece raises ArgumentError and drops the upload.
        def self.Na__Chat__UploadPart(payload)
            upload = payload['upload'].to_s
            raise ArgumentError, 'The picture upload has no id.' unless upload.match?(/\A[A-Za-z0-9_-]{4,40}\z/)

            index = payload['index'].to_i
            total = payload['total'].to_i
            data  = payload['data'].to_s
            unless total.between?(1, NA_MAX_PARTS) && index.between?(0, total - 1) && data.length <= NA_PART_CHARS
                @na_uploads.delete(upload)
                raise ArgumentError, 'That picture is too large to paste (15 MB at most).'
            end

            self.na_prune_uploads
            entry = (@na_uploads[upload] ||= { 'parts' => [], 'total' => total, 'at' => Time.now.to_f })
            raise ArgumentError, 'The picture upload was muddled: paste it again.' if entry['total'] != total

            entry['parts'][index] = data
            got = entry['parts'].count { |part| !part.nil? }
            return { 'upload' => upload, 'done' => false, 'got' => got, 'total' => total } if got < total

            @na_uploads.delete(upload)
            bytes = self.na_decode(entry['parts'].join)
            info  = self.na_store(bytes)
            info.merge(
                'upload' => upload,
                'done'   => true,
                'name'   => self.na_label(payload['name']),
                'w'      => self.na_dimension(payload['w']) || info['w'],
                'h'      => self.na_dimension(payload['h']) || info['h']
            )
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Pictures on a Message
# -----------------------------------------------------------------------------

        # FUNCTION | The Pictures a Message Carries, Checked Against the Folder
        # ------------------------------------------------------------
        # list: [{file, w, h, bytes, name}] (or plain names). Every file must be
        # a picture in the cache. Returns the clean list, [] for none.
        def self.Na__Chat__Attachments(list)
            items = Array(list)
            return [] if items.empty?
            raise ArgumentError, "A message can carry #{NA_MAX_IMAGES} pictures at most; this one has #{items.length}." if items.length > NA_MAX_IMAGES

            items.map do |item|
                item  = { 'file' => item } unless item.is_a?(Hash)
                file  = item['file'] || item[:file]
                path  = self.Na__Chat__Path(file)
                raise ArgumentError, 'A picture on this message is no longer in the chat folder: paste it again.' unless File.file?(path)

                clean = { 'file' => file.to_s, 'bytes' => File.size(path) }
                width  = self.na_dimension(item['w'] || item[:w])
                height = self.na_dimension(item['h'] || item[:h])
                clean['w'] = width if width
                clean['h'] = height if height
                label = self.na_label(item['name'] || item[:name])
                clean['name'] = label unless label.empty?
                clean
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Picture File an Agent Sends, Copied Into the Agents' Folder
        # ------------------------------------------------------------
        def self.Na__Chat__ImportFile(path)
            source = path.to_s.strip
            raise ArgumentError, 'Give each picture as a file path on this PC.' if source.empty?
            raise ArgumentError, "There is no file at #{source}." unless File.file?(source)

            size = File.size(source)
            raise ArgumentError, "#{File.basename(source)} is #{(size / 1_048_576.0).round(1)} MB; a picture can be 15 MB at most." if size > NA_MAX_BYTES
            raise ArgumentError, "#{File.basename(source)} is empty." if size.zero?

            bytes = File.binread(source)
            info  = self.na_store(bytes, NA_AGENT_PREFIX)
            info.merge('name' => self.na_label(File.basename(source)))
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Stored Picture With Its Path (payloads for the dialog and agents)
        # ------------------------------------------------------------
        def self.Na__Chat__Describe(image)
            item = image.is_a?(Hash) ? image.dup : { 'file' => image.to_s }
            begin
                path = self.Na__Chat__Path(item['file'])
                item['path']   = path
                item['exists'] = File.file?(path)
            rescue ArgumentError
                item['exists'] = false
            end
            item
        end
        # ---------------------------------------------------------------

        # FUNCTION | What Kind of Picture These Bytes Are, by Their First Bytes
        # ------------------------------------------------------------
        def self.Na__Chat__Sniff(bytes)
            head = bytes.to_s.byteslice(0, 16).to_s.b
            return 'png'  if head.start_with?("\x89PNG\r\n\x1A\n".b)
            return 'jpg'  if head.start_with?("\xFF\xD8\xFF".b)
            return 'gif'  if head.start_with?('GIF87a'.b) || head.start_with?('GIF89a'.b)
            return 'webp' if head.start_with?('RIFF'.b) && head.byteslice(8, 4) == 'WEBP'.b

            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Width and Height Read From the File's Own Header (PNG, GIF, JPEG)
        # ------------------------------------------------------------
        def self.Na__Chat__Dimensions(bytes, type)
            data = bytes.to_s.b
            case type
            when 'png'
                return nil if data.bytesize < 24

                data.byteslice(16, 8).unpack('NN')
            when 'gif'
                return nil if data.bytesize < 10

                data.byteslice(6, 4).unpack('vv')
            when 'jpg'
                self.na_jpeg_size(data)
            end
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Private Helpers
# -----------------------------------------------------------------------------

        def self.na_decode(text)
            clean = text.to_s.delete("\r\n ")
            raise ArgumentError, 'The picture arrived empty: paste it again.' if clean.empty?
            raise ArgumentError, 'The picture arrived damaged: paste it again.' unless clean.match?(%r{\A[A-Za-z0-9+/]*={0,2}\z})

            bytes = clean.unpack1('m')
            raise ArgumentError, 'That picture is too large (15 MB at most).' if bytes.bytesize > NA_MAX_BYTES

            bytes
        end

        # Checks the bytes, then writes them under a new name (a .part file
        # renamed, so a half-written picture never carries a real name).
        # prefix 'img' is Adam's folder, 'agt' the agents' (0.1.9).
        def self.na_store(bytes, prefix = 'img')
            type = self.Na__Chat__Sniff(bytes)
            raise ArgumentError, 'Only PNG, JPEG, GIF or WebP pictures can go in a chat.' unless type
            raise ArgumentError, 'That picture is too large (15 MB at most).' if bytes.bytesize > NA_MAX_BYTES

            folder = prefix == NA_AGENT_PREFIX ? self.Na__Chat__AgentFolder : self.Na__Chat__Folder
            FileUtils.mkdir_p(folder)
            name = self.na_new_name(type, folder, prefix)
            path = File.join(folder, name)
            temp = "#{path}.part"
            File.binwrite(temp, bytes)
            File.rename(temp, path)
            size = self.Na__Chat__Dimensions(bytes, type) || []
            info = { 'file' => name, 'bytes' => bytes.bytesize, 'type' => type }
            info['w'] = size[0] if size[0].to_i.positive?
            info['h'] = size[1] if size[1].to_i.positive?
            info
        rescue SystemCallError => error
            File.delete(temp) if temp && File.exist?(temp)
            raise ArgumentError, "The picture could not be saved in the chat folder (#{error.class.name.split('::').last})."
        end

        def self.na_new_name(type, folder, prefix = 'img')
            stamp = Time.now.strftime('%Y%m%d_%H%M%S')
            8.times do
                name = "#{prefix}_#{stamp}_#{format('%04x', rand(65_536))}.#{type}"
                return name unless File.exist?(File.join(folder, name))
            end
            raise ArgumentError, 'Too many pictures in the same second: paste it again.'
        end

        def self.na_file_url(folder)
            path = folder.tr('\\', '/')
            escaped = path.gsub(%r{[^A-Za-z0-9\-._~/:]}) { |char| char.bytes.map { |byte| format('%%%02X', byte) }.join }
            "file:///#{escaped.sub(%r{\A/+}, '')}/"
        end

        # [pictures, bytes] in one folder. Not Dir.glob: it reads a Windows
        # backslash as an escape.
        def self.na_folder_count(folder)
            names = File.directory?(folder) ? Dir.children(folder).select { |name| name.match?(NA_NAME_RULE) } : []
            [names.length, names.sum { |name| File.size?(File.join(folder, name)).to_i }]
        rescue SystemCallError => error
            Na__AgentOutliner::Na__DebugTools.Na__Debug__Warn("Chat cache: #{error.message}")
            [0, 0]
        end

        def self.na_prune_uploads
            limit = Time.now.to_f - NA_UPLOAD_TTL
            @na_uploads.delete_if { |_id, entry| entry['at'] < limit }
        end

        def self.na_label(text)
            text.to_s.gsub(/[\u0000-\u001F]/, ' ').strip[0, 80]
        end

        def self.na_dimension(value)
            number = value.to_i
            number.between?(1, 100_000) ? number : nil
        end

        # The first start-of-frame marker holds the height and width.
        def self.na_jpeg_size(data)
            offset = 2
            while offset + 9 < data.bytesize
                return nil unless data.getbyte(offset) == 0xFF

                marker = data.getbyte(offset + 1)
                length = data.byteslice(offset + 2, 2).unpack1('n')
                if [0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF].include?(marker)
                    height, width = data.byteslice(offset + 5, 4).unpack('nn')
                    return [width, height]
                end
                return nil if length.nil? || length < 2

                offset += 2 + length
            end
            nil
        end

# endregion -------------------------------------------------------------------

    end # module Na__ChatCache
end # module Na__AgentOutliner

# =============================================================================
# END OF FILE
# =============================================================================
