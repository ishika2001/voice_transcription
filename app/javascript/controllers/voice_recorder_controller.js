import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "startBtn", "stopBtn", "status", "liveTranscription", 
    "resultsSection", "finalTranscription", "summaryBtn", 
    "summarySection", "summaryContent", "errorMessage", "loading"
  ]

  connect() {
    this.mediaRecorder = null
    this.audioChunks = []
    this.recognition = null
    this.currentTranscriptionId = null
    this.isRecording = false
    
    this.setupSpeechRecognition()
  }

  setupSpeechRecognition() {
    if (!('webkitSpeechRecognition' in window) && !('SpeechRecognition' in window)) {
      this.showError('Speech recognition not supported in this browser. Please use Chrome or Edge.')
      return
    }

    const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition
    this.recognition = new SpeechRecognition()
    
    this.recognition.continuous = true
    this.recognition.interimResults = true
    this.recognition.lang = 'en-US'
    
    let finalTranscript = ''
    
    this.recognition.onresult = (event) => {
      let interimTranscript = ''
      
      for (let i = event.resultIndex; i < event.results.length; i++) {
        const transcript = event.results[i][0].transcript
        
        if (event.results[i].isFinal) {
          finalTranscript += transcript + ' '
        } else {
          interimTranscript += transcript
        }
      }
      
      this.updateLiveTranscription(finalTranscript, interimTranscript)
    }
    
    this.recognition.onend = () => {
      if (this.isRecording) {
        this.recognition.start()
      }
    }
    
    this.recognition.onerror = (event) => {
      console.error('Speech recognition error:', event.error)
      if (event.error !== 'aborted') {
        this.showError(`Speech recognition error: ${event.error}`)
      }
    }
  }

  async startRecording() {
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true })
      
      this.startBtnTarget.disabled = true
      this.stopBtnTarget.disabled = false
      this.statusTarget.textContent = "Recording... Speak now!"
      this.statusTarget.className = "recording-status recording"
      this.isRecording = true
      
      this.liveTranscriptionTarget.innerHTML = '<p class="live-text">Listening...</p>'
      this.hideResults()
      this.hideError()
      
      this.audioChunks = []
      this.mediaRecorder = new MediaRecorder(stream)
      
      this.mediaRecorder.ondataavailable = (event) => {
        this.audioChunks.push(event.data)
      }
      
      this.mediaRecorder.onstop = () => {
        this.processRecording()
        stream.getTracks().forEach(track => track.stop())
      }
      
      this.mediaRecorder.start()
      
      if (this.recognition) {
        this.recognition.start()
      }
      
    } catch (error) {
      console.error('Error accessing microphone:', error)
      this.showError('Could not access microphone. Please ensure you have granted permission.')
      this.resetControls()
    }
  }

  stopRecording() {
    this.isRecording = false
    this.startBtnTarget.disabled = false
    this.stopBtnTarget.disabled = true
    this.statusTarget.textContent = "Processing..."
    this.statusTarget.className = "recording-status processing"
    
    if (this.mediaRecorder && this.mediaRecorder.state !== 'inactive') {
      this.mediaRecorder.stop()
    }
    
    if (this.recognition) {
      this.recognition.stop()
    }
  }

  updateLiveTranscription(finalText, interimText) {
    const displayText = (finalText + interimText).trim()
    
    if (displayText) {
      this.liveTranscriptionTarget.innerHTML = `
        <p class="live-text">
          <span class="final">${finalText}</span>
          <span class="interim">${interimText}</span>
        </p>
      `
    } else {
      this.liveTranscriptionTarget.innerHTML = '<p class="live-text">Listening...</p>'
    }
  }

  async processRecording() {
    if (this.audioChunks.length === 0) {
      this.showError('No audio recorded. Please try again.')
      this.resetControls()
      return
    }

    this.showLoading()
    
    try {
      const audioBlob = new Blob(this.audioChunks, { type: 'audio/webm;codecs=opus' })
      const formData = new FormData()
      formData.append('audio', audioBlob, 'recording.webm')
      
      const response = await fetch('/transcriptions', {
        method: 'POST',
        body: formData,
        headers: {
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content
        }
      })
      
      const data = await response.json()
      
      if (data.success) {
        this.currentTranscriptionId = data.id
        this.showResults(data.text, data.speakers, data.confidence)
      } else {
        this.showError(data.error || 'Failed to transcribe audio')
      }
      
    } catch (error) {
      console.error('Error processing recording:', error)
      this.showError('Failed to process recording. Please try again.')
    } finally {
      this.hideLoading()
      this.resetControls()
    }
  }

  showResults(transcription, speakers = null, confidence = null) {
    if (confidence) {
      const confidencePercent = Math.round(confidence * 100)
      transcription = `[Confidence: ${confidencePercent}%]\n\n${transcription}`
    }
    
    if (speakers && speakers.length > 1) {
      let speakerText = '\n\n--- Speaker Breakdown ---\n'
      speakers.forEach((speaker, index) => {
        speakerText += `Speaker ${speaker.speaker}: ${speaker.text}\n\n`
      })
      transcription += speakerText
    }
    
    this.finalTranscriptionTarget.textContent = transcription
    this.resultsSectionTarget.style.display = 'block'
    this.summaryBtnTarget.style.display = 'inline-block'
    this.summarySectionTarget.style.display = 'none'
  }

  async generateSummary() {
    if (!this.currentTranscriptionId) {
      this.showError('No transcription available for summary')
      return
    }

    this.summaryBtnTarget.disabled = true
    this.summaryBtnTarget.textContent = 'Generating Summary...'
    
    try {
      const response = await fetch(`/transcriptions/${this.currentTranscriptionId}/summary`)
      const data = await response.json()
      
      if (data.summary) {
        this.summaryContentTarget.textContent = data.summary
        this.summaryBtnTarget.style.display = 'none'
        this.summarySectionTarget.style.display = 'block'
      } else {
        this.showError(data.error || 'Failed to generate summary')
      }
      
    } catch (error) {
      console.error('Error generating summary:', error)
      this.showError('Failed to generate summary. Please try again.')
    } finally {
      this.summaryBtnTarget.disabled = false
      this.summaryBtnTarget.textContent = 'Generate Summary'
    }
  }

  copyTranscription() {
    const text = this.finalTranscriptionTarget.textContent
    navigator.clipboard.writeText(text).then(() => {
      const originalText = event.target.textContent
      event.target.textContent = '✅ Copied!'
      setTimeout(() => {
        event.target.textContent = originalText
      }, 2000)
    })
  }

  newRecording() {
    this.hideResults()
    this.currentTranscriptionId = null
    this.liveTranscriptionTarget.innerHTML = '<p class="placeholder">Click "Start Listening" to begin transcription...</p>'
  }

  showResults(transcription) {
    this.finalTranscriptionTarget.textContent = transcription
    this.resultsSectionTarget.style.display = 'block'
    this.summaryBtnTarget.style.display = 'inline-block'
    this.summarySectionTarget.style.display = 'none'
  }

  hideResults() {
    this.resultsSectionTarget.style.display = 'none'
  }

  showError(message) {
    this.errorMessageTarget.textContent = message
    this.errorMessageTarget.style.display = 'block'
  }

  hideError() {
    this.errorMessageTarget.style.display = 'none'
  }

  showLoading() {
    this.loadingTarget.style.display = 'block'
  }

  hideLoading() {
    this.loadingTarget.style.display = 'none'
  }

  resetControls() {
    this.startBtnTarget.disabled = false
    this.stopBtnTarget.disabled = true
    this.statusTarget.textContent = "Ready to record"
    this.statusTarget.className = "recording-status"
  }
}