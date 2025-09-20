class AddFieldsToTranscriptions < ActiveRecord::Migration[8.0]
  def change
    add_column :transcriptions, :audio_file_name, :string
    add_column :transcriptions, :external_id, :string
  end
end
