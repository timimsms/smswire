module Smswire
  # Builds callback URLs from Smswire.config.callbacks_url and reconstructs
  # the public URL of an incoming callback for signature checks.
  module Callbacks
    module_function

    def status_url(provider, delivery = nil)
      base = Smswire.config.callbacks_url.presence or return nil
      url = "#{base.chomp("/")}/status/#{provider}"
      delivery ? "#{url}?delivery_id=#{delivery.id}" : url
    end

    # The URL the provider signed. Behind a TLS-terminating proxy the
    # request may look like plain HTTP, so when callbacks_url is configured
    # its scheme, host, and port are used with the request path.
    def request_url(request)
      base = Smswire.config.callbacks_url.presence or return request.original_url
      uri = URI(base)
      origin = "#{uri.scheme}://#{uri.host}"
      origin += ":#{uri.port}" unless uri.port == uri.default_port
      origin + request.original_fullpath
    end
  end
end
