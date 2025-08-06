defmodule Codera.AI.AgentTest do
  use ExUnit.Case, async: true
  alias Codera.AI.Agent
  alias LangChain.Chains.LLMChain
  alias LangChain.Function

  describe "new/2" do
    test "creates a new agent with valid name and chain" do
      chain = %LLMChain{}
      name = "test-agent"

      agent = Agent.new(name, chain)

      assert %Agent{} = agent
      assert agent.name == name
      assert agent.chain == chain
      assert agent.status == :idle
      assert is_binary(agent.id)
      assert byte_size(agent.id) == 16
    end

    test "generates unique IDs for different agents" do
      chain = %LLMChain{}
      name = "test-agent"

      agent1 = Agent.new(name, chain)
      agent2 = Agent.new(name, chain)

      assert agent1.id != agent2.id
    end

    test "requires name to be a binary" do
      chain = %LLMChain{}

      assert_raise FunctionClauseError, fn ->
        Agent.new(:invalid_name, chain)
      end

      assert_raise FunctionClauseError, fn ->
        Agent.new(123, chain)
      end
    end

    test "requires chain to be an LLMChain struct" do
      name = "test-agent"

      assert_raise FunctionClauseError, fn ->
        Agent.new(name, %{})
      end

      assert_raise FunctionClauseError, fn ->
        Agent.new(name, "invalid_chain")
      end
    end
  end

  describe "add_tools/2" do
    setup do
      chain = %LLMChain{}
      agent = Agent.new("test-agent", chain)
      {:ok, agent: agent}
    end

    test "adds tools to agent's chain", %{agent: agent} do
      tool1 = %Function{name: "tool1", description: "Test tool 1"}
      tool2 = %Function{name: "tool2", description: "Test tool 2"}
      tools = [tool1, tool2]

      result = Agent.add_tools(agent, tools)

      assert %Agent{} = result
      assert result.id == agent.id
      assert result.name == agent.name
      assert result.status == agent.status
      # The chain should be updated by LLMChain.add_tools
      refute result.chain == agent.chain
    end

    test "returns agent with same id, name, and status", %{agent: agent} do
      tool = %Function{name: "test_tool", description: "A test tool"}
      tools = [tool]
      result = Agent.add_tools(agent, tools)

      assert result.id == agent.id
      assert result.name == agent.name
      assert result.status == agent.status
    end

    test "works with empty tools list", %{agent: agent} do
      tools = []
      result = Agent.add_tools(agent, tools)

      assert %Agent{} = result
      assert result.id == agent.id
    end
  end

  describe "add_handlers/2" do
    setup do
      chain = %LLMChain{}
      agent = Agent.new("test-agent", chain)
      {:ok, agent: agent}
    end

    test "adds handlers to agent's chain", %{agent: agent} do
      handlers = [fn -> :ok end, fn -> :ok end]

      result = Agent.add_handlers(agent, handlers)

      assert %Agent{} = result
      assert result.id == agent.id
      assert result.name == agent.name
      assert result.status == agent.status
      # The chain should be updated by LLMChain.add_callback
      refute result.chain == agent.chain
    end

    test "returns agent with same id, name, and status", %{agent: agent} do
      handlers = [fn -> :ok end]
      result = Agent.add_handlers(agent, handlers)

      assert result.id == agent.id
      assert result.name == agent.name
      assert result.status == agent.status
    end

    test "works with empty handlers list", %{agent: agent} do
      handlers = []
      result = Agent.add_handlers(agent, handlers)

      assert %Agent{} = result
      assert result.id == agent.id
    end

    test "works with single handler", %{agent: agent} do
      handler = fn -> :ok end
      result = Agent.add_handlers(agent, handler)

      assert %Agent{} = result
      assert result.id == agent.id
    end
  end

  describe "Agent struct" do
    test "has correct default values" do
      chain = %LLMChain{}
      agent = Agent.new("test", chain)

      assert agent.status == :idle
      assert is_binary(agent.id)
      assert agent.name == "test"
      assert agent.chain == chain
    end

    test "struct has all expected fields" do
      chain = %LLMChain{}
      agent = Agent.new("test", chain)

      # Test that all expected fields exist
      assert Map.has_key?(agent, :id)
      assert Map.has_key?(agent, :name)
      assert Map.has_key?(agent, :chain)
      assert Map.has_key?(agent, :status)
    end
  end
end
