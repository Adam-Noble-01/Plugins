# =============================================================================
# NA SKETCHUP MCP - BRIDGE CORE - API SELF TEST
# =============================================================================
#
# FILE       : Na__SketchUpMcp__BridgeCore__ApiSelfTest__.rb
# NAMESPACE  : Na__SketchUpMcp::Na__ApiSelfTest
# PURPOSE    : Prove, inside the running SketchUp, that every API method each
#              tool depends on really exists; disable the tools that lack one
# CREATED    : 2026
#
# THREE LAYERS OF "NO INVENTED API":
#   1. Offline: every "api" entry in the tool registry must exist in the index
#      built from SketchUp's official ruby-api-stubs (40__Tests__Validation).
#   2. Offline: every method name called in a handler must exist in that index,
#      in Ruby core, or in this plugin's own code (same test folder).
#   3. Live (this file): at bridge start each "api" entry is probed with
#      method_defined? / respond_to? in the real SketchUp. A tool whose
#      dependency is missing (e.g. Solid Tools on a non-Pro licence) is refused
#      with that reason instead of failing half-way through an operation.
#
# SIGNATURE FORMAT (same as the registry and ruby_api_lookup):
#   "Sketchup::Face#pushpull"   instance method
#   "Sketchup.send_action"      module function / class method
#
# =============================================================================

module Na__SketchUpMcp
    module Na__ApiSelfTest

# -----------------------------------------------------------------------------
# REGION | Probing
# -----------------------------------------------------------------------------

        # true = exists, false = class exists but method does not, nil = class unknown / bad signature
        def self.Na__ApiSelfTest__Probe(signature)
            match = /\A([A-Z][\w:]*)(#|\.)([\w?!=\[\]<>+\-*\/%]+)\z/.match(signature.to_s.strip)
            return nil unless match

            owner = na_constant(match[1])
            return nil unless owner.is_a?(Module)

            method_symbol = match[3].to_sym
            if match[2] == '#'
                owner.method_defined?(method_symbol) || owner.private_method_defined?(method_symbol)
            else
                owner.respond_to?(method_symbol)
            end
        end

        def self.na_constant(name)
            name.split('::').reduce(Object) do |scope, part|
                return nil unless scope.const_defined?(part, false)

                scope.const_get(part, false)
            end
        rescue NameError
            nil
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Registry Check
# -----------------------------------------------------------------------------

        def self.Na__ApiSelfTest__Run
            missing = []
            checked = 0
            Na__ConfigLoader.Na__ConfigLoader__Tools.each do |tool|
                (tool['api'] || []).each do |signature|
                    checked += 1
                    missing << { 'tool' => tool['name'], 'api' => signature } unless self.Na__ApiSelfTest__Probe(signature) == true
                end
            end

            @na_last_report = {
                'checked'           => checked,
                'missing'           => missing,
                'unavailable_tools' => missing.map { |entry| entry['tool'] }.uniq,
                'sketchup_version'  => Sketchup.version.to_s
            }
            unless missing.empty?
                puts "[Na__SketchUpMcp] API self-test: #{missing.length} of #{checked} dependencies missing; " \
                     "unavailable tools: #{@na_last_report['unavailable_tools'].join(', ')}"
            end
            @na_last_report
        rescue StandardError => error
            puts "[Na__SketchUpMcp] API self-test warning: #{error.class}: #{error.message}"
            @na_last_report = { 'checked' => 0, 'missing' => [], 'unavailable_tools' => [], 'error' => error.message }
        end

        def self.Na__ApiSelfTest__Report
            @na_last_report || self.Na__ApiSelfTest__Run
        end

        # nil when the tool is usable, otherwise the first missing dependency.
        def self.Na__ApiSelfTest__MissingDependencyFor(tool_name)
            entry = self.Na__ApiSelfTest__Report['missing'].find { |missing| missing['tool'] == tool_name.to_s }
            entry && entry['api']
        end

# endregion -------------------------------------------------------------------

    end # module Na__ApiSelfTest
end # module Na__SketchUpMcp

# =============================================================================
# END OF FILE
# =============================================================================
