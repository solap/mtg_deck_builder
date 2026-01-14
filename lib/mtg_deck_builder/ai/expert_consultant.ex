defmodule MtgDeckBuilder.AI.ExpertConsultant do
  @moduledoc """
  Handles consulting specialist expert agents on behalf of the orchestrator.

  When the orchestrator decides to consult an expert, this module:
  1. Looks up the appropriate specialist agent
  2. Formats the question with deck context
  3. For card_evaluator: enriches with real DB data
  4. Calls the specialist
  5. Returns the expert's response

  Each specialist has a focused prompt optimized for their domain.
  """

  alias MtgDeckBuilder.AI.{AIClient, AgentRegistry, CardDataProvider, ExpertTools}
  alias MtgDeckBuilder.Brew.{BrewContext, ContextSerializer, DeckSummary}

  require Logger

  @doc """
  Consults an expert based on a tool call from the orchestrator.

  ## Parameters

  - `tool_name` - The tool name (e.g., "consult_mana_expert")
  - `input` - The tool input map containing "question" and optional focus areas
  - `context` - The BrewContext with deck information

  ## Returns

  A string response from the expert, or an error message.
  """
  @spec consult(String.t(), map(), BrewContext.t()) :: String.t()
  def consult(tool_name, input, %BrewContext{} = context) do
    agent_id = ExpertTools.tool_to_agent_id(tool_name)
    question = input["question"] || "No specific question provided"

    Logger.debug("ExpertConsultant: Consulting #{agent_id} - #{String.slice(question, 0, 50)}...")

    case AgentRegistry.get_agent(agent_id) do
      nil ->
        # Fallback: return a helpful message if the agent isn't configured
        "Expert '#{agent_id}' is not currently available. Please provide your best assessment based on your own knowledge."

      config ->
        if config.enabled do
          # Use hybrid approach for card_evaluator
          if agent_id == "card_evaluator" do
            do_consult_with_card_data(config, question, input, context)
          else
            do_consult(config, question, input, context)
          end
        else
          "Expert '#{agent_id}' is currently disabled."
        end
    end
  end

  # Standard consultation for most experts
  defp do_consult(config, question, input, context) do
    # Build a prompt that includes deck context and the specific question
    deck_context = ContextSerializer.to_prompt(context)

    # Include any additional focus areas or cards to analyze
    focus_section = build_focus_section(input)

    full_prompt = """
    ## Deck Context

    #{deck_context}

    #{focus_section}
    ## Expert Question

    #{question}

    Please provide focused, actionable advice based on your expertise.
    """

    messages = [%{role: "user", content: full_prompt}]

    case AIClient.chat(config, messages) do
      {:ok, response} ->
        response

      {:error, reason} ->
        Logger.error("ExpertConsultant: Failed to consult #{config.agent_id}: #{inspect(reason)}")
        "Unable to consult expert due to an error: #{inspect(reason)}"
    end
  end

  # Hybrid consultation for card_evaluator - enriches with real DB data
  defp do_consult_with_card_data(config, question, input, context) do
    deck_context = ContextSerializer.to_prompt(context)
    focus_section = build_focus_section(input)

    # Get card names from the deck
    deck_card_names = get_deck_card_names(context)
    format = context.format

    # Query the database for real card data
    card_data = CardDataProvider.build_evaluation_context(deck_card_names, format: format)

    # Format the card data section
    card_data_section = format_card_data_section(card_data, input)

    full_prompt = """
    ## Deck Context

    #{deck_context}

    #{focus_section}
    ## Real Card Data from Database

    #{card_data_section}

    ## Expert Question

    #{question}

    IMPORTANT: Use the real card data above when making recommendations. The "Similar Cards" and "Potential Upgrades" sections show actual cards from the database that could replace or upgrade current deck cards. Base your analysis on this real data, not general knowledge.

    Please provide focused, actionable advice based on your expertise and the real card data.
    """

    messages = [%{role: "user", content: full_prompt}]

    case AIClient.chat(config, messages) do
      {:ok, response} ->
        response

      {:error, reason} ->
        Logger.error("ExpertConsultant: Failed to consult card_evaluator: #{inspect(reason)}")
        "Unable to consult card evaluator due to an error: #{inspect(reason)}"
    end
  end

  defp get_deck_card_names(%BrewContext{deck_summary: %DeckSummary{card_names: card_names}})
       when is_list(card_names) do
    card_names
  end

  defp get_deck_card_names(_), do: []

  defp format_card_data_section(card_data, input) do
    sections = []

    # Cards to specifically evaluate (from tool input)
    cards_to_evaluate = input["cards_to_evaluate"] || []

    # Format deck cards
    deck_cards_section =
      if map_size(card_data.deck_cards) > 0 do
        cards =
          card_data.deck_cards
          |> Enum.map(fn {name, data} ->
            price = if data[:prices][:usd], do: " ($#{data[:prices][:usd]})", else: ""
            "- #{name}: #{data[:mana_cost] || "N/A"} | #{data[:type_line]}#{price}"
          end)
          |> Enum.join("\n")

        "### Deck Cards\n#{cards}"
      else
        nil
      end

    sections = if deck_cards_section, do: [deck_cards_section | sections], else: sections

    # Format similar cards for cards being evaluated
    similar_section =
      if map_size(card_data.similar_cards) > 0 do
        similar =
          card_data.similar_cards
          |> Enum.filter(fn {name, alts} -> length(alts) > 0 and (cards_to_evaluate == [] or name in cards_to_evaluate) end)
          |> Enum.map(fn {name, alts} ->
            alt_list =
              alts
              |> Enum.map(fn alt ->
                price = if alt[:prices][:usd], do: " ($#{alt[:prices][:usd]})", else: ""
                "  - #{alt[:name]}: #{alt[:mana_cost] || "N/A"} | #{alt[:type_line]}#{price}"
              end)
              |> Enum.join("\n")

            "**Similar to #{name}:**\n#{alt_list}"
          end)
          |> Enum.join("\n\n")

        if similar != "", do: "### Similar Cards (Alternatives)\n#{similar}", else: nil
      else
        nil
      end

    sections = if similar_section, do: [similar_section | sections], else: sections

    # Format potential upgrades
    upgrades_section =
      if map_size(card_data.potential_upgrades) > 0 do
        upgrades =
          card_data.potential_upgrades
          |> Enum.filter(fn {name, ups} -> length(ups) > 0 and (cards_to_evaluate == [] or name in cards_to_evaluate) end)
          |> Enum.map(fn {name, ups} ->
            up_list =
              ups
              |> Enum.map(fn up ->
                price = if up[:prices][:usd], do: " ($#{up[:prices][:usd]})", else: ""
                "  - #{up[:name]}: #{up[:mana_cost] || "N/A"} | #{up[:rarity]}#{price}"
              end)
              |> Enum.join("\n")

            "**Upgrades for #{name}:**\n#{up_list}"
          end)
          |> Enum.join("\n\n")

        if upgrades != "", do: "### Potential Upgrades\n#{upgrades}", else: nil
      else
        nil
      end

    sections = if upgrades_section, do: [upgrades_section | sections], else: sections

    # Missing cards warning
    missing_section =
      if length(card_data.missing_from_db) > 0 do
        "### Note: Cards not found in DB\n#{Enum.join(card_data.missing_from_db, ", ")}"
      else
        nil
      end

    sections = if missing_section, do: [missing_section | sections], else: sections

    sections
    |> Enum.reverse()
    |> Enum.join("\n\n")
  end

  defp build_focus_section(input) do
    sections = []

    sections =
      if cards = input["cards_to_analyze"] || input["cards_to_evaluate"] || input["cards_involved"] do
        if is_list(cards) && length(cards) > 0 do
          ["## Cards to Focus On\n#{Enum.join(cards, ", ")}" | sections]
        else
          sections
        end
      else
        sections
      end

    sections =
      if focus = input["focus_areas"] do
        if is_list(focus) && length(focus) > 0 do
          ["## Focus Areas\n#{Enum.join(focus, ", ")}" | sections]
        else
          sections
        end
      else
        sections
      end

    sections =
      if matchups = input["matchups_of_interest"] do
        if is_list(matchups) && length(matchups) > 0 do
          ["## Matchups of Interest\n#{Enum.join(matchups, ", ")}" | sections]
        else
          sections
        end
      else
        sections
      end

    sections =
      if eval_context = input["evaluation_context"] do
        ["## Evaluation Context\n#{eval_context}" | sections]
      else
        sections
      end

    if Enum.empty?(sections) do
      ""
    else
      sections
      |> Enum.reverse()
      |> Enum.join("\n\n")
      |> then(&(&1 <> "\n\n"))
    end
  end
end
