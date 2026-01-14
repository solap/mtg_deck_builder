defmodule MtgDeckBuilder.AI.ModelRegistry do
  @moduledoc """
  Registry of AI model capabilities and configurations.

  Each model has metadata about:
  - Context window size
  - Max output tokens
  - System message format
  - Structured output support
  - Pricing information

  ## System Message Formats

  - `:top_level` - System prompt as separate API parameter (Anthropic)
  - `:first_message` - System prompt as first message with role "system" (OpenAI/xAI)

  ## Structured Output Support

  - `:json_schema` - Full JSON schema enforcement (OpenAI Structured Outputs)
  - `:tool_use` - Via tool/function definitions (Anthropic, OpenAI)
  - `:json_mode` - Basic JSON mode without schema (legacy)
  - `:none` - No structured output support
  """

  @type system_format :: :top_level | :first_message
  @type structured_output :: :json_schema | :tool_use | :json_mode | :none

  @type model_config :: %{
          id: String.t(),
          name: String.t(),
          provider: String.t(),
          context_window: pos_integer(),
          max_output_tokens: pos_integer(),
          system_format: system_format(),
          structured_output: structured_output(),
          supports_vision: boolean(),
          supports_tools: boolean(),
          cost_per_1k_input: float(),
          cost_per_1k_output: float(),
          released: String.t() | nil,
          notes: String.t() | nil
        }

  # Anthropic Claude Models
  # System: top-level parameter
  # Structured output: via tool use
  # Docs: https://docs.anthropic.com/claude/reference/messages

  @anthropic_models [
    %{
      id: "claude-opus-4-5-20250514",
      name: "Claude Opus 4.5",
      provider: "anthropic",
      context_window: 200_000,
      max_output_tokens: 64_000,
      system_format: :top_level,
      structured_output: :tool_use,
      supports_vision: true,
      supports_tools: true,
      cost_per_1k_input: 0.015,
      cost_per_1k_output: 0.075,
      released: "2025-05",
      notes: "Flagship model, hybrid reasoning, effort parameter support"
    },
    %{
      id: "claude-sonnet-4-5-20250514",
      name: "Claude Sonnet 4.5",
      provider: "anthropic",
      context_window: 200_000,
      max_output_tokens: 64_000,
      system_format: :top_level,
      structured_output: :tool_use,
      supports_vision: true,
      supports_tools: true,
      cost_per_1k_input: 0.003,
      cost_per_1k_output: 0.015,
      released: "2025-09",
      notes: "Best for coding and agents, 1M context beta available"
    },
    %{
      id: "claude-sonnet-4-20250514",
      name: "Claude Sonnet 4",
      provider: "anthropic",
      context_window: 200_000,
      max_output_tokens: 64_000,
      system_format: :top_level,
      structured_output: :tool_use,
      supports_vision: true,
      supports_tools: true,
      cost_per_1k_input: 0.003,
      cost_per_1k_output: 0.015,
      released: "2025-05",
      notes: "Balanced performance, 1M context beta available"
    },
    %{
      id: "claude-haiku-4-5-20250514",
      name: "Claude Haiku 4.5",
      provider: "anthropic",
      context_window: 200_000,
      max_output_tokens: 64_000,
      system_format: :top_level,
      structured_output: :tool_use,
      supports_vision: true,
      supports_tools: true,
      cost_per_1k_input: 0.001,
      cost_per_1k_output: 0.005,
      released: "2025-10",
      notes: "Fast and cheap, extended thinking support"
    },
    %{
      id: "claude-3-5-sonnet-20241022",
      name: "Claude 3.5 Sonnet",
      provider: "anthropic",
      context_window: 200_000,
      max_output_tokens: 8_192,
      system_format: :top_level,
      structured_output: :tool_use,
      supports_vision: true,
      supports_tools: true,
      cost_per_1k_input: 0.003,
      cost_per_1k_output: 0.015,
      released: "2024-10",
      notes: "Previous generation, still excellent"
    },
    %{
      id: "claude-3-5-haiku-20241022",
      name: "Claude 3.5 Haiku",
      provider: "anthropic",
      context_window: 200_000,
      max_output_tokens: 8_192,
      system_format: :top_level,
      structured_output: :tool_use,
      supports_vision: true,
      supports_tools: true,
      cost_per_1k_input: 0.0008,
      cost_per_1k_output: 0.004,
      released: "2024-10",
      notes: "Fast and very cheap"
    },
    %{
      id: "claude-3-haiku-20240307",
      name: "Claude 3 Haiku",
      provider: "anthropic",
      context_window: 200_000,
      max_output_tokens: 4_096,
      system_format: :top_level,
      structured_output: :tool_use,
      supports_vision: true,
      supports_tools: true,
      cost_per_1k_input: 0.00025,
      cost_per_1k_output: 0.00125,
      released: "2024-03",
      notes: "Cheapest option, good for simple tasks"
    }
  ]

  # OpenAI Models
  # System: first message with role "system"
  # Structured output: json_schema (GPT-4o+) or json_mode (older)
  # Docs: https://platform.openai.com/docs/models

  @openai_models [
    %{
      id: "gpt-4.1",
      name: "GPT-4.1",
      provider: "openai",
      context_window: 1_000_000,
      max_output_tokens: 32_768,
      system_format: :first_message,
      structured_output: :json_schema,
      supports_vision: true,
      supports_tools: true,
      cost_per_1k_input: 0.002,
      cost_per_1k_output: 0.008,
      released: "2025",
      notes: "Latest flagship, 1M context window"
    },
    %{
      id: "gpt-4.1-mini",
      name: "GPT-4.1 Mini",
      provider: "openai",
      context_window: 1_000_000,
      max_output_tokens: 32_768,
      system_format: :first_message,
      structured_output: :json_schema,
      supports_vision: true,
      supports_tools: true,
      cost_per_1k_input: 0.0004,
      cost_per_1k_output: 0.0016,
      released: "2025",
      notes: "Balanced cost/performance, 1M context"
    },
    %{
      id: "gpt-4.1-nano",
      name: "GPT-4.1 Nano",
      provider: "openai",
      context_window: 1_000_000,
      max_output_tokens: 32_768,
      system_format: :first_message,
      structured_output: :json_schema,
      supports_vision: false,
      supports_tools: true,
      cost_per_1k_input: 0.0001,
      cost_per_1k_output: 0.0004,
      released: "2025",
      notes: "Cheapest GPT-4.1, text only"
    },
    %{
      id: "gpt-4o",
      name: "GPT-4o",
      provider: "openai",
      context_window: 128_000,
      max_output_tokens: 16_384,
      system_format: :first_message,
      structured_output: :json_schema,
      supports_vision: true,
      supports_tools: true,
      cost_per_1k_input: 0.0025,
      cost_per_1k_output: 0.01,
      released: "2024-05",
      notes: "Previous flagship, vision + audio"
    },
    %{
      id: "gpt-4o-mini",
      name: "GPT-4o Mini",
      provider: "openai",
      context_window: 128_000,
      max_output_tokens: 16_384,
      system_format: :first_message,
      structured_output: :json_schema,
      supports_vision: true,
      supports_tools: true,
      cost_per_1k_input: 0.00015,
      cost_per_1k_output: 0.0006,
      released: "2024-07",
      notes: "Great value, recommended for most use cases"
    },
    %{
      id: "gpt-4-turbo",
      name: "GPT-4 Turbo",
      provider: "openai",
      context_window: 128_000,
      max_output_tokens: 4_096,
      system_format: :first_message,
      structured_output: :json_mode,
      supports_vision: true,
      supports_tools: true,
      cost_per_1k_input: 0.01,
      cost_per_1k_output: 0.03,
      released: "2024",
      notes: "Legacy, use GPT-4o instead"
    }
  ]

  # xAI Grok Models
  # System: first message (OpenAI-compatible)
  # Structured output: json_schema (OpenAI-compatible)
  # Docs: https://docs.x.ai/docs/overview

  @xai_models [
    %{
      id: "grok-3",
      name: "Grok 3",
      provider: "xai",
      context_window: 131_072,
      max_output_tokens: 16_384,
      system_format: :first_message,
      structured_output: :json_schema,
      supports_vision: true,
      supports_tools: true,
      cost_per_1k_input: 0.003,
      cost_per_1k_output: 0.015,
      released: "2025",
      notes: "Latest Grok, strong reasoning"
    },
    %{
      id: "grok-3-mini",
      name: "Grok 3 Mini",
      provider: "xai",
      context_window: 131_072,
      max_output_tokens: 16_384,
      system_format: :first_message,
      structured_output: :json_schema,
      supports_vision: false,
      supports_tools: true,
      cost_per_1k_input: 0.0003,
      cost_per_1k_output: 0.0005,
      released: "2025",
      notes: "Fast thinking mode"
    },
    %{
      id: "grok-2-latest",
      name: "Grok 2",
      provider: "xai",
      context_window: 131_072,
      max_output_tokens: 8_192,
      system_format: :first_message,
      structured_output: :json_schema,
      supports_vision: true,
      supports_tools: true,
      cost_per_1k_input: 0.002,
      cost_per_1k_output: 0.01,
      released: "2024",
      notes: "Stable release"
    },
    %{
      id: "grok-2-mini",
      name: "Grok 2 Mini",
      provider: "xai",
      context_window: 131_072,
      max_output_tokens: 8_192,
      system_format: :first_message,
      structured_output: :json_schema,
      supports_vision: false,
      supports_tools: true,
      cost_per_1k_input: 0.0002,
      cost_per_1k_output: 0.001,
      released: "2024",
      notes: "Budget option"
    }
  ]

  @all_models @anthropic_models ++ @openai_models ++ @xai_models

  @doc """
  Returns all registered models.
  """
  @spec list_models() :: [model_config()]
  def list_models, do: @all_models

  @doc """
  Returns models for a specific provider.
  """
  @spec list_models(String.t()) :: [model_config()]
  def list_models(provider) when is_binary(provider) do
    Enum.filter(@all_models, &(&1.provider == provider))
  end

  @doc """
  Gets a specific model by ID.
  """
  @spec get_model(String.t()) :: model_config() | nil
  def get_model(model_id) when is_binary(model_id) do
    Enum.find(@all_models, &(&1.id == model_id))
  end

  @doc """
  Gets the system message format for a model.
  Returns :top_level for Anthropic, :first_message for OpenAI/xAI.
  """
  @spec get_system_format(String.t()) :: system_format() | nil
  def get_system_format(model_id) do
    case get_model(model_id) do
      nil -> nil
      model -> model.system_format
    end
  end

  @doc """
  Gets the system message format for a provider.
  """
  @spec get_provider_system_format(String.t()) :: system_format()
  def get_provider_system_format("anthropic"), do: :top_level
  def get_provider_system_format(_), do: :first_message

  @doc """
  Checks if a model supports structured output.
  """
  @spec supports_structured_output?(String.t()) :: boolean()
  def supports_structured_output?(model_id) do
    case get_model(model_id) do
      nil -> false
      model -> model.structured_output != :none
    end
  end

  @doc """
  Gets the structured output type for a model.
  """
  @spec get_structured_output_type(String.t()) :: structured_output() | nil
  def get_structured_output_type(model_id) do
    case get_model(model_id) do
      nil -> nil
      model -> model.structured_output
    end
  end

  @doc """
  Checks if a model supports tools/function calling.
  """
  @spec supports_tools?(String.t()) :: boolean()
  def supports_tools?(model_id) do
    case get_model(model_id) do
      nil -> false
      model -> model.supports_tools
    end
  end

  @doc """
  Gets context window size for a model.
  """
  @spec get_context_window(String.t()) :: pos_integer() | nil
  def get_context_window(model_id) do
    case get_model(model_id) do
      nil -> nil
      model -> model.context_window
    end
  end

  @doc """
  Gets max output tokens for a model.
  """
  @spec get_max_output_tokens(String.t()) :: pos_integer() | nil
  def get_max_output_tokens(model_id) do
    case get_model(model_id) do
      nil -> nil
      model -> model.max_output_tokens
    end
  end

  @doc """
  Returns models grouped by provider for UI dropdowns.
  """
  @spec models_by_provider() :: %{String.t() => [model_config()]}
  def models_by_provider do
    @all_models
    |> Enum.group_by(& &1.provider)
    |> Enum.into(%{})
  end

  @doc """
  Returns a list of provider names with available models.
  """
  @spec providers() :: [String.t()]
  def providers do
    ["anthropic", "openai", "xai"]
  end

  @doc """
  Returns display name for a provider.
  """
  @spec provider_name(String.t()) :: String.t()
  def provider_name("anthropic"), do: "Anthropic Claude"
  def provider_name("openai"), do: "OpenAI"
  def provider_name("xai"), do: "xAI Grok"
  def provider_name(other), do: other
end
