defmodule Codera.AI.Tools.Files.ReadFile do
  @moduledoc """
  Read a file from the file system. If the file doesn't exist, an error is returned.

  * The `path` parameter **must** be an absolute path.
  * By default, this tool returns the first 1000 lines. To read more, call it multiple times with different read_ranges.
  * Use the Grep tool to find specific content in large files or files with long lines.
  * If you are unsure of the correct file path, use the glob tool to look up filenames by glob pattern.
  * The contents are returned with each line prefixed by its line number. For example, if a file has contents `"abc\n"`, you will receive `"1: abc\n"`.
  * This tool can read images (such as PNG, JPEG, and GIF files) and present them to the model visually.
  * When possible, call this tool in parallel for all files you will want to read.
  """

  alias LangChain.Function
  alias LangChain.FunctionParam

  @default_lines 1000

  def read_file_tool!() do
    Function.new!(%{
      name: "read_file",
      display_text: "Read file",
      description: @moduledoc,
      parameters: [
        FunctionParam.new!(%{
          name: "path",
          type: :string,
          description: "Absolute file path to read from"
        }),
        FunctionParam.new!(%{
          name: "start_line",
          type: :integer,
          description: "(Optional) 1‑based start line of the range to read",
          optional: true,
          default: 1
        })
      ],
      function: &read_file/2,
      async: true
    })
  end

  def read_file(%{"path" => path} = args, _context) do
    with true <- String.starts_with?(path, "/") or {:error, "`path` must be absolute"},
         {:ok, content} <- File.read(path) do
      start_line = Map.get(args, "start_line", 1)

      lines =
        content
        |> String.split("\n")
        |> Enum.with_index(1)
        |> Enum.drop(start_line - 1)
        |> Enum.take(@default_lines)
        |> Enum.map_join("\n", fn {line, idx} -> "#{idx}: #{line}" end)

      {:ok, lines}
    else
      {:error, reason} -> {:error, to_string(reason)}
    end
  end
end
