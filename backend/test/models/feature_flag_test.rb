require "test_helper"

class FeatureFlagTest < ActiveSupport::TestCase
  test "all method returns hash with feature keys" do
    result = FeatureFlag.all

    assert_kind_of Hash, result
    assert_includes result.keys, :native_scheduling
    assert_includes result.keys, :external_scheduling
  end

  test "all method returns correct structure for each feature" do
    result = FeatureFlag.all

    result.each do |feature_key, feature_data|
      assert_kind_of Symbol, feature_key
      assert_kind_of Hash, feature_data
      assert_includes feature_data.keys, :name
      assert_includes feature_data.keys, :description
      assert_includes feature_data.keys, :enabled
      assert_kind_of String, feature_data[:name]
      assert_kind_of String, feature_data[:description]
      assert_boolean feature_data[:enabled]
    end
  end

  test "all method uses feature_key not env_var for enabled check" do
    # Set environment variable
    ENV["ENABLE_NATIVE_SCHEDULING"] = "true"

    result = FeatureFlag.all

    # Should correctly check using feature key :native_scheduling
    assert result[:native_scheduling][:enabled]
  ensure
    ENV.delete("ENABLE_NATIVE_SCHEDULING")
  end

  test "enabled? returns correct value based on environment variable" do
    ENV["ENABLE_NATIVE_SCHEDULING"] = "true"
    assert FeatureFlag.enabled?(:native_scheduling)

    ENV["ENABLE_NATIVE_SCHEDULING"] = "false"
    assert_not FeatureFlag.enabled?(:native_scheduling)

    ENV.delete("ENABLE_NATIVE_SCHEDULING")
    assert_not FeatureFlag.enabled?(:native_scheduling) # Should use default (false)
  end

  test "disabled? is inverse of enabled?" do
    ENV["ENABLE_NATIVE_SCHEDULING"] = "true"
    assert_not FeatureFlag.disabled?(:native_scheduling)

    ENV["ENABLE_NATIVE_SCHEDULING"] = "false"
    assert FeatureFlag.disabled?(:native_scheduling)
  ensure
    ENV.delete("ENABLE_NATIVE_SCHEDULING")
  end

  private

  def assert_boolean(value)
    assert [true, false].include?(value), "Expected boolean, got #{value.class}"
  end
end
