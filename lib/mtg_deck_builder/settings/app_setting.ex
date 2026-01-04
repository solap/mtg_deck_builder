defmodule MtgDeckBuilder.Settings.AppSetting do
  @moduledoc """
  Schema for application settings stored in the database.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer(),
          key: String.t() | nil,
          value: String.t() | nil,
          encrypted: boolean(),
          inserted_at: NaiveDateTime.t(),
          updated_at: NaiveDateTime.t()
        }

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
