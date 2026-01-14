defmodule MtgDeckBuilder.Brew do
  @moduledoc """
  Represents the strategic context for a deck.

  A Brew captures the deck's identity: its archetype, colors, key cards it's built
  around, synergies description, and a theme description. This context is used by
  the AI orchestrator to provide more relevant advice.

  ## Fields

  - `archetype` - The deck's strategic approach (control, aggro, midrange, etc.)
  - `colors` - MTG colors the deck uses (W, U, B, R, G)
  - `key_cards` - Card names the deck is built around (max 10)
  - `synergies` - Description of how key cards work together (max 300 chars)
  - `theme` - Free-text deck identity description (max 500 chars)

  ## Lifecycle

  - Created when user enters Brew Mode
  - Persisted with deck state in localStorage
  - All fields are optional - user fills what matters to them

  ## Example

      %Brew{
        archetype: :control,
        colors: ["W", "U"],
        key_cards: ["Teferi, Hero of Dominaria", "Supreme Verdict"],
        synergies: "Teferi's +1 lets us hold up Verdict while still drawing cards",
        theme: "UW Planeswalker Control focusing on card advantage"
      }
  """

  @type archetype :: :control | :aggro | :midrange | :combo | :tempo | :ramp | nil
  @type color :: String.t()  # "W", "U", "B", "R", "G"
  @type t :: %__MODULE__{
          archetype: archetype(),
          colors: [color()],
          key_cards: [String.t()],
          synergies: String.t() | nil,
          theme: String.t() | nil
        }

  defstruct archetype: nil,
            colors: [],
            key_cards: [],
            synergies: nil,
            theme: nil

  # Custom Jason.Encoder implementation
  defimpl Jason.Encoder do
    def encode(brew, opts) do
      Jason.Encode.map(MtgDeckBuilder.Brew.to_map(brew), opts)
    end
  end

  @valid_archetypes [:control, :aggro, :midrange, :combo, :tempo, :ramp]
  @valid_colors ["W", "U", "B", "R", "G"]
  @max_key_cards 10
  @max_synergies_length 300
  @max_theme_length 500

  @doc """
  Returns a list of valid archetype atoms.
  """
  @spec valid_archetypes() :: [archetype()]
  def valid_archetypes, do: @valid_archetypes

  @doc """
  Creates a new empty brew with default values.

  ## Example

      iex> Brew.new()
      %Brew{archetype: nil, colors: [], key_cards: [], synergies: nil, theme: nil}
  """
  @spec new() :: t()
  def new do
    %__MODULE__{}
  end

  @doc """
  Creates a new brew from a map or keyword list.

  ## Examples

      iex> Brew.new(archetype: :control, key_cards: ["Teferi"])
      {:ok, %Brew{archetype: :control, key_cards: ["Teferi"], ...}}

      iex> Brew.new(%{"archetype" => "aggro", "key_cards" => ["Bolt"]})
      {:ok, %Brew{archetype: :aggro, key_cards: ["Bolt"], ...}}
  """
  @spec new(map() | keyword()) :: {:ok, t()} | {:error, String.t()}
  def new(attrs) when is_map(attrs) do
    archetype = parse_archetype(attrs["archetype"] || attrs[:archetype])
    colors = parse_colors(attrs["colors"] || attrs[:colors] || [])
    key_cards = attrs["key_cards"] || attrs[:key_cards] || []
    synergies = attrs["synergies"] || attrs[:synergies]
    theme = attrs["theme"] || attrs[:theme]

    brew = %__MODULE__{
      archetype: archetype,
      colors: colors,
      key_cards: Enum.take(key_cards, @max_key_cards),
      synergies: truncate_synergies(synergies),
      theme: truncate_theme(theme)
    }

    case validate(brew) do
      :ok -> {:ok, brew}
      {:error, _} = error -> error
    end
  end

  def new(attrs) when is_list(attrs) do
    attrs |> Map.new() |> new()
  end

  @doc """
  Creates a new brew, raising on validation error.
  """
  @spec new!(map() | keyword()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, brew} -> brew
      {:error, reason} -> raise ArgumentError, reason
    end
  end

  @doc """
  Validates a brew struct.

  ## Validation Rules

  - Archetype must be a valid enum value or nil
  - Colors must be valid MTG colors (W, U, B, R, G)
  - Key cards max 10 items, each must be a non-empty string
  - Synergies max 300 characters
  - Theme max 500 characters

  ## Examples

      iex> Brew.validate(%Brew{archetype: :control})
      :ok

      iex> Brew.validate(%Brew{archetype: :invalid})
      {:error, "Invalid archetype"}
  """
  @spec validate(t()) :: :ok | {:error, String.t()}
  def validate(%__MODULE__{} = brew) do
    with :ok <- validate_archetype(brew.archetype),
         :ok <- validate_key_cards(brew.key_cards),
         :ok <- validate_synergies(brew.synergies),
         :ok <- validate_theme(brew.theme) do
      :ok
    end
  end

  @doc """
  Converts a brew to a map suitable for JSON serialization.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = brew) do
    %{
      "archetype" => archetype_to_string(brew.archetype),
      "colors" => brew.colors,
      "key_cards" => brew.key_cards,
      "synergies" => brew.synergies,
      "theme" => brew.theme
    }
  end

  @doc """
  Parses a brew from a JSON map.
  """
  @spec from_map(map() | nil) :: {:ok, t()} | {:error, String.t()}
  def from_map(nil), do: {:ok, new()}
  def from_map(map) when is_map(map), do: new(map)

  @doc """
  Updates a brew with new attributes.

  Only updates the fields provided in the attrs map.
  """
  @spec update(t(), map() | keyword()) :: {:ok, t()} | {:error, String.t()}
  def update(%__MODULE__{} = brew, attrs) when is_map(attrs) do
    updated = %__MODULE__{
      archetype: get_updated_field(attrs, :archetype, brew.archetype, &parse_archetype/1),
      colors: get_updated_field(attrs, :colors, brew.colors, &parse_colors/1),
      key_cards: get_updated_field(attrs, :key_cards, brew.key_cards, &ensure_list/1),
      synergies: get_updated_field(attrs, :synergies, brew.synergies, &identity/1),
      theme: get_updated_field(attrs, :theme, brew.theme, &identity/1)
    }

    case validate(updated) do
      :ok -> {:ok, updated}
      {:error, _} = error -> error
    end
  end

  def update(%__MODULE__{} = brew, attrs) when is_list(attrs) do
    attrs |> Map.new() |> then(&update(brew, &1))
  end

  @doc """
  Adds a key card to the brew.
  """
  @spec add_key_card(t(), String.t()) :: {:ok, t()} | {:error, String.t()}
  def add_key_card(%__MODULE__{key_cards: key_cards} = brew, card_name)
      when is_binary(card_name) do
    if length(key_cards) >= @max_key_cards do
      {:error, "Maximum #{@max_key_cards} key cards allowed"}
    else
      if card_name in key_cards do
        {:ok, brew}
      else
        {:ok, %{brew | key_cards: key_cards ++ [card_name]}}
      end
    end
  end

  @doc """
  Removes a key card from the brew.
  """
  @spec remove_key_card(t(), String.t()) :: {:ok, t()}
  def remove_key_card(%__MODULE__{key_cards: key_cards} = brew, card_name) do
    {:ok, %{brew | key_cards: List.delete(key_cards, card_name)}}
  end

  @doc """
  Calculates which key cards are missing from the deck.
  """
  @spec missing_key_cards(t(), [String.t()]) :: [String.t()]
  def missing_key_cards(%__MODULE__{key_cards: key_cards}, deck_card_names) do
    deck_names_downcased = MapSet.new(deck_card_names, &String.downcase/1)

    Enum.reject(key_cards, fn card ->
      MapSet.member?(deck_names_downcased, String.downcase(card))
    end)
  end

  # Private functions

  defp parse_archetype(nil), do: nil
  defp parse_archetype(archetype) when archetype in @valid_archetypes, do: archetype
  defp parse_archetype(archetype) when is_binary(archetype) do
    case String.to_existing_atom(archetype) do
      atom when atom in @valid_archetypes -> atom
      _ -> nil
    end
  rescue
    ArgumentError -> nil
  end
  defp parse_archetype(_), do: nil

  defp archetype_to_string(nil), do: nil
  defp archetype_to_string(archetype) when is_atom(archetype), do: Atom.to_string(archetype)

  defp parse_colors(colors) when is_list(colors) do
    colors
    |> Enum.filter(&(&1 in @valid_colors))
    |> Enum.uniq()
  end
  defp parse_colors(_), do: []

  defp validate_archetype(nil), do: :ok
  defp validate_archetype(archetype) when archetype in @valid_archetypes, do: :ok
  defp validate_archetype(_), do: {:error, "Invalid archetype. Must be one of: #{inspect(@valid_archetypes)}"}

  defp validate_key_cards(cards) when not is_list(cards) do
    {:error, "Key cards must be a list"}
  end

  defp validate_key_cards(cards) when length(cards) > @max_key_cards do
    {:error, "Maximum #{@max_key_cards} key cards allowed"}
  end

  defp validate_key_cards(cards) do
    if Enum.all?(cards, &valid_card_name?/1) do
      :ok
    else
      {:error, "All key cards must be non-empty strings"}
    end
  end

  defp valid_card_name?(name) when is_binary(name), do: String.trim(name) != ""
  defp valid_card_name?(_), do: false

  defp validate_synergies(nil), do: :ok
  defp validate_synergies(synergies) when is_binary(synergies) do
    if String.length(synergies) <= @max_synergies_length do
      :ok
    else
      {:error, "Synergies must be at most #{@max_synergies_length} characters"}
    end
  end
  defp validate_synergies(_), do: {:error, "Synergies must be a string or nil"}

  defp validate_theme(nil), do: :ok
  defp validate_theme(theme) when is_binary(theme) do
    if String.length(theme) <= @max_theme_length do
      :ok
    else
      {:error, "Theme must be at most #{@max_theme_length} characters"}
    end
  end
  defp validate_theme(_), do: {:error, "Theme must be a string or nil"}

  defp truncate_synergies(nil), do: nil
  defp truncate_synergies(synergies) when is_binary(synergies), do: String.slice(synergies, 0, @max_synergies_length)
  defp truncate_synergies(_), do: nil

  defp truncate_theme(nil), do: nil
  defp truncate_theme(theme) when is_binary(theme), do: String.slice(theme, 0, @max_theme_length)
  defp truncate_theme(_), do: nil

  defp get_updated_field(attrs, key, default, transform) do
    string_key = to_string(key)

    cond do
      Map.has_key?(attrs, key) -> transform.(Map.get(attrs, key))
      Map.has_key?(attrs, string_key) -> transform.(Map.get(attrs, string_key))
      true -> default
    end
  end

  defp ensure_list(val) when is_list(val), do: val
  defp ensure_list(_), do: []

  defp identity(val), do: val
end
