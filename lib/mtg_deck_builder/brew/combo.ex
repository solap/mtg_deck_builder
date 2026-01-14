defmodule MtgDeckBuilder.Brew.Combo do
  @moduledoc """
  Represents a multi-card interaction within a brew.

  A combo consists of 2-4 cards that work together, plus an optional
  description of what the combo does. Combos are embedded within a Brew
  and are not persisted separately.

  ## Fields

  - `cards` - List of card names in the combo (2-4 items, required)
  - `description` - What the combo does (max 200 chars, optional)

  ## Example

      %Combo{
        cards: ["Thassa's Oracle", "Demonic Consultation"],
        description: "Win the game by exiling library with Consultation, then Oracle"
      }
  """

  @type t :: %__MODULE__{
          cards: [String.t()],
          description: String.t() | nil
        }

  @enforce_keys [:cards]
  defstruct [:cards, :description]

  # Custom Jason.Encoder implementation
  defimpl Jason.Encoder do
    def encode(combo, opts) do
      Jason.Encode.map(MtgDeckBuilder.Brew.Combo.to_map(combo), opts)
    end
  end

  @max_cards 4
  @min_cards 2
  @max_description_length 200

  @doc """
  Creates a new combo from a map or keyword list.

  ## Examples

      iex> Combo.new(cards: ["Card A", "Card B"])
      {:ok, %Combo{cards: ["Card A", "Card B"], description: nil}}

      iex> Combo.new(%{"cards" => ["A", "B"], "description" => "Does things"})
      {:ok, %Combo{cards: ["A", "B"], description: "Does things"}}
  """
  @spec new(map() | keyword()) :: {:ok, t()} | {:error, String.t()}
  def new(attrs) when is_map(attrs) do
    cards = attrs["cards"] || attrs[:cards] || []
    description = attrs["description"] || attrs[:description]

    combo = %__MODULE__{
      cards: cards,
      description: truncate_description(description)
    }

    validate(combo)
  end

  def new(attrs) when is_list(attrs) do
    attrs |> Map.new() |> new()
  end

  @doc """
  Creates a new combo, raising on validation error.
  """
  @spec new!(map() | keyword()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, combo} -> combo
      {:error, reason} -> raise ArgumentError, reason
    end
  end

  @doc """
  Validates a combo struct.

  ## Validation Rules

  - Cards must have between 2 and 4 items
  - Each card must be a non-empty string
  - Description must be at most 200 characters (if present)

  ## Examples

      iex> Combo.validate(%Combo{cards: ["A", "B"]})
      :ok

      iex> Combo.validate(%Combo{cards: ["A"]})
      {:error, "Combo must have between 2 and 4 cards"}
  """
  @spec validate(t()) :: :ok | {:error, String.t()}
  def validate(%__MODULE__{cards: cards, description: description}) do
    with :ok <- validate_cards(cards),
         :ok <- validate_description(description) do
      :ok
    end
  end

  @doc """
  Converts a combo to a map suitable for JSON serialization.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{cards: cards, description: description}) do
    %{
      "cards" => cards,
      "description" => description
    }
  end

  @doc """
  Parses a combo from a JSON map.
  """
  @spec from_map(map()) :: {:ok, t()} | {:error, String.t()}
  def from_map(map) when is_map(map) do
    new(map)
  end

  @doc """
  Checks if a combo is complete (all cards present in deck).

  Returns true if all combo cards are found in the provided deck card list.
  """
  @spec complete?(t(), [String.t()]) :: boolean()
  def complete?(%__MODULE__{cards: combo_cards}, deck_card_names) do
    deck_names_downcased = MapSet.new(deck_card_names, &String.downcase/1)

    Enum.all?(combo_cards, fn card ->
      MapSet.member?(deck_names_downcased, String.downcase(card))
    end)
  end

  @doc """
  Returns the list of missing cards from a combo.
  """
  @spec missing_cards(t(), [String.t()]) :: [String.t()]
  def missing_cards(%__MODULE__{cards: combo_cards}, deck_card_names) do
    deck_names_downcased = MapSet.new(deck_card_names, &String.downcase/1)

    Enum.reject(combo_cards, fn card ->
      MapSet.member?(deck_names_downcased, String.downcase(card))
    end)
  end

  # Private functions

  defp validate_cards(cards) when not is_list(cards) do
    {:error, "Cards must be a list"}
  end

  defp validate_cards(cards) when length(cards) < @min_cards do
    {:error, "Combo must have at least #{@min_cards} cards"}
  end

  defp validate_cards(cards) when length(cards) > @max_cards do
    {:error, "Combo must have at most #{@max_cards} cards"}
  end

  defp validate_cards(cards) do
    if Enum.all?(cards, &valid_card_name?/1) do
      :ok
    else
      {:error, "All cards must be non-empty strings"}
    end
  end

  defp valid_card_name?(name) when is_binary(name) do
    String.trim(name) != ""
  end

  defp valid_card_name?(_), do: false

  defp validate_description(nil), do: :ok
  defp validate_description(desc) when is_binary(desc) do
    if String.length(desc) <= @max_description_length do
      :ok
    else
      {:error, "Description must be at most #{@max_description_length} characters"}
    end
  end
  defp validate_description(_), do: {:error, "Description must be a string or nil"}

  defp truncate_description(nil), do: nil
  defp truncate_description(desc) when is_binary(desc) do
    String.slice(desc, 0, @max_description_length)
  end
  defp truncate_description(_), do: nil
end
