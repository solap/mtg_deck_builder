defmodule MtgDeckBuilder.AI.KeyVerifier do
  @moduledoc """
  Verifies AI provider API keys by making minimal test requests.

  Each provider has a lightweight verification method:
  - Anthropic: Small message request
  - OpenAI: Models list (no tokens used)
  - xAI: Small chat request
  """

  alias MtgDeckBuilder.AI.{AgentRegistry, ProviderConfig}

  require Logger

  @doc """
  Verifies an API key for a provider and updates the provider status.

  Returns `{:ok, :valid}` if the key works, or `{:error, reason}` if it fails.
  Also updates the provider's verification status in the database.
  """
  def verify_and_update(provider) when is_binary(provider) do
    case AgentRegistry.get_provider(provider) do
      nil ->
        {:error, "Provider not found: #{provider}"}

      config ->
        case ProviderConfig.get_api_key(config) do
          nil ->
            {:error, "No API key configured for #{provider}"}

          api_key ->
            result = verify_key(provider, api_key, config.base_url)

            # Update provider status
            case result do
              {:ok, :valid} ->
                AgentRegistry.set_provider_verification(provider, :valid)
                {:ok, :valid}

              {:error, reason} ->
                AgentRegistry.set_provider_verification(provider, {:invalid, reason})
                {:error, reason}
            end
        end
    end
  end

  @doc """
  Verifies an API key without updating the database.
  Useful for testing keys before saving.
  """
  def verify_key(provider, api_key, base_url \\ nil)

  def verify_key("anthropic", api_key, _base_url) do
    verify_anthropic(api_key)
  end

  def verify_key("openai", api_key, _base_url) do
    verify_openai(api_key)
  end

  def verify_key("xai", api_key, base_url) do
    verify_xai(api_key, base_url || "https://api.x.ai/v1")
  end

  def verify_key("ollama", _api_key, base_url) do
    verify_ollama(base_url || "http://localhost:11434")
  end

  def verify_key(provider, _api_key, _base_url) do
    {:error, "Unknown provider: #{provider}"}
  end

  # Anthropic verification - minimal message request
  defp verify_anthropic(api_key) do
    url = "https://api.anthropic.com/v1/messages"

    headers = [
      {"x-api-key", api_key},
      {"anthropic-version", "2023-06-01"},
      {"content-type", "application/json"}
    ]

    # Minimal request - just "hi" with 1 max token
    body =
      Jason.encode!(%{
        model: "claude-3-haiku-20240307",
        max_tokens: 1,
        messages: [%{role: "user", content: "hi"}]
      })

    case Tesla.post(client(), url, body, headers: headers) do
      {:ok, %Tesla.Env{status: 200}} ->
        {:ok, :valid}

      {:ok, %Tesla.Env{status: 401, body: body}} ->
        {:error, parse_error(body, "Invalid API key")}

      {:ok, %Tesla.Env{status: 403, body: body}} ->
        {:error, parse_error(body, "Access forbidden")}

      {:ok, %Tesla.Env{status: status, body: body}} ->
        {:error, parse_error(body, "HTTP #{status}")}

      {:error, reason} ->
        {:error, "Connection error: #{inspect(reason)}"}
    end
  end

  # OpenAI verification - list models (free, no tokens used)
  defp verify_openai(api_key) do
    url = "https://api.openai.com/v1/models"

    headers = [
      {"authorization", "Bearer #{api_key}"},
      {"content-type", "application/json"}
    ]

    case Tesla.get(client(), url, headers: headers) do
      {:ok, %Tesla.Env{status: 200}} ->
        {:ok, :valid}

      {:ok, %Tesla.Env{status: 401, body: body}} ->
        {:error, parse_error(body, "Invalid API key")}

      {:ok, %Tesla.Env{status: status, body: body}} ->
        {:error, parse_error(body, "HTTP #{status}")}

      {:error, reason} ->
        {:error, "Connection error: #{inspect(reason)}"}
    end
  end

  # xAI verification - minimal chat request
  defp verify_xai(api_key, base_url) do
    url = "#{base_url}/chat/completions"

    headers = [
      {"authorization", "Bearer #{api_key}"},
      {"content-type", "application/json"}
    ]

    body =
      Jason.encode!(%{
        model: "grok-beta",
        max_tokens: 1,
        messages: [%{role: "user", content: "hi"}]
      })

    case Tesla.post(client(), url, body, headers: headers) do
      {:ok, %Tesla.Env{status: 200}} ->
        {:ok, :valid}

      {:ok, %Tesla.Env{status: 401, body: body}} ->
        {:error, parse_error(body, "Invalid API key")}

      {:ok, %Tesla.Env{status: status, body: body}} ->
        {:error, parse_error(body, "HTTP #{status}")}

      {:error, reason} ->
        {:error, "Connection error: #{inspect(reason)}"}
    end
  end

  # Ollama verification - check if server is running (no auth needed)
  defp verify_ollama(base_url) do
    url = "#{base_url}/api/tags"

    case Tesla.get(client(), url) do
      {:ok, %Tesla.Env{status: 200}} ->
        {:ok, :valid}

      {:ok, %Tesla.Env{status: status}} ->
        {:error, "Ollama server returned HTTP #{status}"}

      {:error, _reason} ->
        {:error, "Cannot connect to Ollama at #{base_url}"}
    end
  end

  defp client do
    Tesla.client([
      {Tesla.Middleware.Timeout, timeout: 10_000},
      Tesla.Middleware.JSON
    ])
  end

  defp parse_error(body, default) when is_map(body) do
    cond do
      is_map(body["error"]) and is_binary(body["error"]["message"]) ->
        body["error"]["message"]

      is_binary(body["error"]) ->
        body["error"]

      is_binary(body["message"]) ->
        body["message"]

      true ->
        default
    end
  end

  defp parse_error(body, default) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> parse_error(decoded, default)
      _ -> default
    end
  end

  defp parse_error(_, default), do: default
end
