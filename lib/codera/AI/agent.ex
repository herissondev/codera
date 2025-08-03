defmodule Codera.AI.Agent do
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

    %Agent{
      id: id,
      name: name,
      chain: chain
    }
  end

  def chat_response(agent, message, opts \\ [])

  def chat_response(%Agent{} = agent, message, opts) when is_binary(message) do
    chat_response(agent, Message.new_user!(message), opts)
  end

  def chat_response(
        %Agent{chain: %LLMChain{}} = agent,
        %Message{role: :user} = message,
        opts
      ) do
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

    result =
      case running_mode do
        mode when mode in [:while_needs_response, :until_success] ->
          LLMChain.run(chain, mode: mode)

        :until_tool_used ->
          LLMChain.run_until_tool_used(chain, termination_tool)
      end

    case result do
      {:ok, updated_chain} ->
        %Agent{agent | chain: updated_chain}

      {:error, updated_chain?, error} ->
        Logger.error("Error while running chain #{inspect(error)}")
        %Agent{agent | chain: updated_chain?}
    end
  end

  def add_tools(%Agent{chain: %LLMChain{} = chain} = agent, tools) do
    new_chain = LLMChain.add_tools(chain, tools)
    %Agent{agent | chain: new_chain}
  end

  def add_handlers(%Agent{chain: %LLMChain{} = chain} = agent, handlers) do
    new_chain = LLMChain.add_callback(chain, handlers)
    %Agent{agent | chain: new_chain}
  end

  defp add_message(%Agent{chain: %LLMChain{} = chain} = agent, message) do
    new_chain = LLMChain.add_message(chain, message)
    %Agent{agent | chain: new_chain}
  end
end
