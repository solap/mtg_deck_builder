defmodule MtgDeckBuilder.AI.AgentRegistry do
  @moduledoc """
  GenServer that manages AI agent configurations with ETS caching.

  On startup, loads all agent configs from PostgreSQL into an ETS table
  for fast lookups. Updates are written through to the database and
  the cache is invalidated appropriately.

  ## Usage

      # Get an agent config
      AgentRegistry.get_agent("orchestrator")
      #=> %AgentConfig{agent_id: "orchestrator", model: "claude-sonnet-4-20250514", ...}

      # List all agents
      AgentRegistry.list_agents()
      #=> [%AgentConfig{...}, ...]

      # Update an agent
      AgentRegistry.update_agent("orchestrator", %{temperature: 0.5})
      #=> {:ok, %AgentConfig{temperature: 0.5, ...}}

      # Reset agent prompt to default
      AgentRegistry.reset_agent_prompt("orchestrator")
      #=> {:ok, %AgentConfig{system_prompt: <default>, ...}}
  """
  use GenServer

  alias MtgDeckBuilder.AI.AgentConfig
  alias MtgDeckBuilder.AI.ProviderConfig
  alias MtgDeckBuilder.Repo


  @table_name :agent_configs_cache
  @provider_table_name :provider_configs_cache

  # Client API

  @doc """
  Starts the AgentRegistry GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets an agent config by agent_id.
  Returns nil if not found.
  """
  def get_agent(agent_id) when is_binary(agent_id) do
    case :ets.lookup(@table_name, agent_id) do
      [{^agent_id, config}] -> config
      [] -> nil
    end
  end

  @doc """
  Gets an agent config by agent_id.
  Raises if not found.
  """
  def get_agent!(agent_id) when is_binary(agent_id) do
    case get_agent(agent_id) do
      nil -> raise "Agent config not found: #{agent_id}"
      config -> config
    end
  end

  @doc """
  Lists all agent configs from the cache.
  """
  def list_agents do
    @table_name
    |> :ets.tab2list()
    |> Enum.map(fn {_id, config} -> config end)
    |> Enum.sort_by(& &1.agent_id)
  end

  @doc """
  Lists only enabled agent configs.
  """
  def list_enabled_agents do
    list_agents()
    |> Enum.filter(& &1.enabled)
  end

  @doc """
  Updates an agent config with the given attributes.
  Updates both the database and the cache.
  """
  def update_agent(agent_id, attrs) when is_binary(agent_id) and is_map(attrs) do
    GenServer.call(__MODULE__, {:update_agent, agent_id, attrs})
  end

  @doc """
  Resets an agent's system_prompt to its default_prompt.
  """
  def reset_agent_prompt(agent_id) when is_binary(agent_id) do
    GenServer.call(__MODULE__, {:reset_prompt, agent_id})
  end

  @doc """
  Gets a provider config by provider name.
  Returns nil if not found.
  """
  def get_provider(provider) when is_binary(provider) do
    case :ets.lookup(@provider_table_name, provider) do
      [{^provider, config}] -> config
      [] -> nil
    end
  end

  @doc """
  Lists all provider configs.
  """
  def list_providers do
    @provider_table_name
    |> :ets.tab2list()
    |> Enum.map(fn {_id, config} -> config end)
    |> Enum.sort_by(& &1.provider)
  end

  @doc """
  Gets the API key for a provider.
  Checks DB first, then falls back to environment variable.
  """
  def get_provider_api_key(provider) when is_binary(provider) do
    case get_provider(provider) do
      nil -> nil
      config -> ProviderConfig.get_api_key(config)
    end
  end

  @doc """
  Sets the API key for a provider (stored encrypted in DB).
  """
  def set_provider_api_key(provider, api_key) when is_binary(provider) and is_binary(api_key) do
    GenServer.call(__MODULE__, {:set_api_key, provider, api_key})
  end

  @doc """
  Clears the database API key for a provider.
  Will fall back to environment variable if available.
  """
  def clear_provider_api_key(provider) when is_binary(provider) do
    GenServer.call(__MODULE__, {:clear_api_key, provider})
  end

  @doc """
  Updates a provider config with the given attributes.
  """
  def update_provider(provider, attrs) when is_binary(provider) and is_map(attrs) do
    GenServer.call(__MODULE__, {:update_provider, provider, attrs})
  end

  @doc """
  Marks a provider's key as verified (valid or invalid).
  """
  def set_provider_verification(provider, status) when is_binary(provider) do
    GenServer.call(__MODULE__, {:set_verification, provider, status})
  end

  @doc """
  Gets provider status info including key source and status.
  """
  def get_provider_status(provider) when is_binary(provider) do
    case get_provider(provider) do
      nil ->
        nil

      config ->
        %{
          provider: config.provider,
          enabled: config.enabled,
          has_key: ProviderConfig.has_api_key?(config),
          key_source: ProviderConfig.key_source(config),
          key_status: config.key_status,
          last_verified_at: config.last_verified_at,
          last_error: config.last_error
        }
    end
  end

  @doc """
  Gets status info for all providers.
  """
  def list_provider_statuses do
    list_providers()
    |> Enum.map(fn config ->
      %{
        provider: config.provider,
        enabled: config.enabled,
        has_key: ProviderConfig.has_api_key?(config),
        key_source: ProviderConfig.key_source(config),
        key_status: config.key_status,
        last_verified_at: config.last_verified_at,
        last_error: config.last_error
      }
    end)
  end

  @doc """
  Refreshes the cache by reloading all configs from the database.
  Useful after direct database modifications.
  """
  def refresh_cache do
    GenServer.call(__MODULE__, :refresh_cache)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Create ETS tables
    :ets.new(@table_name, [:named_table, :set, :public, read_concurrency: true])
    :ets.new(@provider_table_name, [:named_table, :set, :public, read_concurrency: true])

    # Load configs from database
    load_all_configs()

    {:ok, %{}}
  end

  @impl true
  def handle_call({:update_agent, agent_id, attrs}, _from, state) do
    result =
      case Repo.get_by(AgentConfig, agent_id: agent_id) do
        nil ->
          {:error, :not_found}

        config ->
          config
          |> AgentConfig.update_changeset(attrs)
          |> Repo.update()
          |> case do
            {:ok, updated_config} ->
              # Update cache
              :ets.insert(@table_name, {agent_id, updated_config})
              {:ok, updated_config}

            {:error, changeset} ->
              {:error, changeset}
          end
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call({:reset_prompt, agent_id}, _from, state) do
    result =
      case Repo.get_by(AgentConfig, agent_id: agent_id) do
        nil ->
          {:error, :not_found}

        config ->
          config
          |> AgentConfig.update_changeset(%{system_prompt: config.default_prompt})
          |> Repo.update()
          |> case do
            {:ok, updated_config} ->
              # Update cache
              :ets.insert(@table_name, {agent_id, updated_config})
              {:ok, updated_config}

            {:error, changeset} ->
              {:error, changeset}
          end
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call(:refresh_cache, _from, state) do
    load_all_configs()
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:set_api_key, provider, api_key}, _from, state) do
    result =
      case Repo.get_by(ProviderConfig, provider: provider) do
        nil ->
          {:error, :not_found}

        config ->
          config
          |> ProviderConfig.set_api_key_changeset(api_key)
          |> Repo.update()
          |> case do
            {:ok, updated_config} ->
              :ets.insert(@provider_table_name, {provider, updated_config})
              {:ok, updated_config}

            {:error, changeset} ->
              {:error, changeset}
          end
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call({:clear_api_key, provider}, _from, state) do
    result =
      case Repo.get_by(ProviderConfig, provider: provider) do
        nil ->
          {:error, :not_found}

        config ->
          config
          |> ProviderConfig.clear_api_key_changeset()
          |> Repo.update()
          |> case do
            {:ok, updated_config} ->
              :ets.insert(@provider_table_name, {provider, updated_config})
              {:ok, updated_config}

            {:error, changeset} ->
              {:error, changeset}
          end
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call({:update_provider, provider, attrs}, _from, state) do
    result =
      case Repo.get_by(ProviderConfig, provider: provider) do
        nil ->
          {:error, :not_found}

        config ->
          config
          |> ProviderConfig.update_changeset(attrs)
          |> Repo.update()
          |> case do
            {:ok, updated_config} ->
              :ets.insert(@provider_table_name, {provider, updated_config})
              {:ok, updated_config}

            {:error, changeset} ->
              {:error, changeset}
          end
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call({:set_verification, provider, status}, _from, state) do
    result =
      case Repo.get_by(ProviderConfig, provider: provider) do
        nil ->
          {:error, :not_found}

        config ->
          config
          |> ProviderConfig.verification_changeset(status)
          |> Repo.update()
          |> case do
            {:ok, updated_config} ->
              :ets.insert(@provider_table_name, {provider, updated_config})
              {:ok, updated_config}

            {:error, changeset} ->
              {:error, changeset}
          end
      end

    {:reply, result, state}
  end

  # Private Functions

  defp load_all_configs do
    load_agent_configs()
    load_provider_configs()
  end

  defp load_agent_configs do
    AgentConfig
    |> Repo.all()
    |> Enum.each(fn config ->
      :ets.insert(@table_name, {config.agent_id, config})
    end)
  end

  defp load_provider_configs do
    ProviderConfig
    |> Repo.all()
    |> Enum.each(fn config ->
      :ets.insert(@provider_table_name, {config.provider, config})
    end)
  end
end
