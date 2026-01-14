defmodule MtgDeckBuilder.AI.ProviderAdapter do
  @moduledoc """
  Behaviour for AI provider adapters.

  Each provider (Anthropic, OpenAI, xAI) implements this behaviour to handle
  provider-specific request formatting and response parsing. This abstraction
  allows the system to support multiple AI providers with different API conventions.

  ## Provider Differences

  - **Anthropic (Claude)**: System prompt as separate `system` parameter
  - **OpenAI (GPT)**: System prompt as first message with role "system"
  - **xAI (Grok)**: OpenAI-compatible format

  ## Usage

      # Get the adapter for a provider
      adapter = ProviderAdapter.get_adapter("anthropic")

      # Format a request
      request = adapter.format_request(system_prompt, messages, options)

      # Parse a response
      {:ok, content} = adapter.parse_response(response)
  """

  @type message :: %{role: String.t(), content: String.t()}
  @type options :: %{
          :model => String.t(),
          :max_tokens => non_neg_integer(),
          :temperature => float(),
          optional(:stream) => boolean()
        }
  @type request_body :: map()
  @type response :: map()

  @doc """
  Formats a request for the provider's API.

  Takes a system prompt, list of messages, and options (model, max_tokens, etc.)
  and returns a request body map ready to be sent to the provider's API.
  """
  @callback format_request(
              system_prompt :: String.t(),
              messages :: [message()],
              options :: options()
            ) :: request_body()

  @doc """
  Parses a response from the provider's API.

  Returns {:ok, content} on success or {:error, reason} on failure.
  """
  @callback parse_response(response :: response()) ::
              {:ok, String.t()} | {:error, term()}

  @doc """
  Returns whether this provider supports streaming responses.
  """
  @callback supports_streaming?() :: boolean()

  @doc """
  Returns the base URL for this provider's API.
  """
  @callback base_url() :: String.t()

  @doc """
  Returns the name of the authorization header for this provider.
  """
  @callback auth_header() :: String.t()

  @doc """
  Formats the API key for use in the authorization header.
  """
  @callback format_auth(api_key :: String.t()) :: String.t()

  # Helper functions

  @doc """
  Gets the adapter module for a given provider name.
  """
  @spec get_adapter(String.t()) :: module() | nil
  def get_adapter("anthropic"), do: MtgDeckBuilder.AI.Adapters.Anthropic
  def get_adapter("openai"), do: MtgDeckBuilder.AI.Adapters.OpenAI
  def get_adapter("xai"), do: MtgDeckBuilder.AI.Adapters.XAI
  def get_adapter(_), do: nil

  @doc """
  Gets the adapter module for a given provider name.
  Raises if provider is not supported.
  """
  @spec get_adapter!(String.t()) :: module()
  def get_adapter!(provider) do
    case get_adapter(provider) do
      nil -> raise "Unsupported provider: #{provider}"
      adapter -> adapter
    end
  end

  @doc """
  Lists all supported providers.
  """
  @spec supported_providers() :: [String.t()]
  def supported_providers do
    ["anthropic", "openai", "xai"]
  end
end
