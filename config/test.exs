import Config

# Tests start the pollers they need themselves, after installing `Req.Test`
# stubs. See `BccmDashboard.Application.pollers/0`.
config :bccm_dashboard, start_pollers: false

# Point both HTTP clients at `Req.Test`, so a test that forgets to install a
# stub fails loudly instead of reaching the real Semaphore or Gatus API. The
# credentials are placeholders — only their presence matters, since the stub
# never checks them.
# `retry: false` because a stubbed error response is the point of the test, not
# a blip to back off from — Req's default retry would spend seconds on it.
config :bccm_dashboard, BccmDashboard.Semaphore.Client,
  token: "test-token",
  base_url: "http://semaphore.test/api/v1alpha",
  req_options: [plug: {Req.Test, BccmDashboard.Semaphore.Client}, retry: false]

config :bccm_dashboard, BccmDashboard.Gatus.Client,
  base_url: "http://gatus.test",
  req_options: [plug: {Req.Test, BccmDashboard.Gatus.Client}, retry: false]

config :cerberus, endpoint: BccmDashboardWeb.Endpoint

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :bccm_dashboard, BccmDashboardWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "ZZ4O6gAxpspyl8XcCnKX7ThvelrzhEqAjnk2OprAkTvp2Max0bNgCRhzt4tTsQvM",
  server: false

# In test we don't send emails
config :bccm_dashboard, BccmDashboard.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true
