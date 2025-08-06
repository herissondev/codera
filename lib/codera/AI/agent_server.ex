defmodule Codera.AI.AgentServer do
  use GenServer

  def start_link(config) do
    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  def init(init_arg) do
    {:ok, init_arg}
  end

  def handle_message(_message, _state) do
    # call LangChain chain
    :ok
  end
end
