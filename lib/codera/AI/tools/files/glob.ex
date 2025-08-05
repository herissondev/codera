defmodule Codera.AI.Tools.Files.Glob do
  @moduledoc """
  Fast file pattern matching tool that works with any codebase size.

  * **filePattern** – Glob pattern to match files (supports `**` for recursive search).
  * **limit** – (optional) Maximum number of results to return. Defaults to `nil` (no limit).
  * **offset** – (optional) Number of initial results to skip (for pagination). Defaults to `0`.

  Results are **sorted by last modification time** (newest first) before pagination is
  applied. Each path is returned on its own line.
  """

  alias LangChain.Function
  alias LangChain.FunctionParam

  # ---------------------------------------------------------------------------
  # Registration
  # ---------------------------------------------------------------------------
  def glob_tool!() do
    Function.new!(%{
      name: "glob",
      display_text: "Glob search",
      description: @moduledoc,
      parameters: [
        FunctionParam.new!(%{
          name: "filePattern",
          type: :string,
          description: "Glob pattern (e.g., '**/*.js')"
        }),
        FunctionParam.new!(%{
          name: "limit",
          type: :integer,
          description: "(Optional) Maximum number of results to return",
          optional: true
        }),
        FunctionParam.new!(%{
          name: "offset",
          type: :integer,
          description: "(Optional) Number of initial results to skip",
          optional: true,
          default: 0
        })
      ],
      function: &glob/2,
      async: true
    })
  end

  # ---------------------------------------------------------------------------
  # Callback
  # ---------------------------------------------------------------------------
  @spec glob(map(), map()) :: {:ok, binary()} | {:error, binary()}
  def glob(%{"filePattern" => pattern} = args, _ctx) do
    limit = Map.get(args, "limit")
    offset = Map.get(args, "offset", 0)

    paths = Path.wildcard(pattern, match_dot: true)

    sorted =
      paths
      |> Enum.map(fn p -> {p, file_mtime(p)} end)
      |> Enum.sort_by(fn {_p, mtime} -> mtime end, {:desc, DateTime})
      |> Enum.drop(offset)
      |> maybe_take(limit)
      |> Enum.map(fn {p, _} -> p end)

    {:ok, Enum.join(sorted, "\n")}
  rescue
    e in File.Error -> {:error, e.reason |> to_string()}
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------
  defp file_mtime(path) do
    case File.stat(path) do
      {:ok, %File.Stat{mtime: mtime}} ->
        cond do
          is_integer(mtime) -> DateTime.from_unix!(mtime)
          true -> DateTime.from_unix!(0)
        end

      _ ->
        DateTime.from_unix!(0)
    end
  end

  defp maybe_take(list, nil), do: list
  defp maybe_take(list, n) when is_integer(n) and n > 0, do: Enum.take(list, n)
  defp maybe_take(list, _), do: list
end
