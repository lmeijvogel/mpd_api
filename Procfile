# The -o is necessary to allow the api to receive requests from react.
# I'm not sure why.
api:   bundle exec rackup -o 0.0.0.0 -p 4567
react: cd frontend-react ; npm start
sidekiq: bundle exec ./vendor/bundle/ruby/2.7.0/bin/sidekiq -r ./lib/cover_loader.rb
