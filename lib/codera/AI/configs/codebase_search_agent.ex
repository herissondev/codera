defmodule Codera.AI.Configs.CodebaseSearchAgent do
  alias LangChain.Message
  alias LangChain.Chains.LLMChain
  alias LangChain.ChatModels.ChatOpenAI
  alias Codera.AI.Tools.Files

  def config do
    openrouter = Application.fetch_env!(:codera, :openrouter)

    model =
      ChatOpenAI.new!(%{
        api_key: openrouter[:api_key],
        # big model, maybe wan reduce for speed/price but for now free
        model: "openai/gpt-5-mini",
        endpoint: openrouter[:endpoint],
        user: openrouter[:user]
      })

    tools = Files.read_only_tools!()

    %{
      chain: LLMChain.new!(%{llm: model}) |> LLMChain.add_message(system_prompt()),
      name: "codebase_search_agent",
      tools: tools
    }
  end

  defp system_prompt() do
    """
    You are a powerful code search agent.  Your task is to help find files that might contain answers to another agent's query.  - You do that by searching through the codebase with the tools that are available to you. - You can use the tools multiple times. - You are encouraged to use parallel tool calls as much as possible. - Your goal is to return a list of relevant filenames. Your goal is NOT to explore the complete codebase to construct an essay of an answer. - IMPORTANT: Only your last message is surfaced back to the agent as the final answer.  <example> user: Where do we check for the x-goog-api-key header? assistant: [uses Grep tool to find files containing 'x-goog-api-key', then uses two parallel tool calls to Read to read the files] src/api/auth/authentication.ts </example>  <example> user: We're looking for how the database connection is setup assistant: [uses list_directory tool to list the files in `config` folder, then issues three parallel Read tool calls to view the development.yaml, production.yaml, and staging.yaml files] config/staging.yaml, config/production.yaml, config/development.yaml </examples>  <example> user: Where do we store the svelte components? assistant: [uses glob tool with `**/*.svelte` to find files ending in `*.svelte`] The majority of the Svelte components are stored in web/ui/components, but some are also in web/storybook, which seem to be only used for the Storybook. </examples>  <example> user: Which files handle the user authentication flow? assistant: [Uses Grep for keywords 'login' and 'authenticate', then reads multiple related files in parallel with Read] src/api/auth/login.ts, src/api/auth/authentication.ts, and src/api/auth/session.ts. </example>

    Current working directory is `#{File.cwd!()}`.
    """
    |> Message.new_system!()
  end
end
