defmodule MtgDeckBuilderWeb.DeckLive do
  use MtgDeckBuilderWeb, :live_view

  alias MtgDeckBuilder.Cards
  alias MtgDeckBuilder.Decks
  alias MtgDeckBuilder.Decks.{Deck, Stats, Validator}
  alias MtgDeckBuilder.AI.AnthropicClient
  alias MtgDeckBuilder.Chat.{CommandExecutor, CardResolver, ResponseFormatter, UndoServer}

  @impl true
  def mount(params, _session, socket) do
    {deck, format, flash_msg} =
      if params["load_sample"] == "true" do
        case load_sample_deck("reanimator_4c") do
          {:ok, sample_deck} ->
            {sample_deck, sample_deck.format, "Loaded 4c Reanimator sample deck"}

          {:error, _reason} ->
            {Deck.new(:modern), :modern, nil}
        end
      else
        {Deck.new(:modern), :modern, nil}
      end

    socket =
      socket
      |> assign(:search_query, "")
      |> assign(:search_results, [])
      |> assign(:search_loading, false)
      |> assign(:format, format)
      |> assign(:deck, deck)
      |> assign(:stats, Stats.calculate(deck))
      |> assign(:validation_errors, Validator.get_errors(deck))
      |> assign(:editing_name, false)
      |> assign(:page_title, "Deck Editor")
      # Chat assigns
      |> assign(:chat_messages, [])
      |> assign(:chat_input, "")
      |> assign(:chat_processing, false)
      |> assign(:disambiguation_options, nil)

    socket = if flash_msg, do: put_flash(socket, :info, flash_msg), else: socket

    {:ok, socket}
  end

  @impl true
  def handle_event("search_cards", %{"query" => query}, socket) when byte_size(query) < 2 do
    {:noreply, assign(socket, search_results: [], search_query: query)}
  end

  def handle_event("clear_search", _params, socket) do
    {:noreply, assign(socket, search_results: [], search_query: "")}
  end

  def handle_event("keydown", %{"key" => "Escape"}, socket) do
    {:noreply, assign(socket, search_results: [], search_query: "")}
  end

  def handle_event("keydown", %{"key" => "/"}, socket) do
    {:noreply, push_event(socket, "focus_chat", %{})}
  end

  def handle_event("keydown", _params, socket), do: {:noreply, socket}

  def handle_event("search_cards", %{"query" => query}, socket) do
    format = socket.assigns.format
    results = Cards.search(query, format: format, limit: 50)

    {:noreply,
     socket
     |> assign(:search_query, query)
     |> assign(:search_results, results)
     |> assign(:search_loading, false)}
  end

  def handle_event("change_format", params, socket) do
    format = params["format"]
    format_atom = String.to_existing_atom(format)

    # Re-run search with new format if there's a query
    socket =
      if socket.assigns.search_query != "" do
        results = Cards.search(socket.assigns.search_query, format: format_atom, limit: 50)
        assign(socket, :search_results, results)
      else
        socket
      end

    # Move illegal cards to removed
    {updated_deck, count_moved} = Decks.move_illegal_to_removed(socket.assigns.deck, format_atom)

    socket =
      if count_moved > 0 do
        put_flash(socket, :info, "#{count_moved} card(s) moved to Staging Area (not legal in #{format})")
      else
        socket
      end

    {:noreply,
     socket
     |> assign(:format, format_atom)
     |> assign(:deck, updated_deck)
     |> sync_deck()}
  end

  def handle_event("restore_card", %{"scryfall_id" => scryfall_id, "board" => board}, socket) do
    board_atom = String.to_existing_atom(board)

    case Decks.restore_card(socket.assigns.deck, scryfall_id, board_atom) do
      {:ok, updated_deck} ->
        {:noreply, socket |> assign(:deck, updated_deck) |> sync_deck()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, reason)}
    end
  end

  def handle_event("add_card", %{"scryfall_id" => scryfall_id, "board" => board}, socket) do
    board_atom = String.to_existing_atom(board)
    deck = socket.assigns.deck

    case Decks.add_card(deck, scryfall_id, board_atom, 1) do
      {:ok, updated_deck} ->
        {:noreply, socket |> assign(:deck, updated_deck) |> sync_deck()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, reason)}
    end
  end

  def handle_event("remove_card", %{"scryfall_id" => scryfall_id, "board" => board}, socket) do
    board_atom = String.to_existing_atom(board)
    updated_deck = Decks.remove_card(socket.assigns.deck, scryfall_id, board_atom)
    {:noreply, socket |> assign(:deck, updated_deck) |> sync_deck()}
  end

  def handle_event(
        "update_quantity",
        %{"scryfall_id" => scryfall_id, "board" => board, "delta" => delta},
        socket
      ) do
    board_atom = String.to_existing_atom(board)
    delta_int = String.to_integer(delta)

    case Decks.update_quantity(socket.assigns.deck, scryfall_id, board_atom, delta_int) do
      {:ok, updated_deck} ->
        {:noreply, socket |> assign(:deck, updated_deck) |> sync_deck()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, reason)}
    end
  end

  def handle_event("move_card", %{"scryfall_id" => scryfall_id, "from" => from, "to" => to}, socket) do
    from_atom = String.to_existing_atom(from)
    to_atom = String.to_existing_atom(to)

    case Decks.move_card(socket.assigns.deck, scryfall_id, from_atom, to_atom) do
      {:ok, updated_deck} ->
        {:noreply, socket |> assign(:deck, updated_deck) |> sync_deck()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, reason)}
    end
  end

  def handle_event("move_to_staging", %{"scryfall_id" => scryfall_id, "board" => board}, socket) do
    board_atom = String.to_existing_atom(board)

    case Decks.move_to_staging(socket.assigns.deck, scryfall_id, board_atom) do
      {:ok, updated_deck} ->
        {:noreply, socket |> assign(:deck, updated_deck) |> sync_deck()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, reason)}
    end
  end

  def handle_event("remove_from_staging", %{"scryfall_id" => scryfall_id}, socket) do
    updated_deck = Decks.remove_from_staging(socket.assigns.deck, scryfall_id)
    {:noreply, socket |> assign(:deck, updated_deck) |> sync_deck()}
  end

  def handle_event("clear_board", %{"board" => board}, socket) do
    board_atom = String.to_existing_atom(board)
    updated_deck = Decks.clear_board(socket.assigns.deck, board_atom)

    {:noreply,
     socket
     |> assign(:deck, updated_deck)
     |> assign(:stats, Stats.calculate(updated_deck))
     |> sync_deck()}
  end

  def handle_event("load_sample_deck", _params, socket) do
    case load_sample_deck("reanimator_4c") do
      {:ok, deck} ->
        {:noreply,
         socket
         |> assign(:deck, deck)
         |> assign(:format, deck.format)
         |> assign(:stats, Stats.calculate(deck))
         |> sync_deck()
         |> put_flash(:info, "Loaded 4c Reanimator sample deck")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to load sample deck: #{reason}")}
    end
  end

  def handle_event("load_deck", %{"deck_json" => deck_json}, socket) when is_binary(deck_json) do
    case Jason.decode(deck_json) do
      {:ok, data} ->
        deck = decode_deck(data)
        format = deck.format

        {:noreply,
         socket
         |> assign(:deck, deck)
         |> assign(:format, format)
         |> assign(:stats, Stats.calculate(deck))
         |> assign(:validation_errors, Validator.get_errors(deck))}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  def handle_event("load_deck", _params, socket), do: {:noreply, socket}

  def handle_event("edit_name", _params, socket) do
    {:noreply, assign(socket, :editing_name, true)}
  end

  def handle_event("save_name", %{"name" => name}, socket) do
    name = String.trim(name)
    name = if name == "", do: "New Deck", else: name

    updated_deck = %{socket.assigns.deck | name: name, updated_at: DateTime.utc_now() |> DateTime.to_iso8601()}

    {:noreply,
     socket
     |> assign(:deck, updated_deck)
     |> assign(:editing_name, false)
     |> sync_deck()}
  end

  def handle_event("cancel_edit_name", _params, socket) do
    {:noreply, assign(socket, :editing_name, false)}
  end

  # Chat event handlers

  def handle_event("submit_command", %{"command" => ""}, socket), do: {:noreply, socket}

  def handle_event("submit_command", %{"command" => command}, socket) do
    command = String.trim(command)
    if command == "", do: {:noreply, socket}

    # Check if this is a disambiguation selection (number or card name)
    case try_disambiguation_selection(command, socket.assigns.disambiguation_options) do
      {:ok, index} ->
        # User typed a number or card name matching disambiguation options
        handle_event("select_card", %{"index" => Integer.to_string(index)}, socket)

      :not_disambiguation ->
        # Normal command processing
        user_message = %{role: "user", content: command, timestamp: DateTime.utc_now()}
        messages = socket.assigns.chat_messages ++ [user_message]

        socket =
          socket
          |> assign(:chat_messages, messages)
          |> assign(:chat_input, "")
          |> assign(:chat_processing, true)
          |> assign(:disambiguation_options, nil)
          |> push_event("command_sent", %{command: command})

        # Process command asynchronously
        send(self(), {:process_command, command})

        {:noreply, sync_chat(socket)}
    end
  end

  def handle_event("select_card", %{"index" => index_str}, socket) do
    index = String.to_integer(index_str) - 1
    options = socket.assigns.disambiguation_options

    case Enum.at(options.cards, index) do
      nil ->
        {:noreply, add_assistant_message(socket, "Invalid selection. Please try again.")}

      card ->
        # Remember this selection for future
        CardResolver.remember_selection(options.original_name, card)

        # Re-execute the original command with the resolved card
        socket = assign(socket, :disambiguation_options, nil)
        send(self(), {:execute_with_card, options.original_command, card})
        {:noreply, socket}
    end
  end

  def handle_event("load_chat", %{"messages" => messages}, socket) when is_list(messages) do
    decoded_messages =
      Enum.map(messages, fn msg ->
        %{
          role: msg["role"] || "user",
          content: msg["content"] || "",
          timestamp: msg["timestamp"]
        }
      end)

    {:noreply, assign(socket, :chat_messages, decoded_messages)}
  end

  def handle_event("load_chat", _params, socket), do: {:noreply, socket}

  def handle_event("focus_chat_shortcut", _params, socket) do
    {:noreply, push_event(socket, "focus_chat", %{})}
  end

  @impl true
  def handle_info({:process_command, command}, socket) do
    socket = process_chat_command(command, socket)
    {:noreply, socket}
  end

  def handle_info({:execute_with_card, command, card}, socket) do
    # Re-parse and execute with the specific card
    deck_card_names = get_deck_card_names(socket.assigns.deck)

    case AnthropicClient.parse_command(command, deck_card_names: deck_card_names) do
      {:ok, parsed_cmd} ->
        execute_command_with_card(parsed_cmd, card, socket)

      {:error, reason} ->
        socket =
          socket
          |> assign(:chat_processing, false)
          |> add_assistant_message("Error: #{reason}")

        {:noreply, sync_chat(socket)}
    end
  end

  defp process_chat_command(command, socket) do
    deck_card_names = get_deck_card_names(socket.assigns.deck)

    case AnthropicClient.parse_command(command, deck_card_names: deck_card_names) do
      {:ok, parsed_cmd} ->
        execute_parsed_command(parsed_cmd, command, socket)

      {:error, _reason} ->
        socket
        |> assign(:chat_processing, false)
        |> add_assistant_message(ResponseFormatter.format_error(:api_unavailable, %{}))
        |> sync_chat()
    end
  end

  defp get_deck_card_names(deck) do
    mainboard_names = Enum.map(deck.mainboard, & &1.name)
    sideboard_names = Enum.map(deck.sideboard, & &1.name)
    staging_names = Enum.map(deck.removed_cards || [], & &1.name)
    Enum.uniq(mainboard_names ++ sideboard_names ++ staging_names)
  end

  defp execute_parsed_command(parsed_cmd, original_command, socket) do
    deck = socket.assigns.deck

    # Save undo state before modification (for modifying actions)
    if parsed_cmd.action in [:add, :remove, :set, :move] do
      description = "#{parsed_cmd.action} #{parsed_cmd.quantity || 1}x #{parsed_cmd.card_name}"
      UndoServer.save_state(deck, description)
    end

    case CommandExecutor.execute(parsed_cmd, deck) do
      {:ok, updated_deck, message} ->
        socket
        |> assign(:deck, updated_deck)
        |> assign(:chat_processing, false)
        |> add_assistant_message(message)
        |> sync_deck()
        |> sync_chat()

      {:error, message} ->
        socket
        |> assign(:chat_processing, false)
        |> add_assistant_message(message)
        |> sync_chat()

      {:disambiguation, cards} ->
        disambiguation_msg = ResponseFormatter.format_disambiguation(cards)

        socket
        |> assign(:chat_processing, false)
        |> assign(:disambiguation_options, %{
          cards: cards,
          original_command: original_command,
          original_name: parsed_cmd.card_name
        })
        |> add_assistant_message(disambiguation_msg)
        |> sync_chat()

      {:undo_requested, _deck} ->
        handle_undo(socket)
    end
  end

  defp execute_command_with_card(parsed_cmd, card, socket) do
    deck = socket.assigns.deck

    # Save undo state
    if parsed_cmd.action in [:add, :remove, :set, :move] do
      description = "#{parsed_cmd.action} #{parsed_cmd.quantity || 1}x #{card.name}"
      UndoServer.save_state(deck, description)
    end

    # Execute based on action type with the specific card
    result =
      case parsed_cmd.action do
        :add ->
          board = parsed_cmd.target_board || :mainboard
          qty = parsed_cmd.quantity || 1

          case Decks.add_card(deck, card.scryfall_id, board, qty) do
            {:ok, updated_deck} ->
              msg = ResponseFormatter.format_success(:add, %{card: card, quantity: qty, board: board})
              {:ok, updated_deck, msg}

            {:error, reason} ->
              {:error, reason}
          end

        :remove ->
          board = parsed_cmd.source_board || :mainboard
          qty = parsed_cmd.quantity

          board_list = Map.get(deck, board, [])

          case Enum.find(board_list, fn c -> c.scryfall_id == card.scryfall_id end) do
            nil ->
              {:error, ResponseFormatter.format_error(:card_not_in_deck, %{name: card.name, board: board})}

            existing ->
              remove_qty = if is_nil(qty) or qty >= existing.quantity, do: existing.quantity, else: qty

              if remove_qty >= existing.quantity do
                updated_deck = Decks.remove_card(deck, card.scryfall_id, board)
                msg = ResponseFormatter.format_success(:remove, %{card: card, quantity: remove_qty, board: board})
                {:ok, updated_deck, msg}
              else
                case Decks.update_quantity(deck, card.scryfall_id, board, -remove_qty) do
                  {:ok, updated_deck} ->
                    msg = ResponseFormatter.format_success(:remove, %{card: card, quantity: remove_qty, board: board})
                    {:ok, updated_deck, msg}

                  {:error, reason} ->
                    {:error, reason}
                end
              end
          end

        _ ->
          # Other actions, re-execute normally
          CommandExecutor.execute(parsed_cmd, deck)
      end

    case result do
      {:ok, updated_deck, message} ->
        socket =
          socket
          |> assign(:deck, updated_deck)
          |> assign(:chat_processing, false)
          |> add_assistant_message(message)
          |> sync_deck()
          |> sync_chat()

        {:noreply, socket}

      {:error, message} ->
        socket =
          socket
          |> assign(:chat_processing, false)
          |> add_assistant_message(message)
          |> sync_chat()

        {:noreply, socket}
    end
  end

  defp handle_undo(socket) do
    case UndoServer.undo() do
      {:ok, previous_deck, description} ->
        msg = ResponseFormatter.format_success(:undo, %{description: description})

        socket
        |> assign(:deck, previous_deck)
        |> assign(:chat_processing, false)
        |> add_assistant_message(msg)
        |> sync_deck()
        |> sync_chat()

      {:error, :nothing_to_undo} ->
        msg = ResponseFormatter.format_error(:nothing_to_undo, %{})

        socket
        |> assign(:chat_processing, false)
        |> add_assistant_message(msg)
        |> sync_chat()
    end
  end

  defp add_assistant_message(socket, content) do
    message = %{role: "assistant", content: content, timestamp: DateTime.utc_now()}
    messages = socket.assigns.chat_messages ++ [message]
    assign(socket, :chat_messages, messages)
  end

  defp sync_chat(socket) do
    messages =
      Enum.map(socket.assigns.chat_messages, fn msg ->
        %{
          role: msg.role,
          content: msg.content,
          timestamp: format_timestamp(msg.timestamp)
        }
      end)

    push_event(socket, "sync_chat", %{messages: messages})
  end

  defp format_timestamp(nil), do: nil
  defp format_timestamp(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp format_timestamp(str) when is_binary(str), do: str

  # Check if user input is a disambiguation selection (number or card name)
  defp try_disambiguation_selection(_input, nil), do: :not_disambiguation

  defp try_disambiguation_selection(input, %{cards: cards}) do
    input_lower = String.downcase(input)

    # Try parsing as a number first
    case Integer.parse(input) do
      {num, ""} when num >= 1 and num <= length(cards) ->
        {:ok, num}

      _ ->
        # Try matching card name (case insensitive, partial match)
        case Enum.find_index(cards, fn card ->
               String.downcase(card.name) == input_lower or
                 String.contains?(String.downcase(card.name), input_lower)
             end) do
          nil -> :not_disambiguation
          index -> {:ok, index + 1}
        end
    end
  end

  # Load a sample deck from priv/sample_decks
  defp load_sample_deck(name) do
    path = Application.app_dir(:mtg_deck_builder, "priv/sample_decks/#{name}.json")

    case File.read(path) do
      {:ok, json} ->
        case Jason.decode(json) do
          {:ok, data} -> {:ok, decode_deck(data)}
          {:error, _} -> {:error, "Invalid JSON"}
        end

      {:error, _} ->
        {:error, "Sample deck not found"}
    end
  end

  # Helper to sync deck to localStorage and recalculate stats
  defp sync_deck(socket) do
    deck = socket.assigns.deck
    deck_json = Jason.encode!(deck)

    socket
    |> assign(:stats, Stats.calculate(deck))
    |> assign(:validation_errors, Validator.get_errors(deck))
    |> push_event("sync_deck", %{deck_json: deck_json})
  end

  # Decode deck from JSON map to struct
  defp decode_deck(data) when is_map(data) do
    mainboard =
      (data["mainboard"] || [])
      |> Enum.map(&decode_deck_card/1)

    sideboard =
      (data["sideboard"] || [])
      |> Enum.map(&decode_deck_card/1)

    format =
      case data["format"] do
        f when is_binary(f) -> String.to_existing_atom(f)
        f when is_atom(f) -> f
        _ -> :modern
      end

    removed_cards =
      (data["removed_cards"] || [])
      |> Enum.map(&decode_removed_card/1)

    %Deck{
      id: data["id"] || Ecto.UUID.generate(),
      name: data["name"] || "New Deck",
      format: format,
      mainboard: mainboard,
      sideboard: sideboard,
      removed_cards: removed_cards,
      created_at: data["created_at"],
      updated_at: data["updated_at"]
    }
  end

  defp decode_deck_card(data) when is_map(data) do
    %MtgDeckBuilder.Decks.DeckCard{
      scryfall_id: data["scryfall_id"],
      name: data["name"],
      quantity: data["quantity"] || 1,
      mana_cost: data["mana_cost"],
      cmc: data["cmc"] || 0.0,
      type_line: data["type_line"],
      oracle_text: data["oracle_text"],
      colors: data["colors"] || [],
      price: data["price"],
      is_basic_land: data["is_basic_land"] || false
    }
  end

  defp decode_removed_card(data) when is_map(data) do
    original_board =
      case data["original_board"] do
        "mainboard" -> :mainboard
        "sideboard" -> :sideboard
        b when is_atom(b) -> b
        _ -> :mainboard
      end

    %MtgDeckBuilder.Decks.RemovedCard{
      scryfall_id: data["scryfall_id"],
      name: data["name"],
      quantity: data["quantity"] || 1,
      mana_cost: data["mana_cost"],
      cmc: data["cmc"] || 0.0,
      type_line: data["type_line"],
      oracle_text: data["oracle_text"],
      colors: data["colors"] || [],
      price: data["price"],
      is_basic_land: data["is_basic_land"] || false,
      removal_reason: data["removal_reason"],
      original_board: original_board
    }
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="deck-container" phx-hook="DeckStorage" phx-window-keydown="keydown" class="px-4 py-6">
      <div class="flex flex-col lg:flex-row gap-6">
        <!-- Left Column: Search + Chat -->
        <div class="w-full lg:w-80 xl:w-96 flex-shrink-0 flex flex-col gap-4">
          <!-- Search Panel -->
          <div class="bg-slate-800 rounded-lg p-4 border border-slate-700">
            <h2 class="text-lg font-semibold text-amber-400 mb-4">Card Search</h2>

            <form phx-submit="search_cards" phx-change="search_cards" class="mb-4">
              <input
                type="text"
                name="query"
                value={@search_query}
                placeholder="Search cards..."
                autocomplete="off"
                phx-debounce="300"
                class="w-full bg-slate-700 border border-slate-600 rounded-lg px-4 py-2 text-slate-100 placeholder-slate-400 focus:outline-none focus:ring-2 focus:ring-amber-400 focus:border-transparent"
              />
            </form>

            <form phx-change="change_format" class="mb-4">
              <label class="block text-sm text-slate-400 mb-1">Format</label>
              <select
                name="format"
                class="w-full bg-slate-700 border border-slate-600 rounded-lg px-3 py-2 text-slate-100 focus:outline-none focus:ring-2 focus:ring-amber-400"
              >
                <option value="modern" selected={@format == :modern}>Modern</option>
                <option value="standard" selected={@format == :standard}>Standard</option>
                <option value="pioneer" selected={@format == :pioneer}>Pioneer</option>
                <option value="legacy" selected={@format == :legacy}>Legacy</option>
                <option value="vintage" selected={@format == :vintage}>Vintage</option>
                <option value="pauper" selected={@format == :pauper}>Pauper</option>
              </select>
            </form>

            <!-- Search Results -->
            <div class="space-y-2 max-h-[35vh] overflow-y-auto">
              <%= if @search_loading do %>
                <!-- Loading Skeleton -->
                <div class="space-y-2">
                  <%= for _i <- 1..3 do %>
                    <div class="bg-slate-700 rounded-lg p-3 animate-pulse">
                      <div class="flex items-start justify-between">
                        <div class="flex-1">
                          <div class="h-4 bg-slate-600 rounded w-3/4 mb-2"></div>
                          <div class="h-3 bg-slate-600 rounded w-1/2"></div>
                        </div>
                        <div class="flex flex-col gap-1 ml-2">
                          <div class="h-6 w-12 bg-slate-600 rounded"></div>
                          <div class="h-6 w-12 bg-slate-600 rounded"></div>
                        </div>
                      </div>
                    </div>
                  <% end %>
                </div>
              <% end %>

              <%= if @search_query != "" and Enum.empty?(@search_results) and not @search_loading do %>
                <div class="text-center py-4 text-slate-400">
                  No cards found matching "{@search_query}"
                </div>
              <% end %>

              <%= for card <- @search_results do %>
                <.card_result card={card} />
              <% end %>
            </div>
          </div>

          <!-- Chat Panel -->
          <.chat_panel
            messages={@chat_messages}
            processing={@chat_processing}
            disambiguation_options={@disambiguation_options}
          />
        </div>

        <!-- Deck Panel -->
        <div class="flex-1 min-w-0">
          <div class="bg-slate-800 rounded-lg p-4 border border-slate-700">
            <div class="flex items-center justify-between mb-4">
              <%= if @editing_name do %>
                <form phx-submit="save_name" phx-click-away="cancel_edit_name" class="flex-1 mr-4">
                  <input
                    type="text"
                    name="name"
                    value={@deck.name}
                    autofocus
                    phx-mounted={JS.focus()}
                    class="bg-slate-700 border border-amber-400 rounded px-2 py-1 text-lg font-semibold text-amber-400 w-full max-w-xs focus:outline-none focus:ring-2 focus:ring-amber-400"
                  />
                </form>
              <% else %>
                <h2
                  class="text-lg font-semibold text-amber-400 cursor-pointer hover:text-amber-300 group flex items-center gap-2"
                  phx-click="edit_name"
                  title="Click to edit deck name"
                >
                  {@deck.name}
                  <span class="text-slate-500 group-hover:text-slate-400 text-sm">&#9998;</span>
                </h2>
              <% end %>
              <span class="text-sm text-slate-400 capitalize">{@format} Format</span>
            </div>

            <!-- Deck Validity Indicator -->
            <.deck_validity errors={@validation_errors} />

            <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
              <.board_list
                title="Mainboard"
                board="mainboard"
                cards={@deck.mainboard}
                count={Deck.mainboard_count(@deck)}
                max_count={60}
                empty_message="No cards yet - search and add some!"
              />

              <.board_list
                title="Sideboard"
                board="sideboard"
                cards={@deck.sideboard}
                count={Deck.sideboard_count(@deck)}
                max_count={15}
                empty_message="Add cards to sideboard"
              />

            <!-- Staging Area -->
              <div class="sm:col-span-2">
                <div class="flex items-center justify-between mb-2">
                  <h3 class="text-sm font-medium text-amber-400">
                    Staging Area ({length(@deck.removed_cards)} cards)
                  </h3>
                  <%= if length(@deck.removed_cards) > 0 do %>
                    <button
                      type="button"
                      phx-click="clear_board"
                      phx-value-board="staging"
                      class="text-xs text-slate-500 hover:text-red-400"
                      data-confirm="Clear all cards from Staging Area?"
                    >
                      Clear
                    </button>
                  <% end %>
                </div>
                <div class="bg-slate-900 rounded-lg p-3 border border-slate-700 min-h-[100px]">
                <%= if Enum.empty?(@deck.removed_cards) do %>
                  <p class="text-slate-500 text-sm text-center py-4">
                    Move cards here to consider later or when switching formats
                  </p>
                <% else %>
                  <div class="space-y-1">
                    <%= for card <- @deck.removed_cards do %>
                      <.removed_card card={card} format={@format} />
                    <% end %>
                  </div>
                <% end %>
                </div>
              </div>
            </div>

            <!-- Statistics Panel -->
            <div class="mt-4 pt-4 border-t border-slate-700">
              <h3 class="text-sm font-medium text-amber-400 mb-3">Deck Statistics</h3>
              <div class="grid grid-cols-2 md:grid-cols-4 gap-4">
                <!-- Mana Curve -->
                <div class="bg-slate-900 rounded-lg p-3 border border-slate-700">
                  <h4 class="text-xs font-medium text-slate-400 mb-2">Mana Curve</h4>
                  <div class="space-y-1">
                    <%= for cmc <- [0, 1, 2, 3, 4, 5, "6+"] do %>
                      <.mana_curve_bar cmc={cmc} count={@stats.mana_curve[cmc]} max={max_curve_count(@stats.mana_curve)} />
                    <% end %>
                  </div>
                </div>

                <!-- Color Distribution -->
                <div class="bg-slate-900 rounded-lg p-3 border border-slate-700">
                  <h4 class="text-xs font-medium text-slate-400 mb-2">Colors</h4>
                  <div class="space-y-1 text-sm">
                    <%= for {color, count} <- Enum.filter(@stats.color_distribution, fn {_, c} -> c > 0 end) do %>
                      <div class="flex justify-between">
                        <span class={color_class(color)}>{color_name(color)}</span>
                        <span class="text-slate-300">{count}</span>
                      </div>
                    <% end %>
                    <%= if Enum.all?(@stats.color_distribution, fn {_, c} -> c == 0 end) do %>
                      <span class="text-slate-500 text-xs">No cards yet</span>
                    <% end %>
                  </div>
                </div>

                <!-- Type Breakdown -->
                <div class="bg-slate-900 rounded-lg p-3 border border-slate-700">
                  <h4 class="text-xs font-medium text-slate-400 mb-2">Card Types</h4>
                  <div class="space-y-1 text-sm">
                    <%= for {type, count} <- Enum.filter(@stats.type_breakdown, fn {_, c} -> c > 0 end) do %>
                      <div class="flex justify-between">
                        <span class="text-slate-300 capitalize">{type}</span>
                        <span class="text-slate-300">{count}</span>
                      </div>
                    <% end %>
                    <%= if Enum.all?(@stats.type_breakdown, fn {_, c} -> c == 0 end) do %>
                      <span class="text-slate-500 text-xs">No cards yet</span>
                    <% end %>
                  </div>
                </div>

                <!-- Summary -->
                <div class="bg-slate-900 rounded-lg p-3 border border-slate-700">
                  <h4 class="text-xs font-medium text-slate-400 mb-2">Summary</h4>
                  <div class="space-y-1 text-sm">
                    <div class="flex justify-between">
                      <span class="text-slate-400">Avg. MV</span>
                      <span class="text-amber-400">{@stats.average_mana_value}</span>
                    </div>
                    <div class="flex justify-between">
                      <span class="text-slate-400">Total Price</span>
                      <span class="text-green-400">${Float.round(@stats.total_price, 2)}</span>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :messages, :list, required: true
  attr :processing, :boolean, required: true
  attr :disambiguation_options, :any, required: true

  defp chat_panel(assigns) do
    ~H"""
    <div id="chat-panel" phx-hook="ChatInput" class="bg-slate-800 rounded-lg border border-slate-700 flex flex-col">
      <div class="p-3 border-b border-slate-700">
        <div class="flex items-center justify-between">
          <h2 class="text-sm font-semibold text-amber-400">Chat Commands</h2>
          <span class="text-xs text-slate-500">/</span>
        </div>
      </div>

      <!-- Messages -->
      <div class="p-3 space-y-2 max-h-40 overflow-y-auto flex-1" id="chat-messages" phx-hook="ChatScroll">
        <%= if Enum.empty?(@messages) do %>
          <div class="text-slate-500 text-xs text-center py-2">
            <p>"add 4 lightning bolt"</p>
            <p class="text-slate-600 mt-1">Type "help" for commands</p>
          </div>
        <% else %>
          <%= for message <- @messages do %>
            <.chat_message message={message} />
          <% end %>
        <% end %>

        <%= if @processing do %>
          <div class="flex items-center gap-2 text-slate-400 text-xs">
            <span class="animate-pulse">...</span>
            <span>Processing</span>
          </div>
        <% end %>
      </div>

      <!-- Disambiguation Options -->
      <%= if @disambiguation_options do %>
        <div class="px-3 pb-3">
          <div class="bg-slate-900 rounded p-2 border border-amber-500/50">
            <p class="text-xs text-slate-300 mb-1">Select:</p>
            <div class="flex flex-col gap-1">
              <%= for {card, idx} <- Enum.with_index(@disambiguation_options.cards, 1) do %>
                <button
                  type="button"
                  phx-click="select_card"
                  phx-value-index={idx}
                  class="bg-slate-700 hover:bg-slate-600 text-slate-100 px-2 py-1 rounded text-xs text-left"
                >
                  {idx}. {card.name}
                </button>
              <% end %>
            </div>
          </div>
        </div>
      <% end %>

      <!-- Input -->
      <div class="p-3 border-t border-slate-700">
        <form phx-submit="submit_command" class="flex gap-2">
          <input
            type="text"
            name="command"
            placeholder="add 4 lightning bolt..."
            autocomplete="off"
            disabled={@processing}
            class="flex-1 bg-slate-700 border border-slate-600 rounded px-3 py-1.5 text-sm text-slate-100 placeholder-slate-400 focus:outline-none focus:ring-2 focus:ring-amber-400 focus:border-transparent disabled:opacity-50"
          />
          <button
            type="submit"
            disabled={@processing}
            class="bg-amber-500 hover:bg-amber-600 disabled:bg-amber-500/50 text-slate-900 font-medium px-3 py-1.5 rounded text-sm"
          >
            Send
          </button>
        </form>
      </div>
    </div>
    """
  end

  attr :message, :map, required: true

  defp chat_message(assigns) do
    ~H"""
    <div class={[
      "rounded p-2 text-xs",
      if(@message.role == "user", do: "bg-slate-700 text-slate-100", else: "bg-slate-900 text-slate-300")
    ]}>
      <span class={[
        "font-medium",
        if(@message.role == "user", do: "text-amber-400", else: "text-slate-500")
      ]}>
        {if @message.role == "user", do: "You:", else: "Bot:"}
      </span>
      <span class="ml-1 whitespace-pre-wrap">{@message.content}</span>
    </div>
    """
  end

  attr :errors, :list, required: true

  defp deck_validity(assigns) do
    ~H"""
    <div class="mb-4">
      <%= if Enum.empty?(@errors) do %>
        <div class="inline-flex items-center gap-2 bg-green-900/50 border border-green-700 text-green-400 px-3 py-1.5 rounded-lg text-sm">
          <span class="text-green-400">&#10003;</span>
          <span>Deck is legal</span>
        </div>
      <% else %>
        <div class="bg-red-900/30 border border-red-700 rounded-lg p-3">
          <div class="flex items-center gap-2 text-red-400 font-medium text-sm mb-2">
            <span>&#10007;</span>
            <span>Deck has {length(@errors)} issue(s)</span>
          </div>
          <ul class="text-sm text-red-300 space-y-1 ml-5 list-disc">
            <%= for error <- @errors do %>
              <li>{error}</li>
            <% end %>
          </ul>
        </div>
      <% end %>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :board, :string, required: true
  attr :cards, :list, required: true
  attr :count, :integer, required: true
  attr :max_count, :integer, required: true
  attr :empty_message, :string, required: true

  defp board_list(assigns) do
    ~H"""
    <div>
      <div class="flex items-center justify-between mb-2">
        <h3 class="text-sm font-medium text-slate-300">
          {@title} ({@count}/{@max_count} cards)
        </h3>
        <%= if @count > 0 do %>
          <button
            type="button"
            phx-click="clear_board"
            phx-value-board={@board}
            class="text-xs text-slate-500 hover:text-red-400"
            data-confirm={"Clear all cards from #{@title}?"}
          >
            Clear
          </button>
        <% end %>
      </div>
      <div class="bg-slate-900 rounded-lg p-3 min-h-[200px] border border-slate-700">
        <%= if Enum.empty?(@cards) do %>
          <p class="text-slate-500 text-sm text-center py-8">
            {@empty_message}
          </p>
        <% else %>
          <div class="space-y-3">
            <%= for {type, cards} <- group_cards_by_type(@cards) do %>
              <div>
                <h4 class="text-xs font-medium text-slate-500 uppercase tracking-wide mb-1">
                  {type} ({type_count(cards)})
                </h4>
                <div class="space-y-1">
                  <%= for card <- cards do %>
                    <.deck_card card={card} board={@board} />
                  <% end %>
                </div>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  attr :card, MtgDeckBuilder.Cards.Card, required: true

  defp card_result(assigns) do
    ~H"""
    <details class="bg-slate-700 rounded-lg group">
      <summary class="flex items-start justify-between p-3 cursor-pointer hover:bg-slate-600 rounded-lg list-none">
        <div class="flex-1 min-w-0">
          <div class="flex items-center gap-2">
            <span class="font-medium text-slate-100 truncate">{@card.name}</span>
            <span class="text-amber-400 text-sm whitespace-nowrap">
              {format_mana_cost(@card.mana_cost)}
            </span>
          </div>
          <div class="text-xs text-slate-400 truncate">{@card.type_line}</div>
          <%= if @card.prices["usd"] do %>
            <div class="text-xs text-green-400 mt-1">${@card.prices["usd"]}</div>
          <% end %>
        </div>
        <div class="flex flex-col gap-1 ml-2">
          <button
            type="button"
            phx-click="add_card"
            phx-value-scryfall_id={@card.scryfall_id}
            phx-value-board="mainboard"
            class="text-xs bg-amber-500 hover:bg-amber-600 text-slate-900 px-2 py-1 rounded font-medium"
          >
            +Main
          </button>
          <button
            type="button"
            phx-click="add_card"
            phx-value-scryfall_id={@card.scryfall_id}
            phx-value-board="sideboard"
            class="text-xs bg-slate-500 hover:bg-slate-400 text-slate-100 px-2 py-1 rounded font-medium"
          >
            +Side
          </button>
        </div>
      </summary>
      <div class="px-3 pb-3 pt-1 border-t border-slate-600 text-sm">
        <%= if @card.oracle_text do %>
          <div class="text-slate-300 whitespace-pre-wrap mb-2">{@card.oracle_text}</div>
        <% end %>
        <div class="text-xs text-slate-500 space-y-1">
          <%= if @card.rarity do %>
            <div>Rarity: <span class="text-slate-400 capitalize">{@card.rarity}</span></div>
          <% end %>
          <%= if @card.set_code do %>
            <div>Set: <span class="text-slate-400 uppercase">{@card.set_code}</span></div>
          <% end %>
          <%= if @card.legalities && map_size(@card.legalities) > 0 do %>
            <div class="mt-2 pt-2 border-t border-slate-600">
              <div class="font-medium text-slate-400 mb-1">Legalities:</div>
              <div class="grid grid-cols-2 gap-x-4 gap-y-0.5">
                <%= for {format, status} <- Enum.sort(@card.legalities) do %>
                  <div class="flex justify-between">
                    <span class="capitalize">{format}</span>
                    <span class={legality_class(status)}>{status}</span>
                  </div>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </details>
    """
  end

  attr :card, :map, required: true
  attr :board, :string, required: true

  defp deck_card(assigns) do
    # Fetch full card data for complete details
    full_card = MtgDeckBuilder.Cards.get_by_scryfall_id(assigns.card.scryfall_id)
    assigns = assign(assigns, :full_card, full_card)

    ~H"""
    <details class="bg-slate-800 rounded group">
      <summary class="flex items-center justify-between px-2 py-1.5 cursor-pointer hover:bg-slate-700 rounded list-none">
        <div class="flex items-center gap-2 min-w-0 flex-1">
          <span class="text-amber-400 font-medium text-sm w-6">{@card.quantity}x</span>
          <span class="text-slate-100 text-sm truncate">{@card.name}</span>
          <span class="text-slate-400 text-xs whitespace-nowrap">{format_mana_cost(@card.mana_cost)}</span>
        </div>
        <div class="flex items-center gap-1">
          <button
            type="button"
            phx-click="update_quantity"
            phx-value-scryfall_id={@card.scryfall_id}
            phx-value-board={@board}
            phx-value-delta="-1"
            class="text-slate-400 hover:text-red-400 px-1"
          >
            -
          </button>
          <button
            type="button"
            phx-click="update_quantity"
            phx-value-scryfall_id={@card.scryfall_id}
            phx-value-board={@board}
            phx-value-delta="1"
            class="text-slate-400 hover:text-green-400 px-1"
          >
            +
          </button>
          <button
            type="button"
            phx-click="move_card"
            phx-value-scryfall_id={@card.scryfall_id}
            phx-value-from={@board}
            phx-value-to={if @board == "mainboard", do: "sideboard", else: "mainboard"}
            class="text-slate-400 hover:text-amber-400 px-1 text-xs"
            title={if @board == "mainboard", do: "Move to sideboard", else: "Move to mainboard"}
          >
            ↔
          </button>
          <button
            type="button"
            phx-click="move_to_staging"
            phx-value-scryfall_id={@card.scryfall_id}
            phx-value-board={@board}
            class="text-slate-400 hover:text-amber-400 px-1"
            title="Move to staging area"
          >
            ||
          </button>
          <button
            type="button"
            phx-click="remove_card"
            phx-value-scryfall_id={@card.scryfall_id}
            phx-value-board={@board}
            class="text-slate-400 hover:text-red-400 px-1"
            title="Remove from deck"
          >
            ×
          </button>
        </div>
      </summary>
      <%= if @full_card do %>
        <div class="px-3 pb-2 pt-1 border-t border-slate-700 text-xs space-y-1">
          <div class="text-slate-400">{@full_card.type_line}</div>
          <%= if @full_card.oracle_text do %>
            <div class="text-slate-300 whitespace-pre-wrap">{@full_card.oracle_text}</div>
          <% end %>
          <%= if @full_card.prices["usd"] do %>
            <div class="text-green-400">${@full_card.prices["usd"]}</div>
          <% end %>
        </div>
      <% end %>
    </details>
    """
  end

  attr :card, :map, required: true
  attr :format, :atom, required: true

  defp removed_card(assigns) do
    # Fetch full card data for complete details and legality check
    full_card = MtgDeckBuilder.Cards.get_by_scryfall_id(assigns.card.scryfall_id)

    is_now_legal =
      case full_card do
        nil -> false
        card -> MtgDeckBuilder.Decks.Validator.legal_in_format?(card, assigns.format)
      end

    assigns =
      assigns
      |> assign(:is_now_legal, is_now_legal)
      |> assign(:full_card, full_card)

    ~H"""
    <details class={[
      "rounded group",
      if(@is_now_legal, do: "bg-green-900/30 border border-green-700", else: "bg-slate-800")
    ]}>
      <summary class="flex items-center justify-between px-2 py-1.5 cursor-pointer hover:bg-slate-700/50 rounded list-none">
        <div class="flex items-center gap-2 min-w-0 flex-1">
          <span class="text-amber-400 font-medium text-sm w-6">{@card.quantity}x</span>
          <span class="text-slate-100 text-sm truncate">{@card.name}</span>
          <span class="text-slate-400 text-xs whitespace-nowrap">{format_mana_cost(@card.mana_cost)}</span>
          <%= if @is_now_legal do %>
            <span class="text-green-400 text-xs">(now legal)</span>
          <% else %>
            <span class="text-slate-400 text-xs">({staging_reason(@card.removal_reason)})</span>
          <% end %>
        </div>
        <div class="flex items-center gap-1">
          <button
            type="button"
            phx-click="restore_card"
            phx-value-scryfall_id={@card.scryfall_id}
            phx-value-board="mainboard"
            class={[
              "text-xs px-2 py-0.5 rounded",
              if(@is_now_legal, do: "bg-green-600 hover:bg-green-500 text-white", else: "bg-slate-600 hover:bg-slate-500 text-slate-100")
            ]}
            title="Restore to mainboard"
          >
            +Main
          </button>
          <button
            type="button"
            phx-click="restore_card"
            phx-value-scryfall_id={@card.scryfall_id}
            phx-value-board="sideboard"
            class={[
              "text-xs px-2 py-0.5 rounded",
              if(@is_now_legal, do: "bg-green-600 hover:bg-green-500 text-white", else: "bg-slate-600 hover:bg-slate-500 text-slate-100")
            ]}
            title="Restore to sideboard"
          >
            +Side
          </button>
          <button
            type="button"
            phx-click="remove_from_staging"
            phx-value-scryfall_id={@card.scryfall_id}
            class="text-slate-400 hover:text-red-400 px-1"
            title="Remove from staging"
          >
            ×
          </button>
        </div>
      </summary>
      <%= if @full_card do %>
        <div class="px-3 pb-2 pt-1 border-t border-slate-700 text-xs space-y-1">
          <div class="text-slate-400">{@full_card.type_line}</div>
          <%= if @full_card.oracle_text do %>
            <div class="text-slate-300 whitespace-pre-wrap">{@full_card.oracle_text}</div>
          <% end %>
          <%= if @full_card.prices["usd"] do %>
            <div class="text-green-400">${@full_card.prices["usd"]}</div>
          <% end %>
        </div>
      <% end %>
    </details>
    """
  end

  attr :cmc, :any, required: true
  attr :count, :integer, required: true
  attr :max, :integer, required: true

  defp mana_curve_bar(assigns) do
    width_percent =
      if assigns.max > 0 do
        round(assigns.count / assigns.max * 100)
      else
        0
      end

    assigns = assign(assigns, :width_percent, width_percent)

    ~H"""
    <div class="flex items-center gap-1 text-xs">
      <span class="w-4 text-slate-400">{@cmc}</span>
      <div class="flex-1 h-3 bg-slate-700 rounded overflow-hidden">
        <div class="h-full bg-amber-500" style={"width: #{@width_percent}%"}></div>
      </div>
      <span class="w-4 text-right text-slate-300">{@count}</span>
    </div>
    """
  end

  defp max_curve_count(curve) do
    curve
    |> Map.values()
    |> Enum.max()
    |> max(1)
  end

  defp color_class("W"), do: "text-yellow-200"
  defp color_class("U"), do: "text-blue-400"
  defp color_class("B"), do: "text-purple-400"
  defp color_class("R"), do: "text-red-400"
  defp color_class("G"), do: "text-green-400"
  defp color_class("C"), do: "text-slate-400"
  defp color_class(_), do: "text-slate-300"

  defp color_name("W"), do: "White"
  defp color_name("U"), do: "Blue"
  defp color_name("B"), do: "Black"
  defp color_name("R"), do: "Red"
  defp color_name("G"), do: "Green"
  defp color_name("C"), do: "Colorless"
  defp color_name(c), do: c

  defp format_mana_cost(nil), do: ""
  defp format_mana_cost(cost), do: cost

  defp legality_class("legal"), do: "text-green-400"
  defp legality_class("not_legal"), do: "text-red-400"
  defp legality_class("banned"), do: "text-red-500 font-medium"
  defp legality_class("restricted"), do: "text-yellow-400"
  defp legality_class(_), do: "text-slate-400"

  defp staging_reason("Staged for later"), do: "staged"
  defp staging_reason(reason), do: reason

  # Card type ordering for display
  @type_order ["Creature", "Planeswalker", "Instant", "Sorcery", "Artifact", "Enchantment", "Land", "Other"]

  defp group_cards_by_type(cards) do
    cards
    |> Enum.group_by(&get_primary_type/1)
    |> Enum.sort_by(fn {type, _} -> Enum.find_index(@type_order, &(&1 == type)) || 99 end)
  end

  defp get_primary_type(card) do
    type_line = card.type_line || ""
    type_lower = String.downcase(type_line)

    cond do
      String.contains?(type_lower, "creature") -> "Creature"
      String.contains?(type_lower, "planeswalker") -> "Planeswalker"
      String.contains?(type_lower, "instant") -> "Instant"
      String.contains?(type_lower, "sorcery") -> "Sorcery"
      String.contains?(type_lower, "artifact") -> "Artifact"
      String.contains?(type_lower, "enchantment") -> "Enchantment"
      String.contains?(type_lower, "land") -> "Land"
      true -> "Other"
    end
  end

  defp type_count(cards) do
    Enum.reduce(cards, 0, fn card, acc -> acc + card.quantity end)
  end
end
