# require_relative '../table'

module TTFunk
  Sketchup.require(::File.join(PATH_ROOT, 'table'))
  class Table
    class Simple < Table
      attr_reader :tag

      def initialize(file, tag)
        @tag = tag
        super(file)
      end
    end
  end
end
