defmodule Codera.AI.Tools.Task.Report do
  @moduledoc """
  Private tool for sub-agents to finish and report results back to the parent agent.

  Parameters:
  - summary (string): concise overview
  - details (string): key steps taken and results
  - artifacts (string, optional): artifact description or paths
  - followups (string, optional): suggested next steps
  """

  alias LangChain.Function
  alias LangChain.FunctionParam

  def task_report_tool!() do
    Function.new!(%{
      name: "task_report",
      display_text: "Task report (internal)",
      description: @moduledoc,
      parameters: [
        FunctionParam.new!(%{name: "summary", type: :string, description: "Concise overview"}),
        FunctionParam.new!(%{
          name: "details",
          type: :string,
          description: "Key steps and results"
        }),
        FunctionParam.new!(%{
          name: "artifacts",
          type: :string,
          description: "Artifacts or paths",
          optional: true
        }),
        FunctionParam.new!(%{
          name: "followups",
          type: :string,
          description: "Next steps",
          optional: true
        })
      ],
      function: &report/2
    })
  end

  @spec report(map(), map()) :: {:ok, binary()} | {:error, binary()}
  def report(args, _ctx) do
    payload =
      %{
        summary: Map.get(args, "summary"),
        details: Map.get(args, "details"),
        artifacts: Map.get(args, "artifacts"),
        followups: Map.get(args, "followups")
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)
      |> Enum.map(fn {k, v} -> "#{k}: #{v}" end)
      |> Enum.join("\n")

    {:ok, payload}
  end
end
