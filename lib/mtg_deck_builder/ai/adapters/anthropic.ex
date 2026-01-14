defmodule MtgDeckBuilder.AI.Adapters.Anthropic do
  @moduledoc """
  Provider adapter for Anthropic's Claude API.

  Anthropic's API uses a separate `system` parameter for the system prompt,
  rather than including it as a message. This is the preferred format for
  Claude models.

  ## Request Format

      %{
        model: "claude-sonnet-4-20250514",
        max_tokens: 1024,
        system: "You are a helpful assistant.",
        messages: [
          %{role: "user", content: "Hello!"}
        ]
      }

  ## Response Format

      %{
        "content" => [%{"text" => "Hello! How can I help?", "type" => "text"}],
        "model" => "claude-sonnet-4-20250514",
        "usage" => %{"input_tokens" => 10, "output_tokens" => 8}
      }

  ## Tool Use

  When tools are provided, the response may contain tool_use blocks:

      %{
        "content" => [
          %{"type" => "tool_use", "id" => "toolu_xxx", "name" => "tool_name", "input" => %{...}}
        ],
        "stop_reason" => "tool_use"
      }
  """

  @behaviour MtgDeckBuilder.AI.ProviderAdapter

  @base_url "https://api.anthropic.com/v1"
  @api_version "2023-06-01"

  @impl true
  def format_request(system_prompt, messages, options) do
    %{
      model: options[:model] || "claude-sonnet-4-20250514",
      max_tokens: options[:max_tokens] || 1024,
      system: system_prompt,
      messages: format_messages(messages)
    }
    |> maybe_add_temperature(options[:temperature])
    |> maybe_add_stream(options[:stream])
    |> maybe_add_tools(options[:tools])
  end

  @impl true
  def parse_response(%{"content" => content, "stop_reason" => "tool_use"} = response) when is_list(content) do
    # Extract tool calls from the response
    tool_calls =
      content
      |> Enum.filter(&(&1["type"] == "tool_use"))
      |> Enum.map(fn tool ->
        %{
          id: tool["id"],
          name: tool["name"],
          input: tool["input"]
        }
      end)

    # Also extract any text that came before tool calls
    text =
      content
      |> Enum.filter(&(&1["type"] == "text"))
      |> Enum.map(& &1["text"])
      |> Enum.join("")

    {:tool_use, %{tool_calls: tool_calls, text: text, raw_content: content, usage: response["usage"]}}
  end

  def parse_response(%{"content" => content}) when is_list(content) do
    text =
      content
      |> Enum.filter(&(&1["type"] == "text"))
      |> Enum.map(& &1["text"])
      |> Enum.join("")

    {:ok, text}
  end

  def parse_response(%{"error" => %{"message" => message}}) do
    {:error, message}
  end

  def parse_response(response) do
    {:error, "Unexpected response format: #{inspect(response)}"}
  end

  @doc """
  Formats a tool result message for sending back to the API.
  """
  @spec format_tool_result(String.t(), String.t()) :: map()
  def format_tool_result(tool_use_id, result) do
    %{
      type: "tool_result",
      tool_use_id: tool_use_id,
      content: result
    }
  end

  @doc """
  Formats an assistant message containing tool use for conversation history.
  """
  @spec format_assistant_tool_use(list()) :: map()
  def format_assistant_tool_use(raw_content) do
    %{
      role: "assistant",
      content: raw_content
    }
  end

  @doc """
  Formats a user message containing tool results for conversation history.
  """
  @spec format_user_tool_results(list()) :: map()
  def format_user_tool_results(tool_results) do
    %{
      role: "user",
      content: tool_results
    }
  end

  @impl true
  def supports_streaming?, do: true

  @impl true
  def base_url, do: @base_url

  @impl true
  def auth_header, do: "x-api-key"

  @impl true
  def format_auth(api_key), do: api_key

  @doc """
  Returns the API version header value.
  """
  def api_version, do: @api_version

  @doc """
  Returns additional headers required for Anthropic API.
  """
  def extra_headers do
    [{"anthropic-version", @api_version}]
  end

  # Private functions

  defp format_messages(messages) do
    Enum.map(messages, fn msg ->
      role = msg[:role] || msg["role"]
      content = msg[:content] || msg["content"]

      # Content can be a string or a list (for tool results/tool use)
      %{role: role, content: content}
    end)
  end

  defp maybe_add_temperature(request, nil), do: request
  defp maybe_add_temperature(request, temp) when is_number(temp) do
    Map.put(request, :temperature, temp)
  end
  defp maybe_add_temperature(request, %Decimal{} = temp) do
    Map.put(request, :temperature, Decimal.to_float(temp))
  end

  defp maybe_add_stream(request, true), do: Map.put(request, :stream, true)
  defp maybe_add_stream(request, _), do: request

  defp maybe_add_tools(request, nil), do: request
  defp maybe_add_tools(request, []), do: request
  defp maybe_add_tools(request, tools) when is_list(tools) do
    Map.put(request, :tools, tools)
  end
end
