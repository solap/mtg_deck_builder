defmodule MtgDeckBuilder.Brew.BrewContext do
  @moduledoc """
  Rich context object passed to AI for expert synthesis.

  Combines the brew (strategic identity), deck summary (statistics),
  and user question into a single context for the AI orchestrator.
  """

  alias MtgDeckBuilder.Brew
  alias MtgDeckBuilder.Brew.DeckSummary
  alias MtgDeckBuilder.Decks.Deck

  @type t :: %__MODULE__{
          brew: Brew.t() | nil,
          deck_summary: DeckSummary.t(),
          question: String.t(),
          format: atom(),
          chat_history: [map()]
        }

  defstruct brew: nil,
            deck_summary: nil,
            question: "",
            format: :modern,
            chat_history: []

  @doc """
  Builds a BrewContext from a brew, deck, and question.

  ## Options

  - `:chat_history` - Previous conversation messages as list of `%{role: "user"|"assistant", content: "..."}`

  ## Examples

      iex> BrewContext.build(brew, deck, "What should I add?")
      %BrewContext{brew: %Brew{...}, deck_summary: %DeckSummary{...}, question: "..."}

      iex> BrewContext.build(brew, deck, "Follow up", chat_history: history)
      %BrewContext{..., chat_history: [...]}
  """
  @spec build(Brew.t() | nil, Deck.t(), String.t(), keyword()) :: t()
  def build(brew, %Deck{} = deck, question, opts \\ []) when is_binary(question) do
    deck_summary = DeckSummary.build(deck, brew)
    chat_history = Keyword.get(opts, :chat_history, [])

    %__MODULE__{
      brew: brew,
      deck_summary: deck_summary,
      question: question,
      format: deck.format,
      chat_history: chat_history
    }
  end

  @doc """
  Returns whether this context has a brew defined.
  """
  @spec has_brew?(t()) :: boolean()
  def has_brew?(%__MODULE__{brew: nil}), do: false
  def has_brew?(%__MODULE__{brew: %Brew{}}), do: true

  @doc """
  Returns whether this context has any strategic identity defined.
  A brew has strategic identity if it has an archetype, colors, key cards, synergies, or theme.
  """
  @spec has_strategic_identity?(t()) :: boolean()
  def has_strategic_identity?(%__MODULE__{brew: nil}), do: false
  def has_strategic_identity?(%__MODULE__{brew: brew}) do
    !is_nil(brew.archetype) ||
      !Enum.empty?(brew.colors) ||
      !Enum.empty?(brew.key_cards) ||
      (!is_nil(brew.synergies) && brew.synergies != "") ||
      (!is_nil(brew.theme) && brew.theme != "")
  end
end
