require 'httparty'

class AssemblyAiService
  include HTTParty
  
  BASE_URL = 'https://api.assemblyai.com/v2'.freeze
  
  def initialize
    @api_key = ENV['ASSEMBLYAI_API_KEY']
    
    @headers = {
      'Authorization' => "Bearer #{@api_key}",
      'Content-Type' => 'application/json'
    }
  end

  def transcribe_audio(audio_file)
    Rails.logger.info "Starting AssemblyAI transcription process"
    
    audio_url = upload_audio(audio_file)
    Rails.logger.info "Audio uploaded successfully: #{audio_url}"
    
    transcript_id = submit_transcription_request(audio_url)
    Rails.logger.info "Transcription request submitted: #{transcript_id}"
    
    result = poll_for_completion(transcript_id)
    Rails.logger.info "Transcription completed successfully"
    
    {
      transcript_id: transcript_id,
      text: result['text'],
      confidence: result['confidence'],
      speakers: extract_speakers(result)
    }
  end

  def get_transcription_summary(transcript_id, content)
    begin
      response = HTTParty.get(
        "#{BASE_URL}/transcript/#{transcript_id}",
        headers: { 'Authorization' => @api_key }
      )
      
      if response.success? && response.parsed_response['summary']
        return response.parsed_response['summary']
      end
    rescue => e
      Rails.logger.warn "AssemblyAI summary not available: #{e.message}"
    end
    
    generate_extractive_summary(content)
  end

  private

  def upload_audio(audio_file)
    upload_headers = {
      'Authorization' => @api_key,
      'Content-Type' => 'application/octet-stream'
    }

    audio_data = audio_file.respond_to?(:read) ? audio_file.read : File.read(audio_file)
    
    response = HTTParty.post(
      "#{BASE_URL}/upload",
      body: audio_data,
      headers: upload_headers
    )

    unless response.success?
      raise "Audio upload failed: #{response.code} - #{response.body}"
    end

    response.parsed_response['upload_url']
  end

  def submit_transcription_request(audio_url="https://bit.ly/3yxKEIY")
    request_body = {
      audio_url: audio_url  
    }

    response = HTTParty.post(
      "#{BASE_URL}/transcript",
      body: request_body.to_json,
      headers: @headers
    )

    unless response.success?
      raise "Transcription request failed: #{response.code} - #{response.body}"
    end

    response.parsed_response['id']
  end

  def poll_for_completion(transcript_id)
    max_attempts = 60 
    attempt = 0

    loop do
      attempt += 1
      
      response = HTTParty.get(
        "#{BASE_URL}/transcript/#{transcript_id}",
        headers: { 'Authorization' => @api_key }
      )

      unless response.success?
        raise "Failed to get transcription status: #{response.code} - #{response.body}"
      end

      result = response.parsed_response
      status = result['status']

      Rails.logger.info "Transcription status (attempt #{attempt}): #{status}"

      case status
      when 'completed'
        return result
      when 'error'
        error_message = result['error'] || 'Unknown error occurred'
        raise "Transcription failed: #{error_message}"
      when 'processing', 'queued'
        if attempt >= max_attempts
          raise "Transcription timeout: Maximum polling attempts (#{max_attempts}) reached"
        end
        sleep 5
      else
        Rails.logger.warn "Unknown transcription status: #{status}"
        if attempt >= max_attempts
          raise "Transcription timeout with unknown status: #{status}"
        end
        sleep 5
      end
    end
  end

  def extract_speakers(result)
    return [] unless result['utterances']
    
    speakers = []
    current_speaker = nil
    current_text = ""
    
    result['utterances'].each do |utterance|
      speaker = utterance['speaker']
      text = utterance['text']
      
      if current_speaker == speaker
        current_text += " #{text}"
      else
        if current_speaker
          speakers << {
            speaker: current_speaker,
            text: current_text.strip,
            start: speakers.last&.dig(:end) || 0
          }
        end
        current_speaker = speaker
        current_text = text
      end
    end
    
    if current_speaker
      speakers << {
        speaker: current_speaker,
        text: current_text.strip,
        start: speakers.last&.dig(:end) || 0
      }
    end
    
    speakers
  end

  def generate_extractive_summary(text)
    sentences = text.split(/[.!?]+/).map(&:strip).reject(&:empty?)
    
    return text if sentences.length <= 3
    
    word_freq = calculate_word_frequency(text)
    scored_sentences = []
    
    sentences.each_with_index do |sentence, index|
      score = calculate_sentence_score(sentence, word_freq, index, sentences.length)
      scored_sentences << { sentence: sentence, score: score, index: index }
    end
    
    num_sentences = [3, sentences.length].min
    selected_sentences = scored_sentences
                          .sort_by { |s| -s[:score] }
                          .first(num_sentences)
                          .sort_by { |s| s[:index] }
                          .map { |s| s[:sentence] }
    
    selected_sentences.join('. ') + '.'
  end

  def calculate_word_frequency(text)
    stop_words = %w[the a an and or but in on at to for of with by from about into through during before after above below up down out off over under again further then once here there when where why how all any both each few more most other some such no nor not only own same so than too very can will just should could would may might must shall]
    
    words = text.downcase.gsub(/[^\w\s]/, '').split
    word_count = Hash.new(0)
    
    words.each do |word|
      word_count[word] += 1 unless stop_words.include?(word) || word.length < 3
    end
    
    max_freq = word_count.values.max || 1
    word_count.transform_values { |count| count.to_f / max_freq }
  end

  def calculate_sentence_score(sentence, word_freq, position, total_sentences)
    words = sentence.downcase.gsub(/[^\w\s]/, '').split
    return 0 if words.empty?
    
    word_score = words.sum { |word| word_freq[word] || 0 } / words.length.to_f
    
    position_score = 0
    position_score += 0.3 if position == 0
    position_score += 0.2 if position == total_sentences - 1
    position_score += 0.1 if position < total_sentences * 0.2
    
    length_score = 0
    word_count = words.length
    if word_count >= 8 && word_count <= 30
      length_score = 0.1
    elsif word_count < 5
      length_score = -0.2
    end
    
    keyword_score = 0
    important_keywords = %w[important key main primary summary conclusion decision action result therefore however additionally furthermore moreover]
    important_keywords.each do |keyword|
      keyword_score += 0.15 if sentence.downcase.include?(keyword)
    end
    
    word_score + position_score + length_score + keyword_score
  end
end