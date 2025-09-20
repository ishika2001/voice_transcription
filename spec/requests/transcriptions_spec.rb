# spec/requests/transcriptions_spec.rb
require "rails_helper"

RSpec.describe "Summaries", type: :request do
  it "returns summary for transcription" do
    t = Transcription.create!(content: "Today we discussed project updates and next steps.")
    get "/summary/#{t.id}"
    expect(response).to be_successful
    json = JSON.parse(response.body)
    expect(json["summary"]).to be_present
  end
end
