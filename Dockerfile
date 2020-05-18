

FROM ruby:2.5 as Builder

RUN curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | apt-key add -
RUN echo "deb https://dl.yarnpkg.com/debian/ stable main" | tee /etc/apt/sources.list.d/yarn.list

RUN apt-get update -qq \
 && apt-get install -y nodejs postgresql-client yarn --no-install-recommends \
 && apt-get autoremove && apt-get clean \
 && rm -rf /var/lib/apt/lists/* /var/lib/dpkg /var/lib/cache /var/lib/log

RUN mkdir /rails6
WORKDIR /rails6

RUN gem install bundler:2
COPY Gemfile* ./
RUN bundle config build.nokogiri --use-system-libraries
RUN bundle install \
 && rm -rf /usr/local/bundle/cache/*.gem \
 && find /usr/local/bundle/gems/ -name "*.c" -delete \
 && find /usr/local/bundle/gems/ -name "*.o" -delete

COPY package.json yarn.lock ./
RUN yarn install --check-files

COPY . /rails6

EXPOSE 3000

CMD ["bundle", "exec", "rails", "server"]