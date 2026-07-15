# frozen_string_literal: true

module D5CommandForTest
  @@timer
  def self.start
    SUEX_C.enable_test_port
    @@timer = UI.start_timer(0.1,true) do
      SUEX_C.run_test if SUEX_C.respond_to?("run_test")
    end
  end

  def self.stop
    UI.stop_timer(@@timer)
  end
end
