class TranscriptionsController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:create]
  before_action :set_transcription, only: [:show, :summary, :destroy]

  def index
    @transcriptions = Transcription.all.order(created_at: :desc)
  end

  def transcribe
  end

  def create
    return render json: { error: "No audio file provided" }, status: :bad_request unless params[:audio]

    begin
      assembly_ai = AssemblyAiService.new
      
      temp_file = create_temp_audio_file(params[:audio])
      
      begin
        Rails.logger.info "Starting transcription for file: #{params[:audio].original_filename}"
        result = assembly_ai.transcribe_audio(temp_file)
        
        transcription = Transcription.create!(
          content: result[:text],
          audio_file_name: params[:audio].original_filename,
          external_id: result[:transcript_id]
        )

        Rails.logger.info "Transcription completed successfully: #{transcription.id}"

        render json: { 
          id: transcription.id,
          text: transcription.content,
          confidence: result[:confidence],
          speakers: result[:speakers],
          success: true 
        }

      ensure
        temp_file.close
        temp_file.unlink
      end

    rescue => e
      Rails.logger.error "Transcription error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      render json: { error: "Failed to transcribe audio: #{e.message}" }, status: :unprocessable_entity
    end
  end

  def show
    render json: {
      id: @transcription.id,
      content: @transcription.content,
      summary: @transcription.summary,
      audio_file_name: @transcription.audio_file_name,
      created_at: @transcription.created_at
    }
  end

  def summary
    if @transcription.summary.blank?
      begin
        assembly_ai = AssemblyAiService.new
        
        summary_text = if @transcription.external_id.present?
          assembly_ai.get_transcription_summary(@transcription.external_id, @transcription.content)
        else
          assembly_ai.send(:generate_extractive_summary, @transcription.content)
        end
        
        @transcription.update!(summary: summary_text)
        Rails.logger.info "Summary generated for transcription #{@transcription.id}"
        
      rescue => e
        Rails.logger.error "Summary generation error: #{e.message}"
        return render json: { error: "Failed to generate summary: #{e.message}" }, status: :unprocessable_entity
      end
    end

    render json: { 
      id: @transcription.id,
      summary: @transcription.summary 
    }
  end

  def destroy
    @transcription.destroy
    redirect_to transcriptions_path, notice: 'Transcription deleted successfully.'
  end

  private

  def set_transcription
    @transcription = Transcription.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Transcription not found" }, status: :not_found
  end

  def create_temp_audio_file(audio_param)
    file_extension = determine_file_extension(audio_param)
    temp_file = Tempfile.new(['audio', file_extension])
    temp_file.binmode
    
    if audio_param.respond_to?(:read)
      temp_file.write(audio_param.read)
    else
      temp_file.write(audio_param)
    end
    
    temp_file.rewind
    temp_file
  end

  def determine_file_extension(audio_param)
    if audio_param.respond_to?(:original_filename) && audio_param.original_filename
      extension = File.extname(audio_param.original_filename)
      return extension unless extension.empty?
    end
    
    '.webm'
  end
end