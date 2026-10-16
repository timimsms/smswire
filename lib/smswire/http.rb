require "net/http"
require "openssl"
require "uri"
require "json"

module Smswire
  # Minimal HTTP client shared by provider adapters. Network failures are
  # raised as Smswire::TransientError. Bodies are never logged.
  module HTTP
    NETWORK_ERRORS = [
      Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout,
      Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH, Errno::ETIMEDOUT,
      EOFError, IOError, SocketError, OpenSSL::SSL::SSLError
    ].freeze

    module_function

    def post_form(url, pairs, basic_auth: nil, headers: {}, open_timeout: 5, read_timeout: 15, provider: nil)
      uri = URI(url)
      request = Net::HTTP::Post.new(uri, {"User-Agent" => "smswire/#{Smswire::VERSION}"}.merge(headers))
      request.basic_auth(*basic_auth) if basic_auth
      request.content_type = "application/x-www-form-urlencoded"
      request.body = URI.encode_www_form(pairs)

      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout:, read_timeout:) do |http|
        http.request(request)
      end
    rescue *NETWORK_ERRORS => error
      raise TransientError.new("#{error.class}: #{error.message}", provider:)
    end

    def post_json(url, payload, headers: {}, open_timeout: 5, read_timeout: 15, provider: nil)
      uri = URI(url)
      request = Net::HTTP::Post.new(uri, {"User-Agent" => "smswire/#{Smswire::VERSION}",
                                          "Accept" => "application/json"}.merge(headers))
      request.content_type = "application/json"
      request.body = JSON.generate(payload)

      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout:, read_timeout:) do |http|
        http.request(request)
      end
    rescue *NETWORK_ERRORS => error
      raise TransientError.new("#{error.class}: #{error.message}", provider:)
    end

    def parse_json(body)
      JSON.parse(body.to_s)
    rescue JSON::ParserError
      {}
    end
  end
end
