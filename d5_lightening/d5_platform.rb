# frozen_string_literal: true

module D5Platform
  def self.windows?
    Sketchup.platform == :platform_win
  end

  def self.macos?
    Sketchup.platform == :platform_osx
  end

  def self.d5_render_supported?
    windows?
  end

  def self.native_extension_loading_enabled?
    windows?
  end

  def self.lite_native_core_loading_enabled?
    return true if windows?

    macos? && (2_100_000_000...2_700_000_000).include?(Sketchup.version_number)
  end

  def self.lite_native_extension_loading_enabled?
    lite_native_core_loading_enabled?
  end
end
