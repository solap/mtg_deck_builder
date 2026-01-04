defmodule MtgDeckBuilder.Settings.AppSetting do
  @moduledoc """
  Schema for application settings stored in the database.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "app_settings" do
    field :key, :string
    field :value, :string
    field :encrypted, :boolean, default: false

    timestamps()
  end

  @doc false
  def changeset(setting, attrs) do
    setting
    |> cast(attrs, [:key, :value, :encrypted])
    |> validate_required([:key])
    |> unique_constraint(:key)
  end
end
