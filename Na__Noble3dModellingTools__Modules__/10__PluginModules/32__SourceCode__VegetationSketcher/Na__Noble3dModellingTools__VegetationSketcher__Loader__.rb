# frozen_string_literal: true

require_relative 'Na__Noble3dModellingTools__VegetationSketcher__Options__'
require_relative 'Na__Noble3dModellingTools__VegetationSketcher__DataSerializer__'
require_relative 'Na__Noble3dModellingTools__VegetationSketcher__Mesh__'
require_relative 'Na__Noble3dModellingTools__VegetationSketcher__Builder__'
require_relative 'Na__Noble3dModellingTools__VegetationSketcher__Tool__'
require_relative 'Na__Noble3dModellingTools__VegetationSketcher__HedgeTool__'
require_relative 'Na__Noble3dModellingTools__VegetationSketcher__Observers__'
require_relative 'Na__Noble3dModellingTools__VegetationSketcher__DialogManager__'

module Na__Noble3dModellingTools
  module Na__VegetationSketcher
    def self.Na__VegetationSketcher__Run
      Dialog.show
      { success: true, message: 'Vegetation Sketcher opened.' }
    end
  end
end
