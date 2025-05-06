defmodule CymApp.Repo do
  use Ecto.Repo,
    otp_app: :cym_app,
    adapter: Ecto.Adapters.Postgres
end
