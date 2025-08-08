defmodule Codera.AI.Agent do
  @moduledoc """
  Agent wrapper around a LangChain LLMChain with convenience helpers.

  This module now includes structured logging and telemetry around key lifecycle events
  (creation, message handling, chain execution, tools/handlers updates).
  """

  require Logger

  alias LangChain.Chains.LLMChain
  alias LangChain.Message
  alias Codera.AI.Agent

  defstruct [
    :id,
    :name,
    :chain,
    status: :idle
  ]

  def new(name, %LLMChain{} = chain) when is_binary(name) do
    id = :rand.bytes(16)

    agent = %Agent{
      id: id,
      name: name,
      chain: chain
    }

    Logger.debug(fn ->
      meta = [agent_id: Base.encode16(id), agent_name: name]
      {"agent.new", meta}
    end)

    :telemetry.execute(
      [
        :codera,
        :ai,
        :agent,
        :new
      ],
      %{count: 1},
      %{agent_id: Base.encode16(id), agent_name: name}
    )

    agent
  end

  def chat_response(agent, message, opts \\ [])

  def chat_response(%Agent{} = agent, message, opts) when is_binary(message) do
    m = Message.new_user!(message)
    m = %Message{m | name: "toto"}

    Logger.debug(fn ->
      meta = [
        agent_id: encode_id(agent),
        agent_name: agent.name,
        message_len: String.length(message)
      ]

      {"agent.chat_response/2 (string message)", meta}
    end)

    :telemetry.execute(
      [
        :codera,
        :ai,
        :agent,
        :chat_response
      ],
      %{message_len: String.length(message)},
      %{agent_id: encode_id(agent), agent_name: agent.name, kind: :string}
    )

    chat_response(agent, m, opts)
  end

  def chat_response(
        %Agent{chain: %LLMChain{}} = agent,
        %Message{role: :user} = message,
        opts
      ) do
    Logger.debug(fn ->
      meta = [agent_id: encode_id(agent), agent_name: agent.name, role: message.role]
      {"agent.chat_response/2 (Message)", meta}
    end)

    :telemetry.execute(
      [
        :codera,
        :ai,
        :agent,
        :chat_response
      ],
      %{count: 1},
      %{agent_id: encode_id(agent), agent_name: agent.name, role: message.role, kind: :message}
    )

    agent
    |> add_message(message)
    |> run_chain(opts)
  end

  def run_chain(%Agent{chain: %LLMChain{} = chain} = agent, opts \\ []) do
    # running mode can either be :while_needs_response, :until_success, :until_tool_used or :tool_use.
    # In the last two cases, termination_tool ops should be provided as string
    # TODO : implement :tool_use
    running_mode = Keyword.get(opts, :mode, :while_needs_response)
    termination_tool = Keyword.get(opts, :termination_tool, nil)

    Logger.info(fn ->
      meta = [
        agent_id: encode_id(agent),
        agent_name: agent.name,
        mode: running_mode,
        termination_tool: termination_tool
      ]

      {"agent.run_chain.start", meta}
    end)

    start_monotonic = System.monotonic_time()

    :telemetry.execute(
      [
        :codera,
        :ai,
        :agent,
        :run_chain,
        :start
      ],
      %{system_time: System.system_time()},
      %{
        agent_id: encode_id(agent),
        agent_name: agent.name,
        mode: running_mode,
        termination_tool: termination_tool
      }
    )

    result =
      case running_mode do
        mode when mode in [:while_needs_response, :until_success] ->
          LLMChain.run(chain, mode: mode)

        :until_tool_used ->
          LLMChain.run_until_tool_used(chain, termination_tool)
      end

    duration = System.monotonic_time() - start_monotonic

    case result do
      {:ok, updated_chain} ->
        Logger.info(fn ->
          meta = [agent_id: encode_id(agent), agent_name: agent.name, status: :ok]
          {"agent.run_chain.ok", meta}
        end)

        :telemetry.execute(
          [
            :codera,
            :ai,
            :agent,
            :run_chain,
            :stop
          ],
          %{duration: duration},
          %{agent_id: encode_id(agent), agent_name: agent.name, mode: running_mode, status: :ok}
        )

        {:ok, %Agent{agent | chain: updated_chain}}

      # run until tool used ok result
      {:ok, updated_chain, _message} ->
        {:ok, %Agent{agent | chain: updated_chain}}

      {:error, updated_chain?, error} ->
        Logger.error(fn ->
          meta = [agent_id: encode_id(agent), agent_name: agent.name, error: inspect(error)]
          {"agent.run_chain.error", meta}
        end)

        :telemetry.execute(
          [
            :codera,
            :ai,
            :agent,
            :run_chain,
            :exception
          ],
          %{duration: duration},
          %{agent_id: encode_id(agent), agent_name: agent.name, mode: running_mode, error: error}
        )

        {:error, %Agent{agent | chain: updated_chain?}, error}
    end
  end

  def add_message(%Agent{chain: %LLMChain{} = chain} = agent, %Message{} = message) do
    new_chain = LLMChain.add_message(chain, message)

    %Agent{agent | chain: new_chain}
  end

  def add_message(%Agent{} = agent, message) when is_binary(message) do
    message_struct = Message.new_user!(message)
    add_message(agent, message_struct)
  end

  def add_tools(%Agent{chain: %LLMChain{} = chain} = agent, tools) do
    new_chain = LLMChain.add_tools(chain, tools)

    Logger.debug(fn ->
      meta = [
        agent_id: encode_id(agent),
        agent_name: agent.name,
        tools_count: length(List.wrap(tools))
      ]

      {"agent.add_tools", meta}
    end)

    :telemetry.execute(
      [
        :codera,
        :ai,
        :agent,
        :add_tools
      ],
      %{count: length(List.wrap(tools))},
      %{agent_id: encode_id(agent), agent_name: agent.name}
    )

    %Agent{agent | chain: new_chain}
  end

  def add_handlers(%Agent{chain: %LLMChain{} = chain} = agent, handlers) do
    new_chain = LLMChain.add_callback(chain, handlers)

    Logger.debug(fn ->
      meta = [
        agent_id: encode_id(agent),
        agent_name: agent.name,
        handlers_count: length(List.wrap(handlers))
      ]

      {"agent.add_handlers", meta}
    end)

    :telemetry.execute(
      [
        :codera,
        :ai,
        :agent,
        :add_handlers
      ],
      %{count: length(List.wrap(handlers))},
      %{agent_id: encode_id(agent), agent_name: agent.name}
    )

    %Agent{agent | chain: new_chain}
  end

  @doc """
  Replace the current system prompt (first system message) with a new one.

  Checks:
  - Chain must contain exactly one system message; otherwise returns {:error, reason}.
  - The provided message must be a system role message.
  """
  @spec set_system_prompt(%Agent{}, %Message{}) :: {:ok, %Agent{}} | {:error, term()}
  def set_system_prompt(
        %Agent{chain: %LLMChain{} = chain} = agent,
        %Message{role: :system} = new_system
      ) do
    sys_msgs = Enum.filter(chain.messages, &match?(%Message{role: :system}, &1))

    case length(sys_msgs) do
      1 ->
        new_messages =
          chain.messages
          |> Enum.map(fn m -> if m.role == :system, do: new_system, else: m end)

        {:ok, %Agent{agent | chain: %LLMChain{chain | messages: new_messages}}}

      0 ->
        {:error, :no_system_message_found}

      _ ->
        {:error, :multiple_system_messages_found}
    end
  end

  def set_system_prompt(_agent, _), do: {:error, :invalid_system_message}

  defp encode_id(%Agent{id: id}) when is_binary(id), do: Base.encode16(id)
  defp encode_id(_), do: nil
end
