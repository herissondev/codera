defmodule Codera.AI.Tools.Files.Glob do
  @moduledoc """
  Fast file pattern matching tool that works with any codebase size.

  * **filePattern** – Glob pattern to match files (supports `**` for recursive search).
  * **limit** – (optional) Maximum number of results to return. Defaults to `nil` (no limit).
  * **offset** – (optional) Number of initial results to skip (for pagination). Defaults to `0`.

  Results are **sorted by last modification time** (newest first) before pagination is
  applied. Each path is returned on its own line.

  The search **always ignores** the following directories to keep results fast and tidy:
  node_modules, deps, build, .git, .idea, .vscode, .cache, .log, .idea, .vscode, .cache, .log

  If you want to see the content of one of these directories, use the `list_directory` tool.
  """

  alias LangChain.Function
  alias LangChain.FunctionParam

  @ignore_dirs ~w(node_modules _build build .idea .vscode .cache .log deps .git .elixir_ls)

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

    # Handle empty or whitespace-only patterns
    trimmed_pattern = String.trim(pattern)

    if trimmed_pattern == "" do
      {:ok, "No pattern provided"}
    else
      ignore_re = build_ignore_regex()

      paths =
        trimmed_pattern
        |> Path.wildcard(match_dot: true)
        |> Enum.reject(&Regex.match?(ignore_re, &1))

      sorted =
        paths
        |> Enum.map(fn p -> {p, file_mtime(p)} end)
        |> Enum.sort_by(fn {_p, mtime} -> mtime end, {:desc, DateTime})
        |> Enum.drop(offset)
        |> maybe_take(limit)
        |> Enum.map(fn {p, _} -> p end)

      result =
        case Enum.join(sorted, "\n") do
          "" -> "Nothing found"
          res -> res
        end

      {:ok, result}
    end
  rescue
    e in File.Error ->
      IO.inspect(e)
      IO.inspect("we are in rescue 1")
      {:error, e.reason |> to_string()}

    e ->
      IO.inspect("we are in rescue 2")
      {:error, "Pattern error: #{inspect(e)}"}
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

  defp build_ignore_regex do
    extras =
      @ignore_dirs
      |> Enum.map(&Regex.escape/1)
      |> Enum.join("|")

    # \.[^/]+  -> any segment that starts with a dot (excluding “.” and “..” by virtue of +)
    pattern = "(?:\\.[^/]+|#{extras})"

    ~r/(^|\/)#{pattern}(\/|$)/
  end

  defp maybe_take(list, nil), do: list
  defp maybe_take(list, n) when is_integer(n) and n > 0, do: Enum.take(list, n)
  defp maybe_take(list, _), do: list
end
