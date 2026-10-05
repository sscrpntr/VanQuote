require "test_helper"

class QuotesControllerTest < ActionDispatch::IntegrationTest
  test "should get new" do
    get quotes_new_url
    assert_response :success
  end

  test "should get create" do
    get quotes_create_url
    assert_response :success
  end

  test "should get show" do
    get quotes_show_url
    assert_response :success
  end
end
