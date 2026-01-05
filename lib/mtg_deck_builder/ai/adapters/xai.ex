defmodule MtgDeckBuilder.AI.Adapters.XAI do
  @moduledoc """
  Provider adapter for xAI's Grok API.

  xAI's API is OpenAI-compatible, using the same request/response format.
  The system prompt is included as the first message with role "system".

  ## Request Format

      %{
        model: "grok-2-latest",
        max_tokens: 1024,
        messages: [
          %{role: "system", content: "You are a helpful assistant."},
          %{role: "user", content: "Hello!"}
        ]
      }

  ## Response Format

      %{
        "choices" => [
          %{
            "message" => %{"content" => "Hello! How can I help?", "role" => "assistant"},
            "finish_reason" => "stop"
          }
        ],
        "model" => "grok-2-latest",
        "usage" => %{"prompt_tokens" => 10, "completion_tokens" => 8}
      }
  """

  @behaviour MtgDeckBuilder.AI.ProviderAdapter

  @base_url "https://api.x.ai/v1"

  @impl true
  def format_request(system_prompt, messages, options) do
    system_message = %{role: "system", content: system_prompt}
    formatted_messages = [system_message | format_messages(messages)]

    %{
      model: options[:model] || "grok-2-latest",
      max_tokens: options[:max_tokens] || 1024,
      messages: formatted_messages
    }
    |> maybe_add_temperature(options[:temperature])
    |> maybe_add_stream(options[:stream])
  end

  @impl true
  def parse_response(%{"choices" => [%{"message" => %{"content" => content}} | _]}) do
    {:ok, content}
  end

  def parse_response(%{"error" => %{"message" => message}}) do
    {:error, message}
  end

  def parse_response(response) do
    {:error, "Unexpected response format: #{inspect(response)}"}
  end

  @impl true
  def supports_streaming?, do: true

  @impl true
  def base_url, do: @base_url

  @impl true
  def auth_header, do: "authorization"

  @impl true
  def format_auth(api_key), do: "Bearer #{api_key}"

  # Private functions

  defp format_messages(messages) do
    Enum.map(messages, fn msg ->
      %{
        role: msg[:role] || msg["role"],
        content: msg[:content] || msg["content"]
      }
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
end
