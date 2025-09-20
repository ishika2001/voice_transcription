Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Root route - shows transcription history
  root "transcriptions#index"
  
  # Main transcription page
  get "transcribe", to: "transcriptions#transcribe"
  
  # RESTful transcriptions routes
  resources :transcriptions do
    member do
      get :summary      # GET /transcriptions/:id/summary
    end
  end
  
  # Health check route (optional)
  get "health", to: proc { [200, {}, ["OK"]] }
end