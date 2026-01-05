defmodule MtgDeckBuilder.AI.ProviderConfig do
  @moduledoc """
  Ecto schema for AI provider configurations.

  Stores configuration for each AI provider (Anthropic, OpenAI, xAI, etc.)
  including encrypted API keys and status tracking.

  ## Key Resolution Order

  1. Encrypted API key in database (if set)
  2. Environment variable (fallback)

  ## Key Status

  - `not_configured` - No API key available (neither DB nor env)
  - `configured` - API key exists but not verified
  - `valid` - API key verified and working
  - `invalid` - API key failed verification
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @providers ~w(anthropic openai xai ollama)
  @key_statuses ~w(not_configured configured valid invalid)

  schema "provider_configs" do
    field :provider, :string
    field :api_key_env, :string
    field :encrypted_api_key, :binary
    field :base_url, :string
    field :enabled, :boolean, default: true
    field :key_status, :string, default: "not_configured"
    field :last_verified_at, :utc_datetime
    field :last_error, :string

    timestamps()
  end

  @doc """
  Changeset for creating a new provider config.
  """
  def create_changeset(provider_config, attrs) do
    provider_config
    |> cast(attrs, [:provider, :api_key_env, :base_url, :enabled])
    |> validate_required([:provider])
    |> validate_inclusion(:provider, @providers)
    |> validate_url(:base_url)
    |> unique_constraint(:provider)
  end

  @doc """
  Changeset for updating an existing provider config.
  """
  def update_changeset(provider_config, attrs) do
    provider_config
    |> cast(attrs, [:api_key_env, :base_url, :enabled, :key_status, :last_verified_at, :last_error])
    |> validate_url(:base_url)
    |> validate_inclusion(:key_status, @key_statuses)
  end

  @doc """
  Changeset for setting an API key.
  Encrypts the key before storing.
  """
  def set_api_key_changeset(provider_config, api_key) do
    encrypted = encrypt_api_key(api_key)

    provider_config
    |> change(%{
      encrypted_api_key: encrypted,
      key_status: "configured",
      last_verified_at: nil,
      last_error: nil
    })
  end

  @doc """
  Changeset for clearing an API key.
  """
  def clear_api_key_changeset(provider_config) do
    # Determine new status based on whether env var exists
    new_status =
      if has_env_key?(provider_config) do
        "configured"
      else
        "not_configured"
      end

    provider_config
    |> change(%{
      encrypted_api_key: nil,
      key_status: new_status,
      last_verified_at: nil,
      last_error: nil
    })
  end

  @doc """
  Changeset for updating verification status.
  """
  def verification_changeset(provider_config, :valid) do
    provider_config
    |> change(%{
      key_status: "valid",
      last_verified_at: DateTime.utc_now() |> DateTime.truncate(:second),
      last_error: nil
    })
  end

  def verification_changeset(provider_config, {:invalid, error}) do
    provider_config
    |> change(%{
      key_status: "invalid",
      last_verified_at: DateTime.utc_now() |> DateTime.truncate(:second),
      last_error: truncate_error(error)
    })
  end

  defp validate_url(changeset, field) do
    case get_change(changeset, field) do
      nil ->
        changeset

      url when is_binary(url) and url != "" ->
        case URI.parse(url) do
          %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and not is_nil(host) ->
            changeset

          _ ->
            add_error(changeset, field, "must be a valid HTTP(S) URL")
        end

      _ ->
        changeset
    end
  end

  @doc """
  Gets the API key for this provider.
  Checks encrypted DB key first, then falls back to environment variable.
  Returns nil if no key is available.
  """
  def get_api_key(%__MODULE__{} = config) do
    # Try encrypted key in DB first
    case decrypt_api_key(config.encrypted_api_key) do
      nil ->
        # Fall back to environment variable
        get_env_key(config)

      key ->
        key
    end
  end

  @doc """
  Gets the API key from environment variable only.
  """
  def get_env_key(%__MODULE__{api_key_env: env_var}) when is_binary(env_var) and env_var != "" do
    System.get_env(env_var)
  end

  def get_env_key(_), do: nil

  @doc """
  Checks if the provider has an environment variable key configured.
  """
  def has_env_key?(%__MODULE__{} = config) do
    get_env_key(config) != nil
  end

  @doc """
  Checks if the provider has a database key configured.
  """
  def has_db_key?(%__MODULE__{encrypted_api_key: key}) when is_binary(key) and key != "", do: true
  def has_db_key?(_), do: false

  @doc """
  Checks if the provider has any API key configured (DB or env).
  """
  def has_api_key?(%__MODULE__{} = config) do
    has_db_key?(config) or has_env_key?(config)
  end

  @doc """
  Returns the source of the current API key.
  """
  def key_source(%__MODULE__{} = config) do
    cond do
      has_db_key?(config) -> :database
      has_env_key?(config) -> :environment
      true -> :none
    end
  end

  @doc """
  Returns the list of valid providers.
  """
  def valid_providers, do: @providers

  @doc """
  Returns the list of valid key statuses.
  """
  def valid_key_statuses, do: @key_statuses

  # Encryption helpers (Base64 for now - use proper encryption in production)

  defp encrypt_api_key(nil), do: nil
  defp encrypt_api_key(""), do: nil
  defp encrypt_api_key(key) when is_binary(key), do: Base.encode64(key)

  defp decrypt_api_key(nil), do: nil
  defp decrypt_api_key(""), do: nil

  defp decrypt_api_key(encrypted) when is_binary(encrypted) do
    case Base.decode64(encrypted) do
      {:ok, key} -> key
      :error -> nil
    end
  end

  defp truncate_error(error) when is_binary(error) do
    String.slice(error, 0, 500)
  end

  defp truncate_error(error), do: inspect(error) |> truncate_error()
end
