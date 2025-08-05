defmodule Codera.AI.Tools.Task do
  @moduledoc """
  Perform a task (a sub-task of the user's overall task) using a sub-agent that has access to the following tools:
  list_directory, glob, Read, Bash, edit_file, create_file.

  When to use the Task tool:
  - When you need to perform complex multi-step tasks
  - When you need to run an operation that will produce a lot of output (tokens) that is not needed after the sub-agent's task completes
  - When you are making changes across many layers of an application (after you have first planned/spec'd the changes)
  - When the user asks you to launch an agent

  When NOT to use the Task tool:
  - For a single logical task in a single part of the application (use specific tools instead)
  - For reading a single file (use Read), text search (use Grep), editing a single file (use edit_file)
  - When you're not sure what changes you want to make. First determine the changes with available tools.

  How to use the Task tool:
  - Include all necessary context from the user's message and prior assistant steps, as well as a detailed plan for the task, in the task description.
  - Be specific about what the sub-agent should return when finished to summarize its work.
  - Tell the sub-agent how to verify its work if possible (e.g., by mentioning the relevant test commands to run).
  - You will not see the individual steps of the sub-agent's execution, and you can't communicate with it until it finishes. When done, it will call the private tool `task_report`, and we will return its payload back to the parent as this tool's result.
  """

  require Logger
  alias LangChain.Function
  alias LangChain.FunctionParam
  alias LangChain.Message
  alias LangChain.Chains.LLMChain

  alias Codera.AI.Agent
  alias Codera.AI.Tools.Bash
  alias Codera.AI.Tools.Files
  alias Codera.AI.Tools.Task.Report
  alias Codera.AI.Configs.CodingAgent

  # ---------------------------------------------------------------------------
  # Registration
  # ---------------------------------------------------------------------------
  def task_tool!() do
    Function.new!(%{
      name: "task",
      display_text: "Task",
      description: @moduledoc,
      parameters: [
        FunctionParam.new!(%{
          name: "description",
          type: :string,
          description: "Full task description with all necessary context and expected outputs"
        }),
        FunctionParam.new!(%{
          name: "plan",
          type: :string,
          description: "Detailed plan/checklist for the sub-agent to follow"
        }),
        FunctionParam.new!(%{
          name: "verification",
          type: :string,
          description: "Optional commands/steps to verify work (tests, lint, build)",
          optional: true
        }),
        FunctionParam.new!(%{
          name: "extra_context",
          type: :string,
          description: "Optional free-form context to pass to sub-agent",
          optional: true
        })
      ],
      function: &run/2,
      async: true
    })
  end

  # ---------------------------------------------------------------------------
  # Callback
  # ---------------------------------------------------------------------------
  @spec run(map(), map()) :: {:ok, binary()} | {:error, binary()}
  def run(%{"description" => desc, "plan" => plan} = args, _ctx) do
    Logger.info("Running task with description: #{desc}")

    try do
      %{chain: base_chain} = CodingAgent.config()

      system = subagent_system_prompt()

      user_payload =
        subagent_user_payload(
          desc,
          plan,
          Map.get(args, "verification"),
          Map.get(args, "extra_context")
        )

      chain =
        base_chain
        |> LLMChain.add_message(user_payload)

      agent =
        Agent.new("subtask", chain)
        |> case do
          ag ->
            case Agent.set_system_prompt(ag, system) do
              {:ok, ag2} -> ag2
              {:error, _} -> ag
            end
        end
        |> Agent.add_tools(Files.all_files_tools!())
        |> Agent.add_tools(Bash.bash_tool!())
        |> Agent.add_tools(Report.task_report_tool!())

      case Agent.run_chain(agent, mode: :until_tool_used, termination_tool: "task_report") do
        {:ok, %Agent{chain: %LLMChain{} = ch}} ->
          IO.inspect(ch.last_message, label: "Sub Agent Tsk Result")

          case extract_task_report(ch) do
            {:ok, payload} -> {:ok, payload}
            {:error, reason} -> {:error, reason}
          end

        {:error, _ag, err} ->
          {:error, format_error(err)}
      end
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  def run(_other, _ctx), do: {:error, "Missing required parameters: description, plan"}

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------
  defp subagent_system_prompt() do
    Message.new_system!("""
    You are a focused sub-agent tasked with completing a single, well-scoped sub-task.
    You have access to tools: list_directory, glob, read_file, edit_file, create_file, bash, and a private tool task_report.

    Rules:
    - Use only the provided tools. Be safe: use absolute paths; verify directories before writes.
    - Do not expose your internal chain or tool noise; only return a final report via task_report when done.
    - If you need to show diffs or outputs, include them succinctly in task_report details.
    - Verify your work using the provided verification steps when applicable.

    When you have finished, call task_report with a JSON payload containing:
    - summary: a concise overview of what you accomplished
    - details: key steps taken and results (brief)
    - artifacts: optional artifacts or file paths created/modified
    - followups: optional next steps or notes for the parent agent
    """)
  end

  defp subagent_user_payload(desc, plan, verification, extra) do
    content =
      [
        "Task description:\n\n",
        desc,
        "\n\nExecution plan:\n\n",
        plan,
        if(verification && verification != "",
          do: "\n\nVerification steps:\n\n#{verification}",
          else: ""
        ),
        if(extra && extra != "", do: "\n\nExtra context:\n\n#{extra}", else: ""),
        "\n\nIMPORTANT: When finished, call task_report with {summary, details, artifacts, followups}."
      ]
      |> IO.iodata_to_binary()

    Message.new_user!(content)
  end

  defp extract_task_report(%LLMChain{messages: msgs}) do
    msgs
    |> Enum.reverse()
    |> Enum.find_value(fn m ->
      case m do
        %Message{role: :tool, tool_results: results} ->
          Enum.find_value(results || [], fn r ->
            case r do
              %Message.ToolResult{name: "task_report", content: c} ->
                {:ok, Enum.map_join(c, "", & &1.content)}

              _ ->
                false
            end
          end)

        _ ->
          false
      end
    end)
    |> case do
      {:ok, payload} -> {:ok, payload}
      _ -> {:error, "task_report tool result not found"}
    end
  end

  defp format_error(err) do
    case err do
      %{message: m} when is_binary(m) -> m
      _ -> inspect(err)
    end
  end
end
