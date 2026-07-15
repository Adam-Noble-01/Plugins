# frozen_string_literal: true

# 性能测试方法，在控制台打印执行耗时
require 'benchmark'
module D5Benchmark
  # 测试启用开关，true时检测代码块耗时并打印；false时直接执行代码块
  @@D5BM_ENABLE = false

  def D5Benchmark.set_enable(enable)
    @@D5BM_ENABLE = enable
  end

  # "label     : real_time"
  def D5Benchmark.bm(label = "", output_device = 0, silence_time = 0)
    if @@D5BM_ENABLE
      time_info = Benchmark.measure(label){ yield }
      if time_info.real > silence_time
        out_string = time_info.format("<bm> %10n: %r") # %n: label; %r: real time
        output_device==0 ? puts(out_string) : $d5_logger.add(Logger::DEBUG,out_string)
      end
    else
      yield
    end
  end
end
