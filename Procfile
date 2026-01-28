# Heroku Procfile
#
# release: Runs before deployment (migrations, etc.)
# web: The main web process

release: bundle exec rails db:migrate && bundle exec rails runner 'Setup::AutoInitialize.run'
web: bundle exec rails server -b 0.0.0.0 -p ${PORT:-3000}
