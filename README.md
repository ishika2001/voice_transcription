Tech-stack:

Ruby on Rails 7+
PostgreSQL (database)
Stimulus / Vanilla JS for frontend
OpenAI API (Whisper + GPT)
RSpec for testing


Set-up instruction:

git clone https://github.com/your-username/voice_transcriber.git
cd voice_transcriber
bundle install
rails db:create db:migrate


Create a .env file in the project root:
OPENAI_API_KEY=sk-your-real-openai-key-here


Start the server
rails s

bundle exec rspec
