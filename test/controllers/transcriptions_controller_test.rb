require "test_helper"

class TranscriptionsControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get transcriptions_index_url
    assert_response :success
  end

  test "should get create" do
    get transcriptions_create_url
    assert_response :success
  end

  test "should get show" do
    get transcriptions_show_url
    assert_response :success
  end

  test "should get summary" do
    get transcriptions_summary_url
    assert_response :success
  end
end
