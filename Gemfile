source "https://rubygems.org"

gemspec

# CI sets RAILS_VERSION (e.g. "7.1") to test each supported Rails line.
if (rails_version = ENV["RAILS_VERSION"])
  requirement = "~> #{rails_version}.0"
  gem "actionpack", requirement
  gem "activejob", requirement
  gem "activesupport", requirement
  gem "railties", requirement
  # ActiveSupport 7.1's to_json passes options that json 3.0 removed.
  gem "json", "< 3" if rails_version == "7.1"
end

gem "rake", "~> 13.0"
gem "minitest", "~> 5.25"
gem "webmock", "~> 3.23"
gem "phonelib", "~> 0.10", require: false
gem "rspec-expectations", "~> 3.13", require: false
gem "standard", "~> 1.0"
