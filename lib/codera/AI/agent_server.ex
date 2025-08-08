defmodule Codera.AI.AgentServer do
  use GenServer
  require Logger
  alias Codera.AI.Agent

  @topic_prefix "thread:"

  # Client API

  @doc """
  Starts a new thread with a friendly name and optional working directory
  """
  def start_thread(thread_name \\ nil, working_dir \\ nil) do
    thread_name =
      thread_name || FriendlyID.generate(3, separator: "-", transform: &String.downcase/1)
    
    working_dir = working_dir || File.cwd!()
    
    Logger.info("Attempting to start thread: #{thread_name} in #{working_dir}")

    case DynamicSupervisor.start_child(
           Codera.AI.ThreadSupervisor,
           {__MODULE__, {thread_name, working_dir}}
         ) do
      {:ok, pid} -> 
        Logger.info("Successfully started thread #{thread_name} with pid #{inspect(pid)}")
        {:ok, thread_name}
      {:error, {:already_started, pid}} -> 
        Logger.info("Thread #{thread_name} already exists with pid #{inspect(pid)}")
        {:ok, thread_name}
      error -> 
        Logger.error("Failed to start thread #{thread_name}: #{inspect(error)}")
        error
    end
  end

  @doc """
  Gets the current agent state for a thread
  """
  def get_agent(thread_name) do
    case get_server_pid(thread_name) do
      nil -> {:error, :not_found}
      pid -> GenServer.call(pid, :get_agent)
    end
  end

  @doc """
  Gets the working directory for a thread
  """
  def get_working_dir(thread_name) do
    case get_server_pid(thread_name) do
      nil -> {:error, :not_found}
      pid -> GenServer.call(pid, :get_working_dir)
    end
  end

  @doc """
  Sends a message to a thread
  """
  def send_message(thread_name, message) do
    case get_server_pid(thread_name) do
      nil -> {:error, :not_found}
      pid -> GenServer.cast(pid, {:send_message, message})
    end
  end

  @doc """
  Lists all active threads with their working directories
  """
  def list_threads do
    children = DynamicSupervisor.which_children(Codera.AI.ThreadSupervisor)
    Logger.info("DynamicSupervisor children: #{inspect(children)}")
    
    children
    |> Enum.map(fn {_, pid, _, _} ->
      try do
        with name when is_binary(name) <- GenServer.call(pid, :get_thread_name, 1000),
             {:ok, working_dir} <- GenServer.call(pid, :get_working_dir, 1000) do
          Logger.info("Found thread: #{name} in #{working_dir}")
          %{name: name, working_dir: working_dir}
        else
          other -> 
            Logger.warning("Invalid thread response: #{inspect(other)}")
            nil
        end
      rescue
        error ->
          Logger.error("Error calling thread #{inspect(pid)}: #{inspect(error)}")
          nil
      end
    end)
    |> Enum.filter(& &1)
  end

  # Server callbacks

  def start_link({thread_name, working_dir}) do
    GenServer.start_link(__MODULE__, {thread_name, working_dir}, name: via_tuple(thread_name))
  end

  def init({thread_name, working_dir}) do
    Logger.info("Starting thread: #{thread_name} in directory: #{working_dir}")
    
    try do
      # Verify working directory exists
      unless File.dir?(working_dir) do
        raise "Working directory does not exist: #{working_dir}"
      end
      
      # Create agent with chain
      %{chain: chain, tools: tools} = Codera.AI.Configs.CodingAgent.config()
      agent = Agent.new(thread_name, chain) |> Agent.add_tools(tools)
      
      state = %{
        thread_name: thread_name,
        working_dir: working_dir,
        agent: agent
      }
      
      Logger.info("Successfully initialized thread: #{thread_name} in #{working_dir}")
      {:ok, state}
    rescue
      error ->
        Logger.error("Failed to initialize thread #{thread_name}: #{inspect(error)}")
        {:stop, error}
    end
  end

  def handle_call(:get_agent, _from, %{agent: agent} = state) do
    {:reply, {:ok, agent}, state}
  end

  def handle_call(:get_working_dir, _from, %{working_dir: working_dir} = state) do
    {:reply, {:ok, working_dir}, state}
  end

  def handle_call(:get_thread_name, _from, %{thread_name: thread_name} = state) do
    {:reply, thread_name, state}
  end

  def handle_cast(
        {:send_message, message_content},
        %{agent: agent, thread_name: thread_name} = state
      ) do
    Logger.info("Sending message to thread #{thread_name}: #{message_content}")

    # Process with AI (async to avoid blocking)
    Task.start(fn ->
      process_message(thread_name, agent, message_content)
    end)

    {:noreply, state}
  end

  def handle_cast({:update_agent, updated_agent}, %{thread_name: thread_name} = state) do
    broadcast_update(thread_name, updated_agent)
    new_state = %{state | agent: updated_agent}
    {:noreply, new_state}
  end

  # Private function to process message using agent.ex functions
  defp process_message(thread_name, agent, message_content) do
    try do
      # Use Agent.chat_response which handles adding user message and running chain
      case Agent.chat_response(agent, message_content) do
        {:ok, updated_agent} ->
          # Update the server state and broadcast
          case get_server_pid(thread_name) do
            nil ->
              Logger.warning("Thread #{thread_name} no longer exists")

            pid ->
              GenServer.cast(pid, {:update_agent, updated_agent})
          end

        {:error, reason} ->
          Logger.error("Failed to process message for thread #{thread_name}: #{inspect(reason)}")
      end
    rescue
      error ->
        Logger.error("Exception processing message for thread #{thread_name}: #{inspect(error)}")
    end
  end

  # Private functions

  defp via_tuple(thread_name) do
    {:via, Registry, {Codera.AI.ThreadRegistry, thread_name}}
  end

  defp get_server_pid(thread_name) do
    case Registry.lookup(Codera.AI.ThreadRegistry, thread_name) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  defp broadcast_update(thread_name, agent) do
    Phoenix.PubSub.broadcast(
      Codera.PubSub,
      @topic_prefix <> thread_name,
      {:agent_updated, agent}
    )
  end

  def subscribe_to_thread(thread_name) do
    Phoenix.PubSub.subscribe(Codera.PubSub, @topic_prefix <> thread_name)
  end
end
