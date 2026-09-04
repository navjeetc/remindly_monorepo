# frozen_string_literal: true

# Keeps a reminder-link token out of Rails' own request log.
#
# `config.filter_parameters` does not reach path segments. It filters the query
# string and the parsed parameters, and `Rails::Rack::Logger` writes its
# "Started GET ..." line from `request.filtered_path` — which is the raw path
# whenever there is no query string. So `/r/<token>` was being written verbatim,
# once per redemption, into stdout and therefore into whatever collects it.
#
# The token is a credential: replaying it grants an indefinite session to that
# care receiver's reminders. A log line is a poor place for one, and this
# project has already fixed the same class of leak once, when reminder titles
# were appearing in deploy logs.
#
# **What this does not cover.** kamal-proxy logs every request as JSON with its
# own `path` field, before Rails sees it, and nothing in the application can
# filter that. The residual exposure is the proxy's container log on our own
# server, once per redemption rather than per page view. Revocation exists partly
# for this: a link that turns up somewhere it should not be can be ended.
#
# This comment used to say the proxy was the *only* residual, and was wrong.
# Ahoy records `request.original_url` as a visit's landing_page, so every
# redemption also wrote the token into `ahoy_visits` — in plaintext, kept
# indefinitely, and rendered on the admin audit screen, which is a worse place
# for a credential than a log that rotates. `Ahoy::Store#credential_in_the_path?`
# closes that. The lesson generalises: a credential in a URL comes to rest
# wherever URLs are recorded, and each of those places has to be found.
module FilterReminderLinkPath
  REDACTED = "/r/[FILTERED]"

  # Anchored, and stops at the next / or ? so it cannot swallow a longer path
  # that merely begins with /r/.
  TOKEN_IN_PATH = %r{\A/r/[^/?]+}

  def filtered_path
    super.sub(TOKEN_IN_PATH, REDACTED)
  end
end

ActiveSupport.on_load(:action_dispatch_request) do
  prepend FilterReminderLinkPath
end
