# =============================================================================
# NA SKETCHUP MCP - DEV TOOLS - RUBY CORE NAMES BUILDER
# =============================================================================
#
# FILE       : Na__SketchUpMcp__RubyCoreNamesBuilder__.rb
# PURPOSE    : Record every method and constant name that SketchUp's own Ruby
#              (3.2, plus the stdlib agents commonly require) defines, so the
#              ruby_eval linter can tell "Ruby core" from "invented API"
# CREATED    : 2026
#
# RUN (plain Ruby, not inside SketchUp; SketchUp never loads subfolder files):
#   python ../40__Tests__Validation/Na__SketchUpMcp__Tests__RunRubyChecks__.py Na__SketchUpMcp__RubyCoreNamesBuilder__.rb
#
# OUTPUT:
#   02__Plugin__CoreAppData/Na__SketchUpMcp__CoreAppData__RubyCoreNames__.json
#
# =============================================================================

# The embedded test interpreter can start without Encoding::UTF_8 bound; SketchUp always has it.
Encoding.const_set(:UTF_8, Encoding.find('UTF-8')) unless Encoding.const_defined?(:UTF_8)

require 'json'
require 'set'
require 'time'
require 'stringio'
require 'fileutils'
require 'pathname'
require 'securerandom'
require 'digest'
require 'date'
require 'base64'
require 'tmpdir'
require 'tempfile'
require 'open3'
require 'socket'

na_methods = Set.new
na_constants = Set.new

ObjectSpace.each_object(Module) do |mod|
    name = begin
        mod.name
    rescue StandardError
        nil
    end
    next unless name
    next if name.start_with?('Na__')

    na_constants << name
    (mod.instance_methods(true) + mod.private_instance_methods(true)).each { |method_name| na_methods << method_name.to_s }
    (mod.singleton_methods(true) + mod.private_methods(true)).each { |method_name| na_methods << method_name.to_s }
end

na_output = File.expand_path(File.join(__dir__, '..', '02__Plugin__CoreAppData', 'Na__SketchUpMcp__CoreAppData__RubyCoreNames__.json'))
File.write(na_output, JSON.generate({
    'ruby_version' => RUBY_VERSION,
    'generated_by' => 'Na__SketchUpMcp__RubyCoreNamesBuilder__.rb',
    'methods'      => na_methods.to_a.sort,
    'constants'    => na_constants.to_a.sort
}))
puts "Ruby #{RUBY_VERSION}: #{na_methods.size} method names, #{na_constants.size} constants -> #{na_output}"

# =============================================================================
# END OF FILE
# =============================================================================
