# frozen_string_literal: true
root_path = File.expand_path('..', File.dirname(__FILE__))
require 'fiddle'
require 'fiddle/import'
require 'fiddle/types'
Sketchup.require "#{root_path}/d5_platform"

module D5WinAPI
  if D5Platform.windows?
    extend Fiddle::Importer
    dlload 'kernel32.dll'

    extern 'int SetDefaultDllDirectories(int)'
    extern 'void* AddDllDirectory(void*)'
    extern 'int SetDllDirectoryW(void*)'
  else
    def self.SetDefaultDllDirectories(_flags); 0; end
    def self.AddDllDirectory(_path); nil; end
    def self.SetDllDirectoryW(_path); 0; end
  end
end

module D5WinDLLLoader
  LOAD_LIBRARY_SEARCH_DEFAULT_DIRS = 0x00001000
  LOAD_LIBRARY_SEARCH_USER_DIRS    = 0x00000400

  @initialized = false

  def self.init_once(path)
    return if @initialized
    D5WinAPI.AddDllDirectory(wstr(path))
    @initialized = true
  end

  def self.wstr(str)
    utf16_encoding_str = str.encode('UTF-16LE')
    utf16_encoding_str << 0x00
    utf16_encoding_str << 0x00
    return utf16_encoding_str
  end

  def self.add_dir(path)
    D5WinAPI.AddDllDirectory(wstr(path))
  end

  def self.add_dir_once(path)
    init_once(path)
  end
end

D5WinAPI.SetDllDirectoryW(D5Converter::D5RESOURCE_PATH.encode("UTF-16LE")) if D5Platform.windows?

if Sketchup.platform == :platform_win
  require 'win32/registry'
  require 'win32ole'
end
