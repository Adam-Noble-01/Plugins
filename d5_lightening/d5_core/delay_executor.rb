# frozen_string_literal: true

class D5DelayExecutor
  # 延迟调用, 以解决短时间多次调用的问题，使用者需为每一个执行创建一个此对象
  # 实现方式：设置倒计时，在倒计时结束后发送，期间再次触发更新的话，则重置倒计时。
  def initialize(delay_time = 0.1)
    super()
    @delay_time = delay_time
    @timer_id = nil
  end

  def execute
    # 停止前一个定时任务
    if @timer_id != nil
      UI.stop_timer(@timer_id)
    end

    # 创建新的定时任务
    @timer_id = UI.start_timer(@delay_time, false) do # 15个灯光定义，每个定义24个引用实例，共360个灯，同步耗时<0.04s。所以这里超时时间设为0.1
      @timer_id = nil
      yield if block_given?
    end
  end
end
