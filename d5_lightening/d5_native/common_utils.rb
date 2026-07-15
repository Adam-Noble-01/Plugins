module D5CommonUtils
  # [Deprecated]直接使用common_utils.dll中的C接口
  if D5Platform.d5_render_supported?
    extend Fiddle::Importer
    dlload("common_utils.dll")
    GAParamsC = struct ['const char* parameters', 'const char* value']
    extern("int InitGAWithoutClientID(int, const wchar_t*)")
    extern("int ReportGA(const char*, const GAParamsC*, size_t, int)")
  end

  # Implemented in common_utils_ruby.so。依赖于common_utils.dll
  def self.load
    @loaded = false
    return @loaded unless D5Platform.native_extension_loading_enabled?

    version_num = Sketchup.version_number
    ruby_ver = RUBY_VERSION
    ruby_ver = ruby_ver.split "."
    ruby_ver_major = ruby_ver[0].to_i
    ruby_ver_minor = ruby_ver[1].to_i
    if ruby_ver_major == 2 && ruby_ver_minor == 5
      require File.join D5Converter::D5RESOURCE_PATH,'ruby25/common_utils_ruby.so'
      @loaded = true
    elsif ruby_ver_major == 2 && ruby_ver_minor == 7
      require File.join D5Converter::D5RESOURCE_PATH,'ruby27/common_utils_ruby.so'
      @loaded = true
    elsif ruby_ver_major == 3 && ruby_ver_minor == 2
      require File.join D5Converter::D5RESOURCE_PATH,'ruby32/common_utils_ruby.so'
      @loaded = true
    end
    @loaded
  end

  def self.loaded?
    @loaded
  end

  def self.init_data_tracking env,cid,params
    # Implemented in common_utils_ruby.so
    puts "not loaded!"
  end
  def self.report_data_tracking event,params,defer
    # Implemented in common_utils_ruby.so
    puts "not loaded!"
  end
  def self.flush_data_tracking
    # Implemented in common_utils_ruby.so
    puts "not loaded!"
  end
  def self.destroy_data_tracking
    # Implemented in common_utils_ruby.so
    puts "not loaded!"
  end
end

# 另一种加载方式
# module MyLib
#   extend Fiddle::Importer
#   dlload(File.join(D5Converter::D5RESOURCE_PATH, "D5Plugin.dll").encode(Encoding.locale_charmap))
#   extern("void D5SetEntityIntProperty(void* session, int type, const wchar_t* id, const wchar_t* name, int value)")
# end

# use Fiddle to import functions from D5Plugin.dll and ProgressBar.dll
# TODO: ruby里用fiddle调用user32这类的最好放到so里去, 到时候用ruby加密在2.7上会有些问题 ---- 竺云强
