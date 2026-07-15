# frozen_string_literal: true

require 'minitest/autorun'
require 'singleton'

ROOT = File.expand_path('..', __dir__)
$LOAD_PATH.unshift(ROOT)

module Sketchup
  class ShadowInfoObserver; end
  class EntityObserver; end
  class EnvironmentsObserver; end

  class << self
    attr_accessor :active_model_value

    def active_model
      @active_model_value
    end
  end
end

module SUEX_D5Converter
  class MeshConverter; end
end

module D5Message
  def self.d5_puts(_message, _level = 0); end
end

require 'd5_lightening/d5_lite_core/lite_cpp_interface'
require 'd5_lightening/su_d5_shadow_and_environment'

module D5SolarPosition
  class << self
    attr_accessor :hdr_sync_count, :solar_sync_count

    def sync_hdr_environment(_environment)
      @hdr_sync_count = @hdr_sync_count.to_i + 1
    end

    def sync_solar_position(_shadow_info)
      @solar_sync_count = @solar_sync_count.to_i + 1
    end
  end
end

class FakeLighteningInterface
  attr_reader :sync_environment_calls

  def initialize
    @sync_environment_calls = []
  end

  def sync_environment_params_from_sketchup(force)
    @sync_environment_calls << force
  end
end

class FakeEnvironments
  attr_accessor :current

  def initialize(current)
    @current = current
  end
end

class FakeModelWithShadow
  attr_reader :shadow_info

  def initialize
    @shadow_info = {}
  end
end

class LiteEnvironmentSyncGuardTest < Minitest::Test
  def setup
    @iface = Dimension5::Lightening::LiteCppInterface.instance
    @native = FakeLighteningInterface.new
    @iface.instance_variable_set(:@lightening_interface, @native)
    @iface.instance_variable_set(:@scene_switch_environment_sync_paused, false)
    @iface.instance_variable_set(:@skip_next_environment_sync, false)
    @iface.instance_variable_set(:@lite_origin_environment_write_depth, 0)
    @iface.instance_variable_set(:@lite_origin_environment_sync_until, nil)
    @iface.instance_variable_set(:@lm_running, true)
    @iface.instance_variable_set(:@geo_sky_observer_enabled, true)

    @environment = Object.new
    @environments = FakeEnvironments.new(@environment)
    Sketchup.active_model_value = FakeModelWithShadow.new
    D5SolarPosition.hdr_sync_count = 0
    D5SolarPosition.solar_sync_count = 0
  end

  def test_lite_origin_write_blocks_multiple_environment_observer_callbacks
    @iface.with_lite_origin_environment_write do
      3.times { notify_environment_observers }
    end
    2.times { notify_environment_observers }

    assert_empty @native.sync_environment_calls
    assert_equal 0, D5SolarPosition.hdr_sync_count
    assert_equal 0, D5SolarPosition.solar_sync_count
  end

  def test_su_environment_edit_syncs_after_lite_origin_grace_expires
    @iface.with_lite_origin_environment_write {}
    expire_lite_origin_guard

    D5SolarPosition::ENVIRONMENTS_OBSERVER.onEnvironmentSetCurrent(@environments, @environment)

    assert_equal [false], @native.sync_environment_calls
    assert_equal 1, D5SolarPosition.hdr_sync_count
    assert_equal 1, D5SolarPosition.solar_sync_count
  end

  def test_scene_switch_pause_and_lite_origin_guard_do_not_leave_stale_block
    @iface.instance_variable_set(:@scene_switch_environment_sync_paused, true)
    @iface.with_lite_origin_environment_write { notify_environment_observers }
    @iface.instance_variable_set(:@scene_switch_environment_sync_paused, false)
    expire_lite_origin_guard

    D5SolarPosition::ENVIRONMENTS_OBSERVER.onEnvironmentSetCurrent(@environments, @environment)

    assert_equal [false], @native.sync_environment_calls
  end

  def test_sync_off_state_does_not_block_environment_sync_by_itself
    @iface.instance_variable_set(:@lm_running, false)

    refute @iface.geo_sky_linkage_active?
    refute @iface.environment_sync_blocked?(true)
  end

  private

  def notify_environment_observers
    D5SolarPosition::ENVIRONMENTS_OBSERVER.onEnvironmentChange(@environments, @environment)
    D5SolarPosition::ENVIRONMENTS_OBSERVER.onEnvironmentSetCurrent(@environments, @environment)
  end

  def expire_lite_origin_guard
    @iface.instance_variable_set(:@lite_origin_environment_sync_until, 0.0)
    @iface.instance_variable_set(:@skip_next_environment_sync, false)
  end
end
