# =============================================================================
# VALEDESIGNSUITE - VALEVISION CLOUD SYNC PROJECT DATA WRITER
# =============================================================================
#
# FILE       : Na__ValeVisionCloudSync__ProjectDataWriter__.rb
# NAMESPACE  : Na__ValeVisionCloudSync::Na__ProjectDataWriter
# PURPOSE    : Read and write the local ProjectData JSON array, preserving
#              its existing object structure while adding/replacing keyed
#              objects such as ValeVison3D__SketchUpCameraData
# CREATED    : 25-Jun-2026
#
# DESCRIPTION:
# - The local project data file is an array of JSON objects.
# - This writer identifies the target object by its first key, then replaces
#   or appends it without touching the other objects in the array.
# - Writes atomically via temp-file + rename to guard against partial writes.
#
# =============================================================================

require 'json'
require 'fileutils'

module Na__ValeVisionCloudSync
    module Na__ProjectDataWriter

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

        # FUNCTION | Find the ProjectData JSON file under 00__ProjectData
        # ------------------------------------------------------------
        def self.Na__ValeVisionCloudSync__FindProjectDataFile(project_root)
            return nil unless project_root && File.directory?(project_root)

            data_dir = File.join(project_root, '00__ProjectData')
            return nil unless File.directory?(data_dir)

            json_files = Dir.glob(File.join(data_dir, '*__ProjectData__.json'))
            json_files.first
        end

        # FUNCTION | Read the ProjectData JSON array from disk
        # ------------------------------------------------------------
        def self.Na__ValeVisionCloudSync__ReadProjectDataArray(file_path)
            return [] unless file_path && File.exist?(file_path)

            raw  = File.read(file_path, encoding: 'utf-8')
            data = JSON.parse(raw)
            data.is_a?(Array) ? data : [data]
        rescue => error
            puts "[Na__ValeVisionCloudSync] ProjectDataWriter read error: #{error.class}: #{error.message}"
            []
        end

        # FUNCTION | Merge a data object into the array by its identifying root key
        # ------------------------------------------------------------
        # The identifying root key is the first key of the new_data_object.
        # If an existing array element has that same key, it is replaced;
        # otherwise the new object is appended to the array.
        # ---------------------------------------------------------------
        def self.Na__ValeVisionCloudSync__MergeDataObject(data_array, new_data_object)
            return data_array unless new_data_object.is_a?(Hash) && !new_data_object.empty?

            root_key = new_data_object.keys.first
            found    = false

            merged = data_array.map do |existing_object|
                if existing_object.is_a?(Hash) && existing_object.key?(root_key)
                    found = true
                    new_data_object   # <-- Replace the whole object
                else
                    existing_object
                end
            end

            merged << new_data_object unless found
            merged
        end

        # FUNCTION | Write the data array back to disk atomically
        # ------------------------------------------------------------
        def self.Na__ValeVisionCloudSync__WriteProjectDataArray(file_path, data_array)
            return { success: false, message: 'No file path given.' } unless file_path

            FileUtils.mkdir_p(File.dirname(file_path))

            json_content = JSON.pretty_generate(data_array)
            temp_path    = file_path + '.tmp'

            File.write(temp_path, json_content, encoding: 'utf-8')
            FileUtils.mv(temp_path, file_path)

            { success: true, message: "Wrote #{File.basename(file_path)}" }
        rescue => error
            FileUtils.rm_f(temp_path) rescue nil
            { success: false, message: "Write error: #{error.class}: #{error.message}" }
        end

        # FUNCTION | Convenience: merge one object and write in a single call
        # ------------------------------------------------------------
        def self.Na__ValeVisionCloudSync__MergeAndWriteDataObject(project_root, new_data_object)
            file_path  = self.Na__ValeVisionCloudSync__FindProjectDataFile(project_root)
            unless file_path
                return { success: false, message: "ProjectData JSON not found under: #{project_root}" }
            end

            data_array = self.Na__ValeVisionCloudSync__ReadProjectDataArray(file_path)
            merged     = self.Na__ValeVisionCloudSync__MergeDataObject(data_array, new_data_object)
            self.Na__ValeVisionCloudSync__WriteProjectDataArray(file_path, merged)
        end

# endregion -------------------------------------------------------------------

    end # module Na__ProjectDataWriter
end # module Na__ValeVisionCloudSync

# =============================================================================
# END OF FILE
# =============================================================================
