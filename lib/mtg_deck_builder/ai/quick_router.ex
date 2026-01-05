defmodule MtgDeckBuilder.AI.QuickRouter do
  @moduledoc """
  Fast intent router using Haiku for quick classification and simple action handling.

  This module provides a two-tier approach:
  1. Quick classification (~200ms) to determine intent type
  2. Direct handling for simple actions, or routing to Orchestrator for complex queries

  ## Intent Types

  - `:card_search` - User wants to find/search for cards matching criteria
  - `:deck_action` - Simple deck operations (set colors, archetype, add cards)
  - `:strategy_question` - Complex questions requiring expert consultation
  - `:deck_build` - Build a complete deck from scratch

  ## Usage

      context = BrewContext.build(brew, deck, "find a white flicker creature")
      case QuickRouter.route(context) do
        {:handled, response, actions} -> # Apply actions and show response
        {:route_to_orchestrator, context} -> # Pass to full orchestrator
      end
  """

  alias MtgDeckBuilder.AI.{AIClient, AgentRegistry}
  alias MtgDeckBuilder.Brew.BrewContext
  alias MtgDeckBuilder.Cards

  require Logger

  @type intent :: :card_search | :deck_action | :strategy_question | :deck_build | :greeting | :unknown
  @type action :: {:set_archetype, atom()} | {:set_colors, [String.t()]} | {:add_cards, String.t(), [map()]} | {:search_results, [map()]}

  @type route_result ::
          {:handled, String.t(), [action()]}
          | {:route_to_orchestrator, BrewContext.t()}
          | {:error, String.t()}

  @classification_tool %{
    "name" => "classify_intent",
    "description" => "Classify the user's intent for the MTG deck builder",
    "input_schema" => %{
      "type" => "object",
      "properties" => %{
        "intent" => %{
          "type" => "string",
          "enum" => ["card_search", "deck_action", "strategy_question", "deck_build", "greeting", "unknown"],
          "description" => """
          The user's primary intent:
          - card_search: Looking for cards with SEARCHABLE attributes (colors, card types, keywords in oracle text like "draw", "destroy", "ETB", "flicker"). Use ONLY when the criteria can be matched against card text.
          - deck_action: Simple action like setting colors, archetype, or adding specific cards by name
          - strategy_question: Questions requiring MTG knowledge that ISN'T in card text - combos, infinite combos, synergies, what cards work well together, meta questions, what to cut, deck improvements. "Find me a combo" = strategy_question.
          - deck_build: Request to build a complete deck or major portion from scratch
          - greeting: Greeting or casual chat
          - unknown: Can't determine intent

          IMPORTANT: "combo", "infinite combo", "synergy", "goes well with" = strategy_question (requires game knowledge, not text search)
          """
        },
        "search_criteria" => %{
          "type" => "object",
          "description" => "For card_search intent - the search parameters",
          "properties" => %{
            "colors" => %{
              "type" => "array",
              "items" => %{"type" => "string", "enum" => ["W", "U", "B", "R", "G", "colorless"]},
              "description" => "Colors to filter by"
            },
            "text_search" => %{
              "type" => "string",
              "description" => "Text to search in card name or oracle text (e.g., 'flicker', 'ETB', 'draw')"
            },
            "type" => %{
              "type" => "string",
              "description" => "Card type to filter by (creature, instant, sorcery, etc.)"
            }
          }
        },
        "deck_actions" => %{
          "type" => "object",
          "description" => "For deck_action intent - the actions to take",
          "properties" => %{
            "set_archetype" => %{
              "type" => "string",
              "enum" => ["aggro", "midrange", "control", "combo", "tempo", "ramp"],
              "description" => "Archetype to set"
            },
            "set_colors" => %{
              "type" => "array",
              "items" => %{"type" => "string", "enum" => ["W", "U", "B", "R", "G"]},
              "description" => "Colors to set"
            },
            "add_cards" => %{
              "type" => "array",
              "items" => %{"type" => "string"},
              "description" => "Specific card names to add"
            },
            "target_board" => %{
              "type" => "string",
              "enum" => ["mainboard", "sideboard", "staging"],
              "description" => "Where to add cards (default: mainboard)"
            }
          }
        },
        "confidence" => %{
          "type" => "number",
          "minimum" => 0,
          "maximum" => 1,
          "description" => "Confidence in the classification (0-1)"
        },
        "reason" => %{
          "type" => "string",
          "description" => "Brief explanation of why this intent was chosen"
        }
      },
      "required" => ["intent", "confidence"]
    }
  }

  @doc """
  Routes a user request to the appropriate handler.

  Returns:
  - `{:handled, response, actions}` - Request was handled directly, apply actions
  - `{:route_to_orchestrator, context}` - Pass to full orchestrator for complex handling
  - `{:error, reason}` - Something went wrong
  """
  @spec route(BrewContext.t(), keyword()) :: route_result()
  def route(%BrewContext{} = context, opts \\ []) do
    format = Keyword.get(opts, :format, :modern)

    case classify_intent(context.question) do
      {:ok, %{intent: :card_search, search_criteria: criteria, confidence: conf}} when conf > 0.7 ->
        handle_card_search(criteria, format)

      {:ok, %{intent: :deck_action, deck_actions: actions, confidence: conf}} when conf > 0.7 ->
        handle_deck_action(actions, format)

      {:ok, %{intent: :greeting, confidence: conf}} when conf > 0.7 ->
        {:handled, "Hey! I'm here to help you build your MTG deck. What would you like to do?", []}

      {:ok, %{intent: intent, confidence: conf}} when intent in [:strategy_question, :deck_build] or conf <= 0.7 ->
        # Complex question or low confidence - route to orchestrator
        {:route_to_orchestrator, context}

      {:ok, _} ->
        # Unknown or unhandled - route to orchestrator
        {:route_to_orchestrator, context}

      {:error, reason} ->
        Logger.warning("QuickRouter classification failed: #{reason}, routing to orchestrator")
        {:route_to_orchestrator, context}
    end
  end

  @doc """
  Classifies the intent of a user message using Haiku.
  """
  @spec classify_intent(String.t()) :: {:ok, map()} | {:error, String.t()}
  def classify_intent(message) when is_binary(message) do
    case AgentRegistry.get_agent("quick_router") do
      nil ->
        # Fallback to orchestrator if quick_router agent not configured
        {:error, "quick_router agent not configured"}

      config ->
        messages = [%{role: "user", content: message}]

        case AIClient.chat_with_tools(config, messages, [@classification_tool], &handle_tool_call/2) do
          {:ok, _text} ->
            # If we got text back instead of tool use, check Process dictionary
            case Process.get(:classification_result) do
              nil -> {:error, "No classification result"}
              result -> {:ok, result}
            end

          {:error, _} = error ->
            error
        end
    end
  end

  # Tool call handler for classification
  defp handle_tool_call("classify_intent", input) do
    # Store the result and return acknowledgment
    result = %{
      intent: parse_intent(input["intent"]),
      search_criteria: input["search_criteria"],
      deck_actions: input["deck_actions"],
      confidence: input["confidence"] || 0.5,
      reason: input["reason"]
    }

    Process.put(:classification_result, result)
    "Classification recorded: #{input["intent"]}"
  end

  defp handle_tool_call(name, _input) do
    "Unknown tool: #{name}"
  end

  defp parse_intent("card_search"), do: :card_search
  defp parse_intent("deck_action"), do: :deck_action
  defp parse_intent("strategy_question"), do: :strategy_question
  defp parse_intent("deck_build"), do: :deck_build
  defp parse_intent("greeting"), do: :greeting
  defp parse_intent(_), do: :unknown

  # Handle card search directly
  defp handle_card_search(nil, _format), do: {:route_to_orchestrator, nil}
  defp handle_card_search(criteria, format) when is_map(criteria) do
    # Build search query from criteria
    text_search = criteria["text_search"] || ""
    colors = criteria["colors"] || []
    card_type = criteria["type"]

    # Search for cards
    results = search_cards_with_criteria(text_search, colors, card_type, format)

    if Enum.empty?(results) do
      {:handled, "I couldn't find any cards matching those criteria. Try broadening your search or check the card name spelling.", []}
    else
      # Format response
      response = format_search_results(results, criteria)
      {:handled, response, [{:search_results, results}]}
    end
  end

  defp search_cards_with_criteria(text, colors, type, format) do
    # Start with text search
    base_results = if text != "" do
      # Search in card names and oracle text
      Cards.search(text, format: format, limit: 50)
    else
      []
    end

    # Filter by colors if specified
    results = if Enum.empty?(colors) do
      base_results
    else
      Enum.filter(base_results, fn card ->
        card_colors = card.colors || []

        cond do
          "colorless" in colors ->
            Enum.empty?(card_colors)

          true ->
            # Card must match at least one of the specified colors
            # and not have colors outside the specified set
            Enum.any?(card_colors, &(&1 in colors)) &&
              Enum.all?(card_colors, &(&1 in colors))
        end
      end)
    end

    # Filter by type if specified
    results = if type do
      type_lower = String.downcase(type)
      Enum.filter(results, fn card ->
        type_line = String.downcase(card.type_line || "")
        String.contains?(type_line, type_lower)
      end)
    else
      results
    end

    # Limit to top 10
    Enum.take(results, 10)
  end

  defp format_search_results(results, criteria) do
    header = build_search_header(criteria)
    cards = Enum.map_join(results, "\n", fn card ->
      colors_str = if card.colors && !Enum.empty?(card.colors) do
        "(#{Enum.join(card.colors, "")})"
      else
        "(C)"
      end

      "• **#{card.name}** #{card.mana_cost || ""} #{colors_str} - #{card.type_line}"
    end)

    "#{header}\n\n#{cards}\n\nWant me to add any of these to your deck?"
  end

  defp build_search_header(criteria) do
    parts = []

    parts = if criteria["colors"] && !Enum.empty?(criteria["colors"]) do
      colors = Enum.join(criteria["colors"], "/")
      ["#{colors}" | parts]
    else
      parts
    end

    parts = if criteria["type"] do
      [criteria["type"] | parts]
    else
      parts
    end

    parts = if criteria["text_search"] && criteria["text_search"] != "" do
      ["with \"#{criteria["text_search"]}\"" | parts]
    else
      parts
    end

    if Enum.empty?(parts) do
      "Found these cards:"
    else
      "Found these #{Enum.join(Enum.reverse(parts), " ")} cards:"
    end
  end

  # Handle simple deck actions directly
  defp handle_deck_action(nil, _format), do: {:route_to_orchestrator, nil}
  defp handle_deck_action(actions, format) when is_map(actions) do
    result_actions = []
    responses = []

    # Handle set_archetype
    {result_actions, responses} = if actions["set_archetype"] do
      archetype = String.to_existing_atom(actions["set_archetype"])
      {
        [{:set_archetype, archetype} | result_actions],
        ["Set archetype to **#{actions["set_archetype"]}**" | responses]
      }
    else
      {result_actions, responses}
    end

    # Handle set_colors
    {result_actions, responses} = if actions["set_colors"] && !Enum.empty?(actions["set_colors"]) do
      colors = actions["set_colors"]
      {
        [{:set_colors, colors} | result_actions],
        ["Set colors to **#{Enum.join(colors, ", ")}**" | responses]
      }
    else
      {result_actions, responses}
    end

    # Handle add_cards
    {result_actions, responses} = if actions["add_cards"] && !Enum.empty?(actions["add_cards"]) do
      board = actions["target_board"] || "mainboard"
      cards = lookup_cards(actions["add_cards"], format)

      if Enum.empty?(cards) do
        {result_actions, ["Couldn't find the specified cards" | responses]}
      else
        found_names = Enum.map(cards, & &1.name)
        {
          [{:add_cards, board, cards} | result_actions],
          ["Added #{length(cards)} card(s) to #{board}: #{Enum.join(found_names, ", ")}" | responses]
        }
      end
    else
      {result_actions, responses}
    end

    if Enum.empty?(result_actions) do
      {:route_to_orchestrator, nil}
    else
      response = Enum.reverse(responses) |> Enum.join("\n")
      {:handled, response, Enum.reverse(result_actions)}
    end
  end

  defp lookup_cards(card_names, format) when is_list(card_names) do
    card_names
    |> Enum.flat_map(fn name ->
      case Cards.search(name, format: format, limit: 1) do
        [card | _] -> [card]
        [] -> []
      end
    end)
  end
end
