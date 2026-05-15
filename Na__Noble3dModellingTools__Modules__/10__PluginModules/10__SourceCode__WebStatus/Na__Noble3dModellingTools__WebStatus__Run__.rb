# =============================================================================
# NA NOBLE3D MODELLING TOOLS - WEB STATUS - RUN ENTRYPOINTS
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__WebStatus__Run__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__WebStatus
# PURPOSE    : Check live web status for registered DataLib raw JSON files
# CREATED    : 2026
#
# =============================================================================

require 'json'
require 'net/http'
require 'uri'
require_relative '../../../Na__Common__DataLib__CoreSuEntityStandards/Na__DataLib__UrlGenerator__'

module Na__Noble3dModellingTools
    module Na__WebStatus

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_HTTP_OPEN_TIMEOUT_SECONDS = 6
        NA_HTTP_READ_TIMEOUT_SECONDS = 10

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public Entry Points
# -----------------------------------------------------------------------------

        def self.Na__WebStatus__CheckDataLibWebStatus
            file_keys = Na__DataLib__UrlGenerator.Na__Url__AllFileKeys.keys
            status_results = file_keys.map { |file_key| na_check_file_key(file_key) }

            success_count = status_results.count { |result| result[:success] }
            message_text = "Web Data: #{status_results.map { |result| result[:summary] }.join('; ')}."

            na_result(success_count == status_results.length, message_text)
        rescue => error
            na_result(false, "Web Data status failed: #{error.class}: #{error.message}")
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Web Fetch Helpers
# -----------------------------------------------------------------------------

        def self.na_check_file_key(file_key)
            url = Na__DataLib__UrlGenerator.Na__Url__BuildRawUrl(file_key)
            return na_status_result(file_key, false, 'missing-url') if url.nil? || url.empty?

            uri = URI.parse(url)
            http = Net::HTTP.new(uri.host, uri.port)
            http.use_ssl = (uri.scheme == 'https')
            http.open_timeout = NA_HTTP_OPEN_TIMEOUT_SECONDS
            http.read_timeout = NA_HTTP_READ_TIMEOUT_SECONDS

            request = Net::HTTP::Get.new(uri.request_uri)
            response = http.request(request)

            unless response.is_a?(Net::HTTPSuccess)
                return na_status_result(file_key, false, "HTTP #{response.code}")
            end

            JSON.parse(response.body)
            na_status_result(file_key, true, "#{response.code} json ok")
        rescue JSON::ParserError => error
            na_status_result(file_key, false, "HTTP json invalid #{error.class}")
        rescue => error
            na_status_result(file_key, false, "#{error.class}: #{error.message}")
        end

        def self.na_status_result(file_key, success_flag, detail_text)
            {
                success: !!success_flag,
                summary: "#{file_key}=#{detail_text}"
            }
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Result Helpers
# -----------------------------------------------------------------------------

        def self.na_result(success_flag, message_text)
            {
                success: !!success_flag,
                message: message_text.to_s
            }
        end

# endregion -------------------------------------------------------------------

    end # module Na__WebStatus
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
