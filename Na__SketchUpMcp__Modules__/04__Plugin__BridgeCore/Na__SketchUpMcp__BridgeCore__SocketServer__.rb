# =============================================================================
# NA SKETCHUP MCP - BRIDGE CORE - SOCKET SERVER
# =============================================================================
#
# FILE       : Na__SketchUpMcp__BridgeCore__SocketServer__.rb
# NAMESPACE  : Na__SketchUpMcp::Na__SocketServer
# PURPOSE    : Listen on 127.0.0.1 for the Python MCP server and hand each
#              request to the command router on SketchUp's main thread
# CREATED    : 2026
#
# WHY A TIMER, NOT A THREAD:
# The SketchUp API is not thread safe and Ruby threads starve inside SketchUp.
# A repeating UI.start_timer runs the pump on the main thread; every socket call
# in it is non-blocking (accept_nonblock / read_nonblock / write_nonblock), so an
# idle or slow client can never freeze the modelling window.
#
# WIRE FORMAT (one JSON object per line, UTF-8, "\n" terminated):
#   request  {"id":1,"token":"<session token>","command":"entity_query","params":{...}}
#   response {"id":1,"ok":true,"result":{...},"warnings":[...]}
#            {"id":1,"ok":false,"error":{"code":"not_found","message":"...","hint":"..."}}
#
# SECURITY:
# - Bound to 127.0.0.1 only; other machines cannot connect.
# - Every request must carry the session token (fresh random 128 bits per start),
#   compared in constant time. The token is written only to this user's
#   git-ignored 91__UserConfig__LocalOnly connection file.
# - A connection whose first line is not a JSON object is closed without reply.
#   A browser page aiming a POST at this port sends "POST / HTTP/1.1" first,
#   so cross-protocol requests die before any command is read.
# - Oversized requests and surplus connections are refused.
#
# RE-ENTRANCY:
# A modal dialog opened by any code during a request pumps the event loop and
# can fire this timer again. The busy flag makes that nested tick a no-op.
#
# =============================================================================

require 'socket'
require 'json'

module Na__SketchUpMcp
    module Na__SocketServer

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_READ_CHUNK_BYTES = 65_536
        NA_MAX_LINES_PER_TICK = 16

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Lifecycle
# -----------------------------------------------------------------------------

        def self.Na__SocketServer__Start
            return self.Na__SocketServer__Status if self.Na__SocketServer__Running

            host = Na__ConfigLoader.Na__ConfigLoader__Get('bridge', 'host', '127.0.0.1').to_s
            @na_server, @na_port = na_open_listener(host)
            @na_host = host
            @na_token = Random.urandom(16).unpack1('H*')
            @na_clients = []
            @na_started_at = Time.now
            @na_request_count = 0
            @na_busy = false

            interval = Na__ConfigLoader.Na__ConfigLoader__Get('bridge', 'poll_interval_seconds', 0.05).to_f
            @na_timer_id = UI.start_timer(interval, true) { self.Na__SocketServer__Pump }

            Na__ConnectionFile.Na__ConnectionFile__Write(@na_host, @na_port, @na_token)
            Na__ApiSelfTest.Na__ApiSelfTest__Run
            puts "[Na__SketchUpMcp] Bridge listening on #{@na_host}:#{@na_port} (pid #{Process.pid})."
            Na__ActivityLog.Na__ActivityLog__Record('bridge_start', 0, true, "Listening on #{@na_host}:#{@na_port}")
            self.Na__SocketServer__Status
        rescue StandardError => error
            self.Na__SocketServer__Stop(silent: true)
            puts "[Na__SketchUpMcp] Bridge failed to start: #{error.class}: #{error.message}"
            Na__ActivityLog.Na__ActivityLog__Record('bridge_start', 0, false, error.message)
            { 'running' => false, 'error' => error.message }
        end

        def self.Na__SocketServer__Stop(silent: false)
            UI.stop_timer(@na_timer_id) if @na_timer_id
            @na_timer_id = nil
            (@na_clients || []).each { |client| na_close_client(client) }
            @na_clients = []
            @na_server.close if @na_server && !@na_server.closed?
            @na_server = nil
            Na__ConnectionFile.Na__ConnectionFile__Remove
            unless silent
                puts '[Na__SketchUpMcp] Bridge stopped.'
                Na__ActivityLog.Na__ActivityLog__Record('bridge_stop', 0, true, 'Stopped')
            end
            self.Na__SocketServer__Status
        rescue StandardError => error
            puts "[Na__SketchUpMcp] Bridge stop warning: #{error.class}: #{error.message}"
            self.Na__SocketServer__Status
        end

        def self.Na__SocketServer__Running
            !!(@na_server && !@na_server.closed?)
        end

        def self.Na__SocketServer__Status
            {
                'running'       => self.Na__SocketServer__Running,
                'host'          => @na_host,
                'port'          => @na_port,
                'pid'           => Process.pid,
                'clients'       => (@na_clients || []).length,
                'requests'      => @na_request_count || 0,
                'started_at'    => @na_started_at ? @na_started_at.strftime('%Y-%m-%d %H:%M:%S') : nil
            }
        end

        # Tries the configured port, then the next ones, so several SketchUp windows can each run a bridge.
        def self.na_open_listener(host)
            first_port = Na__ConfigLoader.Na__ConfigLoader__Get('bridge', 'port', 8385).to_i
            attempts = Na__ConfigLoader.Na__ConfigLoader__Get('bridge', 'port_search_count', 10).to_i
            last_error = nil

            attempts.times do |offset|
                port = first_port + offset
                begin
                    return [TCPServer.new(host, port), port]
                rescue Errno::EADDRINUSE, Errno::EACCES => error
                    last_error = error
                end
            end
            raise "No free port in #{first_port}..#{first_port + attempts - 1} (#{last_error && last_error.message})"
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Pump (one timer tick)
# -----------------------------------------------------------------------------

        def self.Na__SocketServer__Pump
            return if @na_busy || !self.Na__SocketServer__Running

            @na_busy = true
            na_accept_clients
            @na_clients.dup.each { |client| na_service_client(client) }
            na_drop_idle_clients
        rescue StandardError => error
            puts "[Na__SketchUpMcp] Bridge pump warning: #{error.class}: #{error.message}"
        ensure
            @na_busy = false
        end

        def self.na_accept_clients
            max_clients = Na__ConfigLoader.Na__ConfigLoader__Get('bridge', 'max_clients', 8).to_i
            loop do
                socket = @na_server.accept_nonblock(exception: false)
                break if socket.nil? || socket == :wait_readable

                if @na_clients.length >= max_clients
                    socket.close
                    next
                end

                @na_clients << {
                    socket: socket,
                    read_buffer: String.new(encoding: Encoding::BINARY),
                    write_buffer: String.new(encoding: Encoding::BINARY),
                    last_activity: Time.now,
                    first_line_seen: false,
                    close_after_write: false
                }
            end
        end

        def self.na_service_client(client)
            na_read_available(client)
            na_process_lines(client)
            na_flush_writes(client)
            na_close_client(client) if client[:close_after_write] && client[:write_buffer].empty?
        rescue IOError, SystemCallError
            na_close_client(client)
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Reading and Line Framing
# -----------------------------------------------------------------------------

        def self.na_read_available(client)
            max_bytes = Na__ConfigLoader.Na__ConfigLoader__Get('bridge', 'max_request_bytes', 8_388_608).to_i
            loop do
                chunk = client[:socket].read_nonblock(NA_READ_CHUNK_BYTES, exception: false)
                break if chunk == :wait_readable || chunk == :wait_writable

                if chunk.nil?
                    client[:close_after_write] = true
                    break
                end

                client[:read_buffer] << chunk
                client[:last_activity] = Time.now
                next unless client[:read_buffer].bytesize > max_bytes && !client[:read_buffer].include?("\n")

                na_queue_response(client, na_error_response(nil, 'invalid_params',
                                                            "Request larger than #{max_bytes} bytes.", 'Send smaller batches.'))
                client[:read_buffer].clear
                client[:close_after_write] = true
                break
            end
        end

        def self.na_process_lines(client)
            NA_MAX_LINES_PER_TICK.times do
                newline_index = client[:read_buffer].index("\n")
                break unless newline_index

                line = client[:read_buffer].slice!(0..newline_index).force_encoding(Encoding::UTF_8).strip
                next if line.empty?

                na_handle_line(client, line)
                break if client[:close_after_write]
            end
        end

        def self.na_handle_line(client, line)
            request = na_parse_request(line)
            unless client[:first_line_seen]
                client[:first_line_seen] = true
                unless request
                    # Not our protocol (e.g. an HTTP request from a browser): drop silently.
                    client[:read_buffer].clear
                    client[:close_after_write] = true
                    return
                end
            end

            unless request
                na_queue_response(client, na_error_response(nil, 'invalid_params', 'Request line is not a JSON object.', nil))
                return
            end

            unless na_token_valid?(request['token'])
                na_queue_response(client, na_error_response(request['id'], 'unauthorized', 'Session token missing or wrong.',
                                                            'Restart the MCP server so it re-reads the connection file.'))
                client[:close_after_write] = true
                return
            end

            @na_request_count += 1
            na_queue_response(client, Na__CommandRouter.Na__CommandRouter__Dispatch(request))
        end

        def self.na_parse_request(line)
            parsed = JSON.parse(line)
            parsed.is_a?(Hash) ? parsed : nil
        rescue JSON::ParserError, EncodingError
            nil
        end

        # Constant-time comparison so response timing reveals nothing about the token.
        def self.na_token_valid?(candidate)
            expected = @na_token.to_s
            given = candidate.to_s
            return false unless given.bytesize == expected.bytesize

            difference = 0
            given.bytes.each_with_index { |byte, index| difference |= byte ^ expected.getbyte(index) }
            difference.zero?
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Writing
# -----------------------------------------------------------------------------

        def self.na_queue_response(client, response_hash)
            client[:write_buffer] << (na_encode_response(response_hash) + "\n").b
        end

        def self.na_encode_response(response_hash)
            JSON.generate(response_hash)
        rescue JSON::GeneratorError, EncodingError => error
            JSON.generate(na_error_response(response_hash['id'], 'internal_error',
                                            "Result could not be encoded as JSON: #{error.message}", nil))
        end

        def self.na_flush_writes(client)
            until client[:write_buffer].empty?
                written = client[:socket].write_nonblock(client[:write_buffer], exception: false)
                break if written == :wait_writable || written.nil?

                client[:write_buffer] = client[:write_buffer].byteslice(written..-1) || String.new(encoding: Encoding::BINARY)
                client[:last_activity] = Time.now
            end
        end

        def self.na_error_response(request_id, code, message, hint)
            error = { 'code' => code, 'message' => message }
            error['hint'] = hint if hint
            { 'id' => request_id, 'ok' => false, 'error' => error }
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Client Housekeeping
# -----------------------------------------------------------------------------

        def self.na_drop_idle_clients
            timeout_seconds = Na__ConfigLoader.Na__ConfigLoader__Get('bridge', 'client_idle_timeout_seconds', 30).to_f
            now = Time.now
            @na_clients.dup.each do |client|
                na_close_client(client) if now - client[:last_activity] > timeout_seconds
            end
        end

        def self.na_close_client(client)
            client[:socket].close unless client[:socket].closed?
        rescue IOError, SystemCallError
            nil
        ensure
            @na_clients.delete(client) if @na_clients
        end

# endregion -------------------------------------------------------------------

    end # module Na__SocketServer
end # module Na__SketchUpMcp

# =============================================================================
# END OF FILE
# =============================================================================
