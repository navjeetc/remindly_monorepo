require "test_helper"

class CaregiverAvailabilitiesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @caregiver = users(:caregiver_one)
    sign_in_as(@caregiver)
  end

  test "parse_bulk_dates handles valid dates" do
    controller = CaregiverAvailabilitiesController.new
    
    # Test with array
    dates = controller.send(:parse_bulk_dates, ["2025-11-15", "2025-11-16"])
    assert_equal 2, dates.length
    assert_equal Date.parse("2025-11-15"), dates[0]
    assert_equal Date.parse("2025-11-16"), dates[1]
    
    # Test with comma-separated string
    dates = controller.send(:parse_bulk_dates, "2025-11-15,2025-11-16")
    assert_equal 2, dates.length
    assert_equal Date.parse("2025-11-15"), dates[0]
    assert_equal Date.parse("2025-11-16"), dates[1]
  end

  test "parse_bulk_dates handles invalid dates gracefully" do
    controller = CaregiverAvailabilitiesController.new
    
    # Mix of valid and invalid dates
    dates = controller.send(:parse_bulk_dates, ["2025-11-15", "invalid-date", "2025-11-16"])
    
    # Should skip invalid and return only valid dates
    assert_equal 2, dates.length
    assert_equal Date.parse("2025-11-15"), dates[0]
    assert_equal Date.parse("2025-11-16"), dates[1]
  end

  test "parse_bulk_dates returns empty array for blank input" do
    controller = CaregiverAvailabilitiesController.new
    
    assert_equal [], controller.send(:parse_bulk_dates, nil)
    assert_equal [], controller.send(:parse_bulk_dates, "")
    assert_equal [], controller.send(:parse_bulk_dates, [])
  end

  test "parse_bulk_dates logs warning for invalid dates" do
    controller = CaregiverAvailabilitiesController.new
    
    # Capture log output
    assert_logs_match(/Invalid date format: invalid-date/) do
      controller.send(:parse_bulk_dates, ["invalid-date"])
    end
  end

  private

  def sign_in_as(user)
    payload = { uid: user.id }
    token = JWT.encode(payload, Rails.application.credentials.dig(:jwt_secret) || "dev_secret_change_me", "HS256")
    session[:jwt_token] = token
  end

  def assert_logs_match(pattern)
    old_logger = Rails.logger
    log_output = StringIO.new
    Rails.logger = Logger.new(log_output)
    
    yield
    
    assert_match pattern, log_output.string
  ensure
    Rails.logger = old_logger
  end
end
