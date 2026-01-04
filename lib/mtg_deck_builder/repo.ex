defmodule MtgDeckBuilder.Repo do
  use Ecto.Repo,
    otp_app: :mtg_deck_builder,
    adapter: Ecto.Adapters.Postgres
end
