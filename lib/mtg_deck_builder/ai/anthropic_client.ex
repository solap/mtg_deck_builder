defmodule MtgDeckBuilder.AI.AnthropicClient do
  @moduledoc """
  Client for the Anthropic Claude API.

  Parses natural language deck commands using Claude's tool_use feature
  to extract structured command data.
  """

  alias MtgDeckBuilder.AI.{ParsedCommand, ApiLogger}

  @anthropic_api_url "https://api.anthropic.com/v1/messages"
  @default_timeout 10_000

  @tool_schema %{
    "name" => "deck_command",
    "description" => "Parse a Magic: The Gathering deck building command. Extract the action, card name, quantity, and target board from natural language input.",
    "input_schema" => %{
      "type" => "object",
      "properties" => %{
        "action" => %{
          "type" => "string",
          "enum" => ["add", "remove", "set", "move", "query", "undo", "help"],
          "description" => "The deck operation to perform"
        },
        "card_name" => %{
          "type" => "string",
          "description" => "The name of the card (as close to user input as possible)"
        },
        "quantity" => %{
          "type" => "integer",
          "minimum" => 1,
          "maximum" => 15,
          "description" => "Number of cards (default 1 if not specified)"
        },
        "source_board" => %{
          "type" => "string",
          "enum" => ["mainboard", "sideboard"],
          "description" => "Board to take cards from (for move/remove)"
        },
        "target_board" => %{
          "type" => "string",
          "enum" => ["mainboard", "sideboard"],
          "description" => "Board to put cards in (default mainboard)"
        },
        "query_type" => %{
          "type" => "string",
          "enum" => ["count", "list", "status"],
          "description" => "Type of query for query actions"
        }
      },
      "required" => ["action"]
    }
  }

  @doc """
  Parses a natural language command using Claude API.

  ## Examples

      iex> AnthropicClient.parse_command("add 4 lightning bolt")
      {:ok, %ParsedCommand{action: :add, card_name: "lightning bolt", quantity: 4}}

      iex> AnthropicClient.parse_command("remove counterspell from sideboard")
      {:ok, %ParsedCommand{action: :remove, card_name: "counterspell", source_board: :sideboard}}

  ## Returns
    - {:ok, %ParsedCommand{}} on success
    - {:error, reason} on failure
  """
  @spec parse_command(String.t()) :: {:ok, ParsedCommand.t()} | {:error, String.t()}
  def parse_command(input) when is_binary(input) do
    start_time = System.monotonic_time(:millisecond)

    case do_api_call(input) do
      {:ok, response} ->
        latency = System.monotonic_time(:millisecond) - start_time
        handle_success_response(response, input, latency)

      {:error, reason} = error ->
        latency = System.monotonic_time(:millisecond) - start_time
        log_api_error(reason, latency)
        error
    end
  end

  defp do_api_call(input) do
    api_key = get_api_key()
    model = get_model()

    if is_nil(api_key) or api_key == "" do
      {:error, "ANTHROPIC_API_KEY not configured"}
    else
      body =
        Jason.encode!(%{
          "model" => model,
          "max_tokens" => 256,
          "tools" => [@tool_schema],
          "tool_choice" => %{"type" => "tool", "name" => "deck_command"},
          "messages" => [
            %{
              "role" => "user",
              "content" => input
            }
          ]
        })

      headers = [
        {"x-api-key", api_key},
        {"anthropic-version", "2023-06-01"},
        {"content-type", "application/json"}
      ]

      case :httpc.request(
             :post,
             {~c"#{@anthropic_api_url}", headers |> Enum.map(fn {k, v} -> {~c"#{k}", ~c"#{v}"} end), ~c"application/json", body},
             [timeout: @default_timeout, connect_timeout: 5_000],
             []
           ) do
        {:ok, {{_, status, _}, _headers, response_body}} ->
          handle_http_response(status, to_string(response_body))

        {:error, reason} ->
          {:error, "HTTP request failed: #{inspect(reason)}"}
      end
    end
  end

  defp handle_http_response(200, body) do
    case Jason.decode(body) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, _} -> {:error, "Failed to parse API response"}
    end
  end

  defp handle_http_response(400, _body), do: {:error, "Bad request - invalid command format"}
  defp handle_http_response(401, _body), do: {:error, "Invalid API key"}
  defp handle_http_response(429, _body), do: {:error, "Rate limited - please try again"}
  defp handle_http_response(500, _body), do: {:error, "Anthropic server error"}
  defp handle_http_response(529, _body), do: {:error, "API overloaded - please try again"}
  defp handle_http_response(status, _body), do: {:error, "Unexpected status: #{status}"}

  defp handle_success_response(response, raw_input, latency) do
    usage = response["usage"] || %{}
    input_tokens = usage["input_tokens"] || 0
    output_tokens = usage["output_tokens"] || 0

    # Log successful request
    ApiLogger.log_request(%{
      provider: "anthropic",
      model: get_model(),
      endpoint: "/v1/messages",
      input_tokens: input_tokens,
      output_tokens: output_tokens,
      latency_ms: latency,
      success: true
    })

    # Extract tool_use content
    case extract_tool_input(response) do
      {:ok, tool_input} ->
        tool_input
        |> Map.put("raw_input", raw_input)
        |> ParsedCommand.from_map()

      {:error, _} = error ->
        error
    end
  end

  defp extract_tool_input(%{"content" => content}) when is_list(content) do
    case Enum.find(content, fn c -> c["type"] == "tool_use" end) do
      %{"input" => input} -> {:ok, input}
      nil -> {:error, "No tool_use in response"}
    end
  end

  defp extract_tool_input(_), do: {:error, "Invalid response format"}

  defp log_api_error(reason, latency) do
    error_type =
      cond do
        String.contains?(reason, "Rate limited") -> "rate_limit"
        String.contains?(reason, "Invalid API key") -> "auth_error"
        String.contains?(reason, "server error") -> "server_error"
        String.contains?(reason, "overloaded") -> "overloaded"
        String.contains?(reason, "not configured") -> "config_error"
        true -> "unknown"
      end

    ApiLogger.log_request(%{
      provider: "anthropic",
      model: get_model(),
      endpoint: "/v1/messages",
      input_tokens: 0,
      output_tokens: 0,
      latency_ms: latency,
      success: false,
      error_type: error_type
    })
  end

  defp get_api_key do
    # Try DB first, then fall back to environment config
    case MtgDeckBuilder.Settings.get_api_key("anthropic") do
      nil -> Application.get_env(:mtg_deck_builder, :anthropic)[:api_key]
      "" -> Application.get_env(:mtg_deck_builder, :anthropic)[:api_key]
      key -> key
    end
  end

  defp get_model do
    # Try DB first, then fall back to environment config
    case MtgDeckBuilder.Settings.get_model("anthropic") do
      nil -> Application.get_env(:mtg_deck_builder, :anthropic)[:model] || "claude-3-haiku-20240307"
      model -> model
    end
  end
end
