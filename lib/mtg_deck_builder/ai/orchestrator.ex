defmodule MtgDeckBuilder.AI.Orchestrator do
  @moduledoc """
  AI Orchestrator for Brew Mode questions.

  The orchestrator acts as a coordinator that:
  1. Receives user questions with deck context
  2. Decides which specialist experts to consult (via tools)
  3. Synthesizes expert responses into a unified answer

  ## Tool-Based Routing

  The orchestrator has access to specialist tools:
  - `consult_mana_expert` - Mana base analysis
  - `consult_synergy_expert` - Card synergies and interactions
  - `consult_card_evaluator` - Card evaluation and cuts
  - `consult_meta_expert` - Metagame and matchups
  - `consult_rules_expert` - Rules questions

  When a user asks a question, the orchestrator decides which expert(s)
  to consult, calls them, and synthesizes the responses.
  """

  alias MtgDeckBuilder.AI.{AIClient, AgentRegistry, ApiLogger, ExpertTools, ExpertConsultant}
  alias MtgDeckBuilder.Brew.{BrewContext, ContextSerializer}

  require Logger

  @type response :: %{
          content: String.t(),
          model: String.t(),
          provider: String.t(),
          experts_consulted: [String.t()]
        }

  @doc """
  Asks the orchestrator a question with the given context.

  The orchestrator will:
  1. Analyze the question
  2. Decide which experts to consult (if any)
  3. Call experts via tools
  4. Synthesize a final response

  ## Options

  - `:format` - The deck format (for legality context)
  - `:use_tools` - Whether to enable tool-based routing (default: true)

  ## Examples

      iex> context = BrewContext.build(brew, deck, "What should I add?")
      iex> {:ok, response} = Orchestrator.ask(context)
      iex> response.content
      "For your control deck..."
  """
  @spec ask(BrewContext.t(), keyword()) :: {:ok, response()} | {:error, term()}
  def ask(%BrewContext{} = context, opts \\ []) do
    start_time = System.monotonic_time(:millisecond)
    use_tools = Keyword.get(opts, :use_tools, true)

    case AgentRegistry.get_agent("orchestrator") do
      nil ->
        {:error, "Orchestrator agent not configured"}

      config ->
        if config.enabled do
          if use_tools do
            do_ask_with_tools(context, config, opts, start_time)
          else
            do_ask_simple(context, config, opts, start_time)
          end
        else
          {:error, "Orchestrator agent is disabled"}
        end
    end
  end

  # Tool-based routing: orchestrator decides which experts to consult
  defp do_ask_with_tools(context, config, _opts, start_time) do
    # Build the prompt from context
    prompt = ContextSerializer.to_prompt(context)

    # Build messages for the AI, including chat history if available
    messages = build_messages_with_history(context.chat_history, prompt)

    # Get the expert tools
    tools = ExpertTools.tool_definitions()

    # Initialize tracking
    Process.put(:experts_consulted, [])
    Process.put(:recommended_cards, %{mainboard: [], sideboard: [], staging: []})
    Process.put(:brew_settings, nil)

    # Create a tool executor that handles expert consultations and action tools
    tool_executor = fn tool_name, input ->
      if ExpertTools.is_action_tool?(tool_name) do
        # Handle action tools (recommend_cards, set_brew_settings)
        handle_action_tool(tool_name, input, context)
      else
        # Track the expert
        agent_id = ExpertTools.tool_to_agent_id(tool_name)
        Process.put(:experts_consulted, [agent_id | Process.get(:experts_consulted, [])])

        # Consult the expert
        ExpertConsultant.consult(tool_name, input, context)
      end
    end

    Logger.debug("Orchestrator.ask_with_tools: Using #{config.provider}/#{config.model}")

    case AIClient.chat_with_tools(config, messages, tools, tool_executor) do
      {:ok, content} ->
        latency = System.monotonic_time(:millisecond) - start_time
        consulted = Process.get(:experts_consulted, []) |> Enum.reverse() |> Enum.uniq()
        recommended = Process.get(:recommended_cards, %{mainboard: [], sideboard: [], staging: []})
        brew_settings = Process.get(:brew_settings)

        # Log the request
        log_request(config, latency, true, nil, consulted)

        if length(consulted) > 0 do
          Logger.info("Orchestrator consulted #{length(consulted)} expert(s): #{Enum.join(consulted, ", ")}")
        end

        total_cards = length(recommended.mainboard) + length(recommended.sideboard) + length(recommended.staging)
        if total_cards > 0 do
          Logger.info("Orchestrator recommended #{total_cards} card(s): #{length(recommended.mainboard)} mainboard, #{length(recommended.sideboard)} sideboard, #{length(recommended.staging)} staging")
        end

        response = %{
          content: content,
          model: config.model,
          provider: config.provider,
          experts_consulted: consulted,
          recommended_cards: recommended,
          brew_settings: brew_settings
        }

        {:ok, response}

      {:error, reason} = error ->
        latency = System.monotonic_time(:millisecond) - start_time
        log_request(config, latency, false, reason)
        Logger.error("Orchestrator.ask_with_tools failed: #{inspect(reason)}")
        error
    end
  end

  # Handle action tools (recommend_cards, set_brew_settings)
  defp handle_action_tool("recommend_cards", input, context) do
    cards = input["cards"] || []
    board = input["board"] || "staging"
    format = context.format

    # Validate board
    board_atom = case board do
      "mainboard" -> :mainboard
      "sideboard" -> :sideboard
      _ -> :staging
    end

    # Look up cards in the database and validate them
    validated_cards = validate_and_lookup_cards(cards, format)

    # Track the validated recommendations by board
    current = Process.get(:recommended_cards, %{mainboard: [], sideboard: [], staging: []})
    updated = Map.update!(current, board_atom, fn existing -> validated_cards ++ existing end)
    Process.put(:recommended_cards, updated)

    # Return a confirmation message to the AI
    if length(validated_cards) > 0 do
      card_names = Enum.map(validated_cards, & &1.name) |> Enum.join(", ")
      "Added #{length(validated_cards)} card(s) to #{board}: #{card_names}"
    else
      "No valid cards found to recommend."
    end
  end

  defp handle_action_tool("set_brew_settings", input, _context) do
    archetype = input["archetype"]
    colors = input["colors"] || []

    settings = %{archetype: archetype, colors: colors}
    Process.put(:brew_settings, settings)

    parts = []
    parts = if archetype, do: ["archetype: #{archetype}" | parts], else: parts
    parts = if length(colors) > 0, do: ["colors: #{Enum.join(colors, ", ")}" | parts], else: parts

    if length(parts) > 0 do
      "Updated brew settings: #{Enum.join(parts, ", ")}"
    else
      "No brew settings to update."
    end
  end

  defp handle_action_tool(unknown, _input, _context) do
    "Unknown action: #{unknown}"
  end

  # Validate card names against the database and return full card data
  defp validate_and_lookup_cards(cards, format) do
    alias MtgDeckBuilder.Cards

    cards
    |> Enum.map(fn card_input ->
      name = card_input["name"]
      quantity = card_input["quantity"] || 1
      reason = card_input["reason"]

      # Look up the card by name (fuzzy match)
      case Cards.search(name, limit: 1) do
        [found_card | _] ->
          # Check format legality if format specified
          legal = is_nil(format) || check_legality(found_card, format)

          if legal do
            %{
              name: found_card.name,
              scryfall_id: found_card.scryfall_id,
              quantity: min(quantity, 4),
              reason: reason,
              mana_cost: found_card.mana_cost,
              type_line: found_card.type_line,
              cmc: found_card.cmc,
              colors: found_card.colors,
              prices: found_card.prices
            }
          else
            nil
          end

        [] ->
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp check_legality(card, format) when is_atom(format) do
    check_legality(card, Atom.to_string(format))
  end

  defp check_legality(card, format) when is_binary(format) do
    case card.legalities do
      %{^format => "legal"} -> true
      legalities when is_map(legalities) -> legalities[format] == "legal"
      _ -> true  # If no legality data, assume legal
    end
  end

  # Simple mode: no tools, orchestrator answers directly (fallback)
  defp do_ask_simple(context, config, _opts, start_time) do
    prompt = ContextSerializer.to_prompt(context)
    messages = build_messages_with_history(context.chat_history, prompt)

    Logger.debug("Orchestrator.ask_simple: Using #{config.provider}/#{config.model}")

    case AIClient.chat(config, messages) do
      {:ok, content} ->
        latency = System.monotonic_time(:millisecond) - start_time
        log_request(config, latency, true)

        response = %{
          content: content,
          model: config.model,
          provider: config.provider,
          experts_consulted: []
        }

        {:ok, response}

      {:error, reason} = error ->
        latency = System.monotonic_time(:millisecond) - start_time
        log_request(config, latency, false, reason)
        Logger.error("Orchestrator.ask_simple failed: #{inspect(reason)}")
        error
    end
  end

  defp log_request(config, latency, success, error_type \\ nil, experts_consulted \\ []) do
    log_data = %{
      provider: config.provider,
      model: config.model,
      endpoint: "orchestrator",
      input_tokens: 0,
      output_tokens: 0,
      latency_ms: latency,
      success: success
    }

    log_data =
      if error_type do
        Map.put(log_data, :error_type, to_string(error_type))
      else
        log_data
      end

    log_data =
      if length(experts_consulted) > 0 do
        Map.put(log_data, :experts_consulted, experts_consulted)
      else
        log_data
      end

    ApiLogger.log_request(log_data)
  end

  @doc """
  Checks if the orchestrator is available and configured.
  """
  @spec available?() :: boolean()
  def available? do
    case AgentRegistry.get_agent("orchestrator") do
      nil -> false
      config -> config.enabled
    end
  end

  @doc """
  Gets the current orchestrator configuration.
  """
  @spec get_config() :: map() | nil
  def get_config do
    AgentRegistry.get_agent("orchestrator")
  end

  # Build messages including chat history for multi-turn conversations
  defp build_messages_with_history([], current_prompt) do
    # No history, just the current message
    [%{role: "user", content: current_prompt}]
  end

  defp build_messages_with_history(history, current_prompt) when is_list(history) do
    # Convert chat history to message format, limiting to recent messages to save tokens
    # Keep last 6 messages (3 exchanges) for context
    recent_history =
      history
      |> Enum.take(-6)
      |> Enum.map(fn msg ->
        %{role: msg["role"] || msg[:role], content: msg["content"] || msg[:content]}
      end)

    # Add the current prompt as the latest user message
    recent_history ++ [%{role: "user", content: current_prompt}]
  end
end
