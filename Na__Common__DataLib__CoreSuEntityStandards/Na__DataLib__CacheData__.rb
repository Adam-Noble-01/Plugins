# =============================================================================
# NA DATALIB - CACHE DATA
# =============================================================================
#
# FILE       : Na__DataLib__CacheData__.rb
# NAMESPACE  : Na__DataLib__CacheData
# MODULE     : Na__DataLib__CacheData
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : HTTP fetch, temp-dir caching, and three-stage data loading
# CREATED    : 15-Mar-2026
#
# DESCRIPTION:
# - Primary entry point for all Na__ plugins that need centralised data.
# - Checks a local temp-dir cache first (30-minute TTL).
# - If cache is stale or missing, fetches fresh JSON from the GitHub raw URL.
# - On successful fetch, writes the response to the temp cache for next time.
# - On fetch failure, delegates to Na__DataLib__LocalFallback for the local
#   plugins-folder copy as a last resort.
# - Returns the parsed Ruby Hash on success, nil on total failure.
#
# =============================================================================

require 'net/http'
require 'uri'
require 'json'
require 'fileutils'

require_relative 'Na__DataLib__UrlGenerator__'
require_relative 'Na__DataLib__LocalFallback__'

module Na__DataLib__CacheData

# -----------------------------------------------------------------------------
# REGION | Module Constants
# -----------------------------------------------------------------------------

    # MODULE CONSTANTS | Cache Configuration
    # ------------------------------------------------------------
    CACHE_MAX_AGE_SECONDS  = 1800                                             # <-- 30 minutes
    CACHE_SUBFOLDER_NAME   = "Na__DataLib__Cache".freeze
    CACHE_FILE_PREFIX      = "Na__DataLib__Cache__".freeze
    HTTP_OPEN_TIMEOUT      = 10                                               # <-- Connection timeout (seconds)
    HTTP_READ_TIMEOUT      = 15                                               # <-- Read timeout (seconds)
    # ------------------------------------------------------------

    # MODULE CONSTANTS | Human-Readable File Key Labels
    # ------------------------------------------------------------
    FILE_KEY_LABELS = {
        :materials      => "Materials",
        :edge_materials => "Edge Materials",
        :tags           => "Tags",
        :components     => "Components"
    }.freeze
    # ------------------------------------------------------------

    # MODULE VARIABLES | Last Load Source Tracking
    # ------------------------------------------------------------
    @na_last_source = {}                                                      # <-- { file_key => :url | :cache | :local | :failed }
    # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Cache Path Helpers
# -----------------------------------------------------------------------------

    # HELPER FUNCTION | Resolve Cache Directory Path
    # ---------------------------------------------------------------
    def self.Na__Cache__CacheDir
        dir = File.join(Sketchup.temp_dir, CACHE_SUBFOLDER_NAME)
        FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
        dir
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Resolve Cache File Path for a File Key
    # ---------------------------------------------------------------
    def self.Na__Cache__CacheFilePath(file_key)
        File.join(self.Na__Cache__CacheDir, "#{CACHE_FILE_PREFIX}#{file_key}.json")
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Cache Read / Write
# -----------------------------------------------------------------------------

    # HELPER FUNCTION | Read Cached Data if Fresh
    # ---------------------------------------------------------------
    def self.Na__Cache__ReadIfFresh(file_key)
        cache_path = Na__Cache__CacheFilePath(file_key)
        return nil unless File.exist?(cache_path)

        begin
            raw       = File.read(cache_path, encoding: 'UTF-8')
            wrapper   = JSON.parse(raw)
            cached_at = wrapper["cached_at"].to_i
            age       = Time.now.to_i - cached_at

            if age < CACHE_MAX_AGE_SECONDS
                puts "    [Na__DataLib__Cache] Cache hit for :#{file_key} (age: #{age}s)"
                return wrapper["data"]
            else
                puts "    [Na__DataLib__Cache] Cache stale for :#{file_key} (age: #{age}s, max: #{CACHE_MAX_AGE_SECONDS}s)"
                return nil
            end
        rescue => e
            puts "    [Na__DataLib__Cache] Cache read error for :#{file_key}: #{e.message}"
            nil
        end
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Write Data to Cache File
    # ---------------------------------------------------------------
    def self.Na__Cache__WriteToCache(file_key, parsed_data)
        cache_path = Na__Cache__CacheFilePath(file_key)

        wrapper = {
            "cached_at" => Time.now.to_i,
            "data"      => parsed_data
        }

        begin
            File.write(cache_path, JSON.pretty_generate(wrapper), encoding: 'UTF-8')
            puts "    [Na__DataLib__Cache] Cache written for :#{file_key}"
        rescue => e
            puts "    [Na__DataLib__Cache] Cache write error for :#{file_key}: #{e.message}"
        end
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | HTTP Fetch
# -----------------------------------------------------------------------------

    # HELPER FUNCTION | Fetch JSON from GitHub Raw URL
    # ---------------------------------------------------------------
    def self.Na__Cache__FetchFromUrl(file_key)
        url = Na__DataLib__UrlGenerator.Na__Url__BuildRawUrl(file_key)
        return nil unless url

        begin
            puts "    [Na__DataLib__Cache] Fetching :#{file_key} from URL..."
            uri  = URI.parse(url)
            http = Net::HTTP.new(uri.host, uri.port)
            http.use_ssl      = true
            http.open_timeout = HTTP_OPEN_TIMEOUT
            http.read_timeout = HTTP_READ_TIMEOUT

            request  = Net::HTTP::Get.new(uri.request_uri)
            response = http.request(request)

            unless response.is_a?(Net::HTTPSuccess)
                puts "    [Na__DataLib__Cache] HTTP #{response.code}: #{response.message}"
                return nil
            end

            parsed = JSON.parse(response.body)
            puts "    [Na__DataLib__Cache] Fetch success for :#{file_key}"
            parsed

        rescue StandardError => e
            puts "    [Na__DataLib__Cache] Fetch failed for :#{file_key}: #{e.message}"
            nil
        end
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

    # FUNCTION | Load Data for a File Key (Cache -> URL -> Local Fallback)
    # ------------------------------------------------------------
    def self.Na__Cache__LoadData(file_key, force_reload = false)
        unless force_reload
            cached = Na__Cache__ReadIfFresh(file_key)
            if cached
                @na_last_source[file_key] = :cache
                return cached
            end
        end

        fetched = Na__Cache__FetchFromUrl(file_key)
        if fetched
            Na__Cache__WriteToCache(file_key, fetched)
            @na_last_source[file_key] = :url
            return fetched
        end

        local = Na__DataLib__LocalFallback.Na__Fallback__LoadLocal(file_key)
        @na_last_source[file_key] = local ? :local : :failed
        local
    end
    # ---------------------------------------------------------------

    # FUNCTION | Return the Source Used for Last Load of a File Key
    # ------------------------------------------------------------
    def self.Na__Cache__LastSource(file_key)
        @na_last_source[file_key]
    end
    # ---------------------------------------------------------------

    # FUNCTION | Print Startup Status Report for Loaded Data Files
    # ------------------------------------------------------------
    def self.Na__Cache__PrintStartupReport(file_keys)
        puts ""
        puts "    ┌─────────────────────────────────────────────────────────┐"
        puts "    │  Na__DataLib - Data File Status Report                  │"
        puts "    ├─────────────────────────────────────────────────────────┤"

        file_keys.each do |key|
            label  = FILE_KEY_LABELS[key] || key.to_s
            source = @na_last_source[key]

            case source
            when :url
                icon   = "✓"
                detail = "loaded from web (URL)"
            when :cache
                icon   = "✓"
                detail = "loaded from cache"
            when :local
                icon   = "⚠"
                detail = "LOCAL FALLBACK (web unavailable)"
            else
                icon   = "✗"
                detail = "FAILED - data unavailable"
            end

            puts "    │  #{icon} %-18s : %s" % [label, detail]
        end

        puts "    └─────────────────────────────────────────────────────────┘"
        puts ""
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

end # module Na__DataLib__CacheData

# =============================================================================
# END OF FILE
# =============================================================================
