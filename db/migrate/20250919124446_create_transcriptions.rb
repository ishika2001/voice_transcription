class CreateTranscriptions < ActiveRecord::Migration[8.0]
  def change
    create_table :transcriptions do |t|
      t.text :content
      t.text :summary

      t.timestamps
    end
  end
end
