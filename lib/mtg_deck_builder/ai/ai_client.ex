defmodule MtgDeckBuilder.AI.AIClient do
  @moduledoc """
  Unified AI client that abstracts provider-specific API calls.

  This module provides a single interface for making AI API calls,
  automatically selecting the appropriate provider adapter based on
  the agent configuration.

  ## Usage

      # Using an agent config
      config = AgentRegistry.get_agent!("orchestrator")
      {:ok, response} = AIClient.chat(config, messages)

      # With custom system prompt
      {:ok, response} = AIClient.chat(config, messages, system_prompt: "Custom prompt")

      # With tools (for orchestrator routing)
      {:ok, response} = AIClient.chat_with_tools(config, messages, tools, tool_executor)
  """

  alias MtgDeckBuilder.AI.{AgentConfig, AgentRegistry, ProviderAdapter}
  alias MtgDeckBuilder.AI.Adapters.Anthropic, as: AnthropicAdapter

  require Logger

  @type message :: %{role: String.t(), content: String.t() | list()}
  @type tool_call :: %{id: String.t(), name: String.t(), input: map()}
  @type chat_options :: [
          system_prompt: String.t(),
          max_tokens: non_neg_integer(),
          temperature: float(),
          tools: list()
        ]

  # Maximum tool call iterations to prevent infinite loops
  # Deck building needs: set_brew_settings + experts + multiple recommend_cards batches
  @max_tool_iterations 10

  @doc """
  Makes a chat request using the specified agent configuration.

  The agent config determines which provider and model to use,
  as well as default values for max_tokens, temperature, etc.

  ## Options

  - `:system_prompt` - Override the agent's system prompt
  - `:max_tokens` - Override max tokens (default from agent config)
  - `:temperature` - Override temperature (default from agent config)

  ## Examples

      config = AgentRegistry.get_agent!("orchestrator")
      messages = [%{role: "user", content: "Hello!"}]
      {:ok, response} = AIClient.chat(config, messages)
  """
  @spec chat(AgentConfig.t(), [message()], chat_options()) ::
          {:ok, String.t()} | {:error, term()}
  def chat(%AgentConfig{} = config, messages, opts \\ []) do
    with {:ok, adapter} <- get_adapter_safe(config.provider),
         {:ok, api_key} <- get_api_key_safe(config.provider) do
      system_prompt = opts[:system_prompt] || config.system_prompt

      request_opts = %{
        model: config.model,
        max_tokens: opts[:max_tokens] || config.max_tokens,
        temperature: opts[:temperature] || config.temperature
      }

      request_body = adapter.format_request(system_prompt, messages, request_opts)
      endpoint = get_chat_endpoint(adapter)

      Logger.debug("AIClient.chat: #{config.provider}/#{config.model}")

      case make_request(adapter, endpoint, api_key, request_body) do
        {:ok, response} ->
          adapter.parse_response(response)

        {:error, _} = error ->
          error
      end
    end
  end

  @doc """
  Makes a chat request using an agent_id string.

  Looks up the agent config and delegates to `chat/3`.
  """
  @spec chat_with_agent(String.t(), [message()], chat_options()) ::
          {:ok, String.t()} | {:error, term()}
  def chat_with_agent(agent_id, messages, opts \\ []) when is_binary(agent_id) do
    case AgentRegistry.get_agent(agent_id) do
      nil ->
        {:error, "Agent not found: #{agent_id}"}

      config ->
        if config.enabled do
          chat(config, messages, opts)
        else
          {:error, "Agent is disabled: #{agent_id}"}
        end
    end
  end

  @doc """
  Makes a chat request with tool support, handling the tool-call loop.

  When the model decides to use tools, this function:
  1. Receives the tool calls from the model
  2. Executes them via the provided `tool_executor` function
  3. Sends results back to the model
  4. Repeats until the model produces a final text response

  ## Parameters

  - `config` - The agent configuration
  - `messages` - Initial conversation messages
  - `tools` - List of tool definitions (Anthropic format)
  - `tool_executor` - Function that takes (tool_name, input) and returns result string
  - `opts` - Additional options (same as chat/3)

  ## Example

      tools = ExpertTools.tool_definitions()
      executor = fn name, input -> ExpertConsultant.consult(name, input, context) end
      {:ok, response} = AIClient.chat_with_tools(config, messages, tools, executor)
  """
  @spec chat_with_tools(AgentConfig.t(), [message()], list(), function(), chat_options()) ::
          {:ok, String.t()} | {:error, term()}
  def chat_with_tools(%AgentConfig{} = config, messages, tools, tool_executor, opts \\ []) do
    with {:ok, adapter} <- get_adapter_safe(config.provider),
         {:ok, api_key} <- get_api_key_safe(config.provider) do
      do_chat_with_tools(config, adapter, api_key, messages, tools, tool_executor, opts, 0)
    end
  end

  defp do_chat_with_tools(_config, _adapter, _api_key, _messages, _tools, _executor, _opts, iteration)
       when iteration >= @max_tool_iterations do
    {:error, "Maximum tool iterations (#{@max_tool_iterations}) exceeded"}
  end

  defp do_chat_with_tools(config, adapter, api_key, messages, tools, tool_executor, opts, iteration) do
    system_prompt = opts[:system_prompt] || config.system_prompt

    request_opts = %{
      model: config.model,
      max_tokens: opts[:max_tokens] || config.max_tokens,
      temperature: opts[:temperature] || config.temperature,
      tools: tools
    }

    request_body = adapter.format_request(system_prompt, messages, request_opts)
    endpoint = get_chat_endpoint(adapter)

    Logger.debug("AIClient.chat_with_tools: iteration #{iteration}, #{config.provider}/#{config.model}")

    case make_request(adapter, endpoint, api_key, request_body) do
      {:ok, response} ->
        case adapter.parse_response(response) do
          {:ok, text} ->
            # Final text response - we're done
            {:ok, text}

          {:tool_use, %{tool_calls: tool_calls, raw_content: raw_content}} ->
            # Model wants to use tools - execute them and continue
            Logger.debug("AIClient: #{length(tool_calls)} tool call(s) requested")

            # Execute all tool calls (could be parallelized)
            tool_results =
              Enum.map(tool_calls, fn %{id: id, name: name, input: input} ->
                Logger.debug("AIClient: Executing tool #{name}")
                result = tool_executor.(name, input)
                AnthropicAdapter.format_tool_result(id, result)
              end)

            # Build updated message history
            assistant_msg = AnthropicAdapter.format_assistant_tool_use(raw_content)
            user_tool_results = AnthropicAdapter.format_user_tool_results(tool_results)
            updated_messages = messages ++ [assistant_msg, user_tool_results]

            # Continue the conversation
            do_chat_with_tools(config, adapter, api_key, updated_messages, tools, tool_executor, opts, iteration + 1)

          {:error, _} = error ->
            error
        end

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Gets the adapter module for a provider.
  Returns nil if provider is not supported.
  """
  @spec get_adapter(String.t()) :: module() | nil
  def get_adapter(provider) do
    ProviderAdapter.get_adapter(provider)
  end

  @doc """
  Gets the adapter module for a provider.
  Raises if provider is not supported.
  """
  @spec get_adapter!(String.t()) :: module()
  def get_adapter!(provider) do
    ProviderAdapter.get_adapter!(provider)
  end

  # Private functions

  defp get_api_key_safe(provider) do
    case AgentRegistry.get_provider_api_key(provider) do
      nil -> {:error, "API key not configured for provider: #{provider}"}
      key -> {:ok, key}
    end
  end

  defp get_adapter_safe(provider) do
    case ProviderAdapter.get_adapter(provider) do
      nil -> {:error, "Unsupported provider: #{provider}"}
      adapter -> {:ok, adapter}
    end
  end

  defp get_chat_endpoint(adapter) do
    base_url = adapter.base_url()

    case adapter do
      AnthropicAdapter -> "#{base_url}/messages"
      _ -> "#{base_url}/chat/completions"
    end
  end

  defp make_request(adapter, endpoint, api_key, body) do
    headers = build_headers(adapter, api_key)

    case Tesla.post(client(), endpoint, body, headers: headers) do
      {:ok, %Tesla.Env{status: status, body: response_body}} when status in 200..299 ->
        {:ok, response_body}

      {:ok, %Tesla.Env{status: status, body: response_body}} ->
        Logger.error("AI API error: #{status} - #{inspect(response_body)}")
        {:error, "API error: #{status}"}

      {:error, reason} ->
        Logger.error("AI API request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp build_headers(adapter, api_key) do
    base_headers = [
      {adapter.auth_header(), adapter.format_auth(api_key)},
      {"content-type", "application/json"}
    ]

    # Add extra headers if adapter defines them (e.g., Anthropic's version header)
    if function_exported?(adapter, :extra_headers, 0) do
      base_headers ++ adapter.extra_headers()
    else
      base_headers
    end
  end

  defp client do
    Tesla.client([
      {Tesla.Middleware.JSON, []}
    ])
  end
end
