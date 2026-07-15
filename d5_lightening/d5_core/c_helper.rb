# frozen_string_literal: true

module CHelper # TODO: 改名为D5CHelper
  #called by c api
  def self.getD5Pdll
    d5pPath = File.join D5Converter::D5RESOURCE_PATH,"D5Plugin.dll"
    return d5pPath
  end

  def self.getPBdll
    pbPath = File.join D5Converter::D5RESOURCE_PATH,"ProgressBar.dll"
    return pbPath
  end
end
