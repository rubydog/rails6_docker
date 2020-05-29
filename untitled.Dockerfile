
## Why size of docker image matters
# The size has an impact on following
# network latency – need to transfer Docker image over the web
# storage – need to store all these bits somewhere
# service availability and elasticity – when using a Docker scheduler, like Kubernetes, Swarm, Nomad, DC/OS or other (the scheduler can move containers between hosts)
# security – do you really, I mean really need the libpng package with all its CVE vulnerabilities for your Java application?
# development agility – small Docker images == faster build time and faster deployment

# Debian vs Alpine
# Should you use Debian or alpine base image depends on which linux packages (for example if your using geos libraries, they are not supported on alpine) you will use in your application. Debain is built around glibc and alpine is build around musl libc implementation. Glibc is by far the most common one and is faster than Musl, but Musl uses less space and is also written with more security in mind and avoids a lot of race conditions and security pitfalls. Comparision between libc's - https://www.etalabs.net/compare_libcs.html
# Debian is superior compared to Alpine Linux with regards to:

# quantity and quality of supported software
# the size and maturity of its development community
# amount of testing everything gets
# quality and quantity of documentation
# present and future security of its build infrastructure
# the size and maturity of its user community, number of people who know its ins and outs
# compatibility with existing software (libc vs musl)
# Alpine Linux's advantages on the other hand:

# it has a smaller filesystem footprint than stock Debian.
# its slightly more memory efficient thanks to BusyBox and musl library
# Alpine touts security as an advantage but aside from defaulting to a grsecurity kernel (which isn't advantage for containers) they don't really offer anything special.


FROM ruby:2.7.1-slim as Builder

ARG FOLDERS_TO_REMOVE
ARG BUNDLE_WITHOUT

RUN apt-get update && apt-get install -y gnupg2 curl

ADD https://dl.yarnpkg.com/debian/pubkey.gpg /tmp/yarn-pubkey.gpg
RUN apt-key add /tmp/yarn-pubkey.gpg && rm /tmp/yarn-pubkey.gpg
RUN echo 'deb http://dl.yarnpkg.com/debian/ stable main' > /etc/apt/sources.list.d/yarn.list

#RUN curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | apt-key add - && \
#	echo "deb https://dl.yarnpkg.com/debian/ stable main" | tee /etc/apt/sources.list.d/yarn.list && \
	## Above two lines are recommended way to install yarn on debian. https://classic.yarnpkg.com/en/docs/install/#debian-stable
# RUN	apt-get update && apt-get install -y --no-install-recommends --fix-missing -qq --auto-remove \
# 	build-essential \
# 	libpq-dev \
# 	git \
# 	tzdata \
#   	postgresql-client \
#   	nodejs \
# 	yarn 
	# apt-get clean && \
 # 	rm -rf /var/lib/apt/lists/* /var/lib/dpkg /var/lib/cache /var/lib/log

 RUN apt-get update && apt-get install -qq -y --fix-missing --no-install-recommends \
    build-essential \
    libpq-dev \
    git \
    tzdata \
    libgeos-dev \
    nodejs \
    yarn && \
    apt-get clean && \
  	rm -rf /var/lib/apt/lists/* /var/lib/dpkg /var/lib/cache /var/lib/log

 # Make 'code' directory and cd into it
WORKDIR /code

## TALK: Order of yarn install and bundle install is important, if in your project node packages will change more often that gems than you should do yarn install after bundle install because docker will invalidate subsequent cahces

## Do not copy whole app yet because it will unneccesarrily increase size of layer
COPY Gemfile* package.json yarn.lock ./
RUN yarn install --check-files && rm -rf /tmp/*

## Check bundle version on your local machine and install the same version to avoid incompatibilty, it is usually at the bottom of Gemfile - `BUNDLED WITH`
RUN gem install bundler:2.1.4 -N && \
	bundle config set without $BUNDLE_WITHOUT && \
	bundle config set no-cache 'true' && \
	# bundle config set clean 'true' && \
	bundle install -j4 --retry 3 && \
	rm -rf /usr/local/bundle/cache/*.gem && \
	rm -rf /usr/local/bundle/gems/*/test && \
	rm -rf /usr/local/bundle/gems/*/spec && \
	find /usr/local/bundle/gems/ -name "MIT-LICENSE" -delete && \
	find /usr/local/bundle/gems/ -name "LICENSE" -delete && \
	find /usr/local/bundle/gems/ -name "*.md" -delete && \
	find /usr/local/bundle/gems/ -name "*.markdown" -delete && \
	find /usr/local/bundle/gems/ -name "*.c" -delete && \
	find /usr/local/bundle/gems/ -name "*.rdoc" -delete && \
	find /usr/local/bundle/gems/ -name "*.o" -delete

COPY . /code

## Highlight Folders to Remove
RUN gem install activerecord-nulldb-adapter -N && \
	bundle exec rake assets:precompile RAILS_ENV=$RAILS_ENV DB_ADAPTER=nulldb && \
	gem uninstall activerecord-nulldb-adapter -a  && \
	yarn cache clean

# RUN rm -rf \
#         /tmp/* \
#         app/assets \
#         lib/assets \
#         test \
#         tmp/cache \
#         vendor/assets \
#         /log/*

###############################
# Stage Final
FROM ruby:2.7.1-slim as Final

ARG ADDITIONAL_PACKAGES

RUN apt-get update && apt-get install -qq -y --fix-missing --no-install-recommends --auto-remove \
    postgresql-client \
    nodejs \
    tzdata \
    ca-certificates \
    ${ADDITIONAL_PACKAGES} && \
    apt-get clean && \
  	rm -rf /var/lib/apt/lists/* /var/lib/dpkg /var/lib/cache /var/lib/log

# Copy app with gems from former build stage
COPY --from=Builder /usr/local/bundle/ /usr/local/bundle/
COPY --from=Builder /code /code

# RUN rm -rf /gems/ruby/2.7.1/cache/*.gem \
#   && find /gems/ruby/2.7.1/gems/ -name "*.c" -delete \
#   && find /gems/ruby/2.7.1/gems/ -name "*.o" -delete

WORKDIR /code

RUN mkdir -p tmp/pids

EXPOSE 3000

CMD ["bundle", "exec", "rails", "server"]


## The reason for order of statements in file is to use maximum cache and minimize changes to cache. for example your projects Gemfile might change often so execute those commands as late as possible. 

## Image size:
## Single stage: 825mb
## Multistage:
## 	without FOLDERS_TO_REMOVE: 518mb
##  with FOLDERS_TO_REMOVE: 392mb 
## 	Removing apt cache: 374mb
##  Remove gems cache file, markdown files, etc
## 

# Should I remove storage folder?

# copy node packages in second stage
# 