defmodule MtgDeckBuilder.Brew.ContextSerializer do
  @moduledoc """
  Serializes BrewContext into a prompt-friendly format for AI consumption.

  Produces a compact, structured representation of the deck's current state
  and the user's question, optimized for token efficiency while maintaining
  all relevant context for expert advice.
  """

  alias MtgDeckBuilder.Brew.{BrewContext, DeckSummary}
  alias MtgDeckBuilder.Brew

  @doc """
  Converts a BrewContext into a formatted prompt string.

  ## Example Output

      Deck: Control (Modern)
      Archetype: Control
      Colors: W, U
      Key Cards: Teferi, Hero of Dominaria; Supreme Verdict
      Synergies: Teferi's +1 lets us hold up Verdict while still drawing cards
      Theme: UW Planeswalker control

      Statistics:
      - Mainboard: 60 cards | Sideboard: 15 cards
      - Creatures: 4 | Instants: 16 | Sorceries: 4 | Lands: 24
      - Mana Curve: 0:2 1:4 2:12 3:8 4:6 5+:4
      - Colors: W:24 U:32
      - Avg MV: 2.5

      Missing Key Cards: None

      Question: What should I cut to make room for more removal?
  """
  @spec to_prompt(BrewContext.t()) :: String.t()
  def to_prompt(%BrewContext{} = context) do
    sections = [
      format_header(context),
      format_brew(context.brew),
      format_statistics(context.deck_summary),
      format_missing_info(context.deck_summary),
      format_question(context.question)
    ]

    sections
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n\n")
  end

  defp format_header(%BrewContext{brew: brew, format: format}) do
    archetype_str =
      if brew && brew.archetype do
        " (#{format_archetype(brew.archetype)})"
      else
        ""
      end

    "Deck: #{format_format(format)}#{archetype_str}"
  end

  defp format_brew(nil), do: nil
  defp format_brew(%Brew{} = brew) do
    parts = []

    parts =
      if brew.archetype do
        ["Archetype: #{format_archetype(brew.archetype)}" | parts]
      else
        parts
      end

    parts =
      if !Enum.empty?(brew.colors) do
        ["Colors: #{Enum.join(brew.colors, ", ")}" | parts]
      else
        parts
      end

    parts =
      if !Enum.empty?(brew.key_cards) do
        ["Key Cards: #{Enum.join(brew.key_cards, "; ")}" | parts]
      else
        parts
      end

    parts =
      if brew.synergies && brew.synergies != "" do
        ["Synergies: #{brew.synergies}" | parts]
      else
        parts
      end

    parts =
      if brew.theme && brew.theme != "" do
        ["Theme: #{brew.theme}" | parts]
      else
        parts
      end

    if Enum.empty?(parts) do
      nil
    else
      parts |> Enum.reverse() |> Enum.join("\n")
    end
  end

  defp format_statistics(%DeckSummary{} = summary) do
    lines = [
      "Statistics:",
      "- Mainboard: #{summary.mainboard_count} cards | Sideboard: #{summary.sideboard_count} cards",
      "- Types: #{format_type_breakdown(summary.cards_by_type)}",
      "- Mana Curve: #{format_mana_curve(summary.mana_curve)}",
      "- Colors: #{format_color_distribution(summary.color_distribution)}",
      "- Avg MV: #{summary.avg_mana_value} | Lands: #{summary.land_count}"
    ]

    Enum.join(lines, "\n")
  end

  defp format_missing_info(%DeckSummary{} = summary) do
    if !Enum.empty?(summary.missing_key_cards) do
      "Missing Key Cards: #{Enum.join(summary.missing_key_cards, ", ")}"
    else
      "Missing Key Cards: None"
    end
  end

  defp format_question(question) do
    "Question: #{question}"
  end

  defp format_format(format) when is_atom(format) do
    format |> Atom.to_string() |> String.capitalize()
  end

  defp format_archetype(archetype) when is_atom(archetype) do
    archetype |> Atom.to_string() |> String.capitalize()
  end

  defp format_type_breakdown(types) when is_map(types) do
    types
    |> Enum.filter(fn {_type, count} -> count > 0 end)
    |> Enum.sort_by(fn {_type, count} -> -count end)
    |> Enum.map(fn {type, count} -> "#{type}: #{count}" end)
    |> Enum.join(" | ")
  end

  defp format_mana_curve(curve) when is_list(curve) do
    curve
    |> Enum.with_index()
    |> Enum.map(fn {count, idx} ->
      cmc_label = if idx == 7, do: "7+", else: to_string(idx)
      "#{cmc_label}:#{count}"
    end)
    |> Enum.join(" ")
  end

  defp format_color_distribution(colors) when is_map(colors) do
    colors
    |> Enum.filter(fn {_color, count} -> count > 0 end)
    |> Enum.sort_by(fn {_color, count} -> -count end)
    |> Enum.map(fn {color, count} -> "#{color}:#{count}" end)
    |> Enum.join(" ")
    |> case do
      "" -> "Colorless"
      str -> str
    end
  end
end
