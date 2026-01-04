defmodule MtgDeckBuilder.Settings do
  @moduledoc """
  Context for managing application settings.

  Handles API keys and provider selection for AI services.
  """

  alias MtgDeckBuilder.Repo
  alias MtgDeckBuilder.Settings.AppSetting

  # Setting keys
  @anthropic_key "anthropic_api_key"
  @openai_key "openai_api_key"
  @xai_key "xai_api_key"
  @active_provider "active_ai_provider"
  @anthropic_model "anthropic_model"
  @openai_model "openai_model"
  @xai_model "xai_model"

  @doc """
  Returns a list of available AI providers.
  """
  def available_providers do
    [
      %{id: "anthropic", name: "Anthropic Claude", models: anthropic_models()},
      %{id: "openai", name: "OpenAI", models: openai_models()},
      %{id: "xai", name: "xAI Grok", models: xai_models()}
    ]
  end

  defp anthropic_models do
    [
      %{id: "claude-3-haiku-20240307", name: "Claude 3 Haiku (Fast, Cheap)"},
      %{id: "claude-3-5-sonnet-20241022", name: "Claude 3.5 Sonnet (Balanced)"},
      %{id: "claude-3-5-haiku-20241022", name: "Claude 3.5 Haiku (Fast)"}
    ]
  end

  defp openai_models do
    [
      %{id: "gpt-4o-mini", name: "GPT-4o Mini (Fast, Cheap)"},
      %{id: "gpt-4o", name: "GPT-4o (Balanced)"},
      %{id: "gpt-4-turbo", name: "GPT-4 Turbo"}
    ]
  end

  defp xai_models do
    [
      %{id: "grok-beta", name: "Grok Beta"}
    ]
  end

  @doc """
  Gets the active AI provider.
  Returns "anthropic" by default.
  """
  @spec get_active_provider() :: String.t()
  def get_active_provider do
    get_setting(@active_provider) || "anthropic"
  end

  @doc """
  Sets the active AI provider.
  """
  @spec set_active_provider(String.t()) :: {:ok, AppSetting.t()} | {:error, Ecto.Changeset.t()}
  def set_active_provider(provider) when provider in ["anthropic", "openai", "xai"] do
    set_setting(@active_provider, provider)
  end

  @doc """
  Gets the API key for a provider.
  Returns nil if not set.
  """
  @spec get_api_key(String.t()) :: String.t() | nil
  def get_api_key("anthropic"), do: get_encrypted_setting(@anthropic_key)
  def get_api_key("openai"), do: get_encrypted_setting(@openai_key)
  def get_api_key("xai"), do: get_encrypted_setting(@xai_key)
  def get_api_key(_), do: nil

  @doc """
  Sets the API key for a provider.
  """
  @spec set_api_key(String.t(), String.t()) :: {:ok, AppSetting.t()} | {:error, Ecto.Changeset.t()}
  def set_api_key("anthropic", key), do: set_encrypted_setting(@anthropic_key, key)
  def set_api_key("openai", key), do: set_encrypted_setting(@openai_key, key)
  def set_api_key("xai", key), do: set_encrypted_setting(@xai_key, key)
  def set_api_key(_, _), do: {:error, :invalid_provider}

  @doc """
  Gets the model for a provider.
  """
  @spec get_model(String.t()) :: String.t() | nil
  def get_model("anthropic"), do: get_setting(@anthropic_model) || "claude-3-haiku-20240307"
  def get_model("openai"), do: get_setting(@openai_model) || "gpt-4o-mini"
  def get_model("xai"), do: get_setting(@xai_model) || "grok-beta"
  def get_model(_), do: nil

  @doc """
  Sets the model for a provider.
  """
  @spec set_model(String.t(), String.t()) :: {:ok, AppSetting.t()} | {:error, Ecto.Changeset.t()}
  def set_model("anthropic", model), do: set_setting(@anthropic_model, model)
  def set_model("openai", model), do: set_setting(@openai_model, model)
  def set_model("xai", model), do: set_setting(@xai_model, model)
  def set_model(_, _), do: {:error, :invalid_provider}

  @doc """
  Checks if a provider has an API key configured.
  """
  @spec has_api_key?(String.t()) :: boolean()
  def has_api_key?(provider) do
    key = get_api_key(provider)
    key != nil and key != ""
  end

  @doc """
  Gets all settings for display (masks API keys).
  """
  @spec get_all_settings() :: map()
  def get_all_settings do
    %{
      active_provider: get_active_provider(),
      anthropic: %{
        has_key: has_api_key?("anthropic"),
        model: get_model("anthropic")
      },
      openai: %{
        has_key: has_api_key?("openai"),
        model: get_model("openai")
      },
      xai: %{
        has_key: has_api_key?("xai"),
        model: get_model("xai")
      }
    }
  end

  # Private helpers

  defp get_setting(key) do
    case Repo.get_by(AppSetting, key: key) do
      nil -> nil
      setting -> setting.value
    end
  end

  defp set_setting(key, value) do
    case Repo.get_by(AppSetting, key: key) do
      nil ->
        %AppSetting{}
        |> AppSetting.changeset(%{key: key, value: value, encrypted: false})
        |> Repo.insert()

      setting ->
        setting
        |> AppSetting.changeset(%{value: value})
        |> Repo.update()
    end
  end

  defp get_encrypted_setting(key) do
    case Repo.get_by(AppSetting, key: key) do
      nil -> nil
      setting -> decode_value(setting.value)
    end
  end

  defp set_encrypted_setting(key, value) do
    encoded = encode_value(value)

    case Repo.get_by(AppSetting, key: key) do
      nil ->
        %AppSetting{}
        |> AppSetting.changeset(%{key: key, value: encoded, encrypted: true})
        |> Repo.insert()

      setting ->
        setting
        |> AppSetting.changeset(%{value: encoded, encrypted: true})
        |> Repo.update()
    end
  end

  # Simple encoding for now - in production, use proper encryption
  defp encode_value(nil), do: nil
  defp encode_value(""), do: ""
  defp encode_value(value), do: Base.encode64(value)

  defp decode_value(nil), do: nil
  defp decode_value(""), do: ""
  defp decode_value(encoded) do
    case Base.decode64(encoded) do
      {:ok, value} -> value
      :error -> encoded
    end
  end
end
