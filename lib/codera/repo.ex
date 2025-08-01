defmodule Codera.Repo do
  use Ecto.Repo,
    otp_app: :codera,
    adapter: Ecto.Adapters.Postgres
end
