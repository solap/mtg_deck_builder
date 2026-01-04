defmodule MtgDeckBuilder.Chat.UndoServer do
  @moduledoc """
  GenServer that manages single-level undo state for chat commands.

  Stores the previous deck state and action description so the user
  can undo their last chat-initiated action.
  """

  use GenServer

  alias MtgDeckBuilder.Decks.Deck

  @doc """
  Starts the UndoServer.
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, %{}, name: name)
  end

  @doc """
  Saves the current deck state before a modification.

  ## Parameters
    - deck: The deck state before the modification
    - description: A human-readable description of what changed

  ## Examples

      iex> UndoServer.save_state(deck, "Added 4x Lightning Bolt to mainboard")
      :ok
  """
  @spec save_state(Deck.t(), String.t()) :: :ok
  def save_state(%Deck{} = deck, description) when is_binary(description) do
    GenServer.call(__MODULE__, {:save_state, deck, description})
  end

  @doc """
  Saves state with a custom server name (for testing).
  """
  @spec save_state(atom(), Deck.t(), String.t()) :: :ok
  def save_state(server, %Deck{} = deck, description) when is_atom(server) and is_binary(description) do
    GenServer.call(server, {:save_state, deck, description})
  end

  @doc """
  Retrieves and clears the undo state, returning the previous deck.

  ## Returns
    - {:ok, previous_deck, description} - If undo state exists
    - {:error, :nothing_to_undo} - If no undo state available

  ## Examples

      iex> UndoServer.undo()
      {:ok, %Deck{...}, "Added 4x Lightning Bolt to mainboard"}
  """
  @spec undo() :: {:ok, Deck.t(), String.t()} | {:error, :nothing_to_undo}
  def undo do
    GenServer.call(__MODULE__, :undo)
  end

  @doc """
  Undo with a custom server name (for testing).
  """
  @spec undo(atom()) :: {:ok, Deck.t(), String.t()} | {:error, :nothing_to_undo}
  def undo(server) when is_atom(server) do
    GenServer.call(server, :undo)
  end

  @doc """
  Clears the undo state without performing an undo.
  """
  @spec clear() :: :ok
  def clear do
    GenServer.call(__MODULE__, :clear)
  end

  @doc """
  Clear with a custom server name (for testing).
  """
  @spec clear(atom()) :: :ok
  def clear(server) when is_atom(server) do
    GenServer.call(server, :clear)
  end

  @doc """
  Checks if there is an undo state available.
  """
  @spec has_undo?() :: boolean()
  def has_undo? do
    GenServer.call(__MODULE__, :has_undo?)
  end

  @doc """
  Check undo availability with a custom server name (for testing).
  """
  @spec has_undo?(atom()) :: boolean()
  def has_undo?(server) when is_atom(server) do
    GenServer.call(server, :has_undo?)
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    {:ok, %{previous_deck: nil, description: nil}}
  end

  @impl true
  def handle_call({:save_state, deck, description}, _from, _state) do
    new_state = %{previous_deck: deck, description: description}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:undo, _from, %{previous_deck: nil} = state) do
    {:reply, {:error, :nothing_to_undo}, state}
  end

  @impl true
  def handle_call(:undo, _from, %{previous_deck: deck, description: description}) do
    # Clear state after undo
    {:reply, {:ok, deck, description}, %{previous_deck: nil, description: nil}}
  end

  @impl true
  def handle_call(:clear, _from, _state) do
    {:reply, :ok, %{previous_deck: nil, description: nil}}
  end

  @impl true
  def handle_call(:has_undo?, _from, %{previous_deck: nil} = state) do
    {:reply, false, state}
  end

  @impl true
  def handle_call(:has_undo?, _from, state) do
    {:reply, true, state}
  end
end
