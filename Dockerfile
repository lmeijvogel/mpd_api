FROM ubuntu:latest

RUN groupadd --gid 1000 api
RUN useradd --uid 1000 --gid 1000 --create-home api

RUN apt-get update && apt-get upgrade -y
RUN apt-get install -y ruby ruby-dev build-essential

RUN gem install bundler

WORKDIR /app

RUN chown -R api:api /app

USER api

COPY .bundle Gemfile Gemfile.lock /app/

RUN bundle config set --local path 'vendor/bundle'
RUN bundle install

CMD bundle exec rackup --host 0.0.0.0 --port 9292
