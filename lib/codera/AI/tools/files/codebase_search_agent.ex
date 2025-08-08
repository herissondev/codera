defmodule Codera.AI.Tools.Files.CodebaseSearchAgent do
  @moduledoc """
  Intelligently search your codebase with an agent that has access to: list_directory, Grep, glob, Read.

  The agent acts like your personal search assistant.

  It's ideal for complex, multi-step search tasks where you need to find code based on functionality or concepts rather than exact matches.

  WHEN TO USE THIS TOOL:
  - When searching for high-level concepts like \"how do we check for authentication headers?\" or \"where do we do error handling in the file watcher?\"
  - When you need to combine multiple search techniques to find the right code
  - When looking for connections between different parts of the codebase
  - When searching for keywords like \"config\" or \"logger\" that need contextual filtering

  WHEN NOT TO USE THIS TOOL:
  - When you know the exact file path - use Read directly
  - When looking for specific symbols or exact strings - use glob or Grep
  - When you need to create, modify files, or run terminal commands

  USAGE GUIDELINES:
  1. Launch multiple agents concurrently for better performance
  2. Be specific in your query - include exact terminology, expected file locations, or code patterns
  3. Use the query as if you were talking to another engineer. Bad: \"logger impl\" Good: \"where is the logger implemented, we're trying to find out how to log to files\"
  4. Make sure to formulate the query in such a way that the agent knows when it's done or has found the result.

  """

  alias LangChain.Message.ContentPart
  alias LangChain.Message
  alias Codera.AI.Agent
  alias Codera.AI.Configs.CodebaseSearchAgent
  alias LangChain.Function
  alias LangChain.FunctionParam

  def codebase_search_agent_tool!() do
    Function.new!(%{
      name: "codebase_search_agent",
      display_text: "Search",
      description: @moduledoc,
      parameters: [
        FunctionParam.new!(%{
          name: "query",
          type: :string,
          description:
            "The search query describing to the agent what it should. Be specific and include technical terms, file types, or expected code patterns to help the agent find relevant code. Formulate the query in a way that makes it clear to the agent when it has found the right thing.",
          required: true
        })
      ],
      function: &read_file/2,
      async: true
    })
  end

  def read_file(%{"query" => query} = _args, _context) do
    %{tools: tools, chain: chain, name: name} = CodebaseSearchAgent.config()

    query_message = Message.new_user!(query)

    agent =
      Agent.new(name, chain)
      |> Agent.add_tools(tools)
      |> Agent.add_message(query_message)

    case Agent.run_chain(agent) do
      {:ok, agent} ->
        IO.puts("Search complete")
        IO.puts("Result:")
        IO.inspect(agent.chain.last_message)
        IO.puts(extract_result(agent.chain.last_message.content))
        {:ok, extract_result(agent.chain.last_message.content)}

      other ->
        IO.puts("An error occurred during the search.")
        IO.puts("Error details: #{inspect(other)}")
        {:error, "Search failed"}
    end
  end

  defp extract_result([%ContentPart{} = content_part]) do
    IO.inspect("extracting contentpart ")

    content_part.content
  end
end
