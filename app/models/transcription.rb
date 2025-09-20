class Transcription < ApplicationRecord
  validates :content, presence: true

  def has_summary?
    summary.present?
  end
end
