defmodule MtgDeckBuilder.AI.CardDataProvider do
  @moduledoc """
  Provides real card data from the database for AI evaluation.

  This module queries the card database to ground AI responses in
  actual card data rather than relying on the model's training data.

  Used by the card_evaluator expert to make accurate recommendations.
  """

  import Ecto.Query
  alias MtgDeckBuilder.Cards.Card
  alias MtgDeckBuilder.Repo

  @doc """
  Gets detailed card data for a list of card names.
  Returns a map of name -> card data.
  """
  @spec get_cards_by_names([String.t()]) :: %{String.t() => map()}
  def get_cards_by_names(names) when is_list(names) do
    names_lower = Enum.map(names, &String.downcase/1)

    from(c in Card, where: fragment("lower(?)", c.name) in ^names_lower)
    |> Repo.all()
    |> Map.new(fn card -> {card.name, format_card_data(card)} end)
  end

  @doc """
  Finds similar cards to the given card names.
  Similar = same CMC, overlapping colors, similar card type.
  """
  @spec find_similar_cards([String.t()], keyword()) :: %{String.t() => [map()]}
  def find_similar_cards(card_names, opts \\ []) do
    format = Keyword.get(opts, :format)
    limit = Keyword.get(opts, :limit, 5)

    # Get the original cards first
    original_cards = get_cards_by_names(card_names)

    # For each card, find similar ones
    card_names
    |> Enum.map(fn name ->
      case Map.get(original_cards, name) do
        nil ->
          {name, []}

        card_data ->
          similar = find_similar_to_card(card_data, format, limit, Map.keys(original_cards))
          {name, similar}
      end
    end)
    |> Map.new()
  end

  @doc """
  Finds potential upgrades for cards in the deck.
  Upgrades = same role but better stats/effects, or strictly better.
  """
  @spec find_upgrades([String.t()], keyword()) :: %{String.t() => [map()]}
  def find_upgrades(card_names, opts \\ []) do
    format = Keyword.get(opts, :format)
    limit = Keyword.get(opts, :limit, 3)

    original_cards = get_cards_by_names(card_names)

    card_names
    |> Enum.map(fn name ->
      case Map.get(original_cards, name) do
        nil ->
          {name, []}

        card_data ->
          upgrades = find_upgrades_for_card(card_data, format, limit, Map.keys(original_cards))
          {name, upgrades}
      end
    end)
    |> Map.new()
  end

  @doc """
  Gets cards that share a type/subtype with the given cards.
  Useful for finding tribal synergies or archetype staples.
  """
  @spec find_cards_by_type(String.t(), keyword()) :: [map()]
  def find_cards_by_type(type_fragment, opts \\ []) do
    format = Keyword.get(opts, :format)
    limit = Keyword.get(opts, :limit, 10)

    query =
      from c in Card,
        where: ilike(c.type_line, ^"%#{type_fragment}%"),
        order_by: [asc: c.cmc, asc: c.name],
        limit: ^limit

    query
    |> maybe_filter_format(format)
    |> Repo.all()
    |> Enum.map(&format_card_data/1)
  end

  @doc """
  Gets cards in a specific CMC range.
  """
  @spec find_cards_by_cmc(number(), number(), keyword()) :: [map()]
  def find_cards_by_cmc(min_cmc, max_cmc, opts \\ []) do
    format = Keyword.get(opts, :format)
    colors = Keyword.get(opts, :colors, [])
    limit = Keyword.get(opts, :limit, 20)

    query =
      from c in Card,
        where: c.cmc >= ^min_cmc and c.cmc <= ^max_cmc,
        where: c.is_basic_land == false,
        order_by: [asc: c.cmc, asc: c.name],
        limit: ^limit

    query
    |> maybe_filter_format(format)
    |> maybe_filter_colors(colors)
    |> Repo.all()
    |> Enum.map(&format_card_data/1)
  end

  @doc """
  Builds a comprehensive evaluation context for the AI.
  Includes deck cards + similar cards + potential upgrades.
  """
  @spec build_evaluation_context([String.t()], keyword()) :: map()
  def build_evaluation_context(deck_card_names, opts \\ []) do
    format = Keyword.get(opts, :format)

    # Get full data for deck cards
    deck_cards = get_cards_by_names(deck_card_names)

    # Get cards we have data for
    found_names = Map.keys(deck_cards)
    missing_names = deck_card_names -- found_names

    # Find similar cards for non-land, non-basic cards
    evaluatable_cards =
      deck_cards
      |> Enum.reject(fn {_name, data} ->
        data[:is_basic_land] || String.contains?(data[:type_line] || "", "Land")
      end)
      |> Enum.map(fn {name, _} -> name end)

    similar = find_similar_cards(evaluatable_cards, format: format, limit: 3)
    upgrades = find_upgrades(evaluatable_cards, format: format, limit: 3)

    %{
      deck_cards: deck_cards,
      missing_from_db: missing_names,
      similar_cards: similar,
      potential_upgrades: upgrades,
      format: format
    }
  end

  # Private functions

  defp find_similar_to_card(card_data, format, limit, exclude_names) do
    cmc = card_data[:cmc] || 0
    colors = card_data[:colors] || []
    type_line = card_data[:type_line] || ""

    # Extract main card type
    main_type = extract_main_type(type_line)

    query =
      from c in Card,
        where: c.cmc >= ^(cmc - 1) and c.cmc <= ^(cmc + 1),
        where: c.is_basic_land == false,
        where: c.name not in ^exclude_names,
        order_by: [asc: fragment("abs(? - ?)", c.cmc, ^cmc), asc: c.name],
        limit: ^limit

    query
    |> maybe_filter_format(format)
    |> maybe_filter_type(main_type)
    |> maybe_filter_colors_overlap(colors)
    |> Repo.all()
    |> Enum.map(&format_card_data/1)
  end

  defp find_upgrades_for_card(card_data, format, limit, exclude_names) do
    cmc = card_data[:cmc] || 0
    colors = card_data[:colors] || []
    type_line = card_data[:type_line] || ""
    main_type = extract_main_type(type_line)

    # Upgrades: same or lower CMC, same type, better rarity often means better
    query =
      from c in Card,
        where: c.cmc <= ^cmc,
        where: c.is_basic_land == false,
        where: c.name not in ^exclude_names,
        where: c.rarity in ["rare", "mythic"],
        order_by: [asc: c.cmc, desc: c.rarity, asc: c.name],
        limit: ^limit

    query
    |> maybe_filter_format(format)
    |> maybe_filter_type(main_type)
    |> maybe_filter_colors_overlap(colors)
    |> Repo.all()
    |> Enum.map(&format_card_data/1)
  end

  defp extract_main_type(type_line) when is_binary(type_line) do
    type_line
    |> String.split(" — ")
    |> List.first()
    |> String.split()
    |> Enum.find(fn word ->
      word in ["Creature", "Instant", "Sorcery", "Enchantment", "Artifact", "Planeswalker"]
    end)
  end

  defp extract_main_type(_), do: nil

  defp maybe_filter_format(query, nil), do: query

  defp maybe_filter_format(query, format) when is_atom(format) do
    format_key = Atom.to_string(format)

    from c in query,
      where: fragment("?->>? = ?", c.legalities, ^format_key, "legal")
  end

  defp maybe_filter_format(query, format) when is_binary(format) do
    from c in query,
      where: fragment("?->>? = ?", c.legalities, ^format, "legal")
  end

  defp maybe_filter_type(query, nil), do: query

  defp maybe_filter_type(query, main_type) do
    from c in query,
      where: ilike(c.type_line, ^"%#{main_type}%")
  end

  defp maybe_filter_colors(query, []), do: query

  defp maybe_filter_colors(query, colors) do
    from c in query,
      where: fragment("? && ?", c.colors, ^colors)
  end

  defp maybe_filter_colors_overlap(query, []), do: query

  defp maybe_filter_colors_overlap(query, colors) do
    # Cards that share at least one color OR are colorless
    from c in query,
      where: fragment("? && ? OR ? = '{}'", c.colors, ^colors, c.colors)
  end

  defp format_card_data(%Card{} = card) do
    %{
      name: card.name,
      mana_cost: card.mana_cost,
      cmc: card.cmc,
      type_line: card.type_line,
      oracle_text: card.oracle_text,
      colors: card.colors,
      color_identity: card.color_identity,
      rarity: card.rarity,
      is_basic_land: card.is_basic_land,
      prices: format_prices(card.prices),
      legalities: card.legalities
    }
  end

  defp format_prices(nil), do: nil
  defp format_prices(prices) when is_map(prices) do
    %{
      usd: prices["usd"],
      usd_foil: prices["usd_foil"]
    }
  end
end
