defmodule Codera.AI.Tools.Files.EditFile do
  @moduledoc """
  Make edits to a text file.

  Replaces `old_str` with `new_str` in the given file.

  Returns a git‑style diff showing the changes made as formatted markdown,
  along with the line range ([startLine, endLine]) of the changed content.
  The diff is also shown to the user.

  The file specified by `path` **MUST** exist. If you need to create a new
  file, use `create_file` instead.

  `old_str` **MUST** exist in the file. Use tools like `Read` to understand
  the files you are editing before changing them.

  `old_str` and `new_str` **MUST** be different from each other.

  Set `replace_all` to `true` to replace all occurrences of `old_str` in the
  file. Else, `old_str` **MUST** be unique within the file or the edit will
  fail. Additional lines of context can be added to make the string more
  unique.

  If you need to replace the entire contents of a file, use `create_file`
  instead, since it requires less tokens for the same action (since you
  won't have to repeat the contents before replacing).
  """

  alias LangChain.Function
  alias LangChain.FunctionParam

  # ---------------------------------------------------------------------------
  # Registration
  # ---------------------------------------------------------------------------
  def edit_file_tool!() do
    Function.new!(%{
      name: "edit_file",
      display_text: "Edit file",
      description: @moduledoc,
      parameters: [
        FunctionParam.new!(%{
          name: "path",
          type: :string,
          description: "Full path of the file to edit"
        }),
        FunctionParam.new!(%{
          name: "old_str",
          type: :string,
          description: "String to replace"
        }),
        FunctionParam.new!(%{
          name: "new_str",
          type: :string,
          description: "Replacement string"
        }),
        FunctionParam.new!(%{
          name: "replace_all",
          type: :boolean,
          description: "Replace every occurrence (default: false)",
          default: false,
          optional: true
        })
      ],
      function: &edit_file/2
    })
  end


  # ---------------------------------------------------------------------------
  # Callback
  # ---------------------------------------------------------------------------
  @spec edit_file(map(), map()) :: {:ok, binary()} | {:error, binary()}
  def edit_file(%{"path" => path, "old_str" => old, "new_str" => new} = args, _ctx) do
    with true <- File.exists?(path) or {:error, "`path` does not exist"},
         true <- old != new or {:error, "`old_str` and `new_str` must differ"},
         {:ok, original} <- File.read(path),
         true <- String.contains?(original, old) or {:error, "`old_str` not found in file"} do
      replace_all? = Map.get(args, "replace_all", false)
      updated = perform_replace(original, old, new, replace_all?)
      :ok = File.write!(path, updated)

      diff_raw =
        TextDiff.format(original, updated,
          color: false,
          line_numbers: true,
          before: 2,
          after: 2
        )
        |> IO.iodata_to_binary()

      {range_start, range_end} = line_range(diff_raw)

      diff_md = """
      ```diff
      #{diff_raw}
      ```

      **Changed lines:** [#{range_start}, #{range_end}]
      """

      {:ok, diff_md}
    else
      {:error, reason} -> {:error, to_string(reason)}
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------
  defp perform_replace(text, old, new, true), do: String.replace(text, old, new)
  defp perform_replace(text, old, new, false), do: String.replace(text, old, new, global: false)

  defp line_range(diff) do
    diff
    |> String.split("\n")
    |> Enum.reduce([], fn line, acc ->
      case Regex.run(~r/^[\-\+]\s*(\d+):/, line) do
        [_, num] -> [String.to_integer(num) | acc]
        _ -> acc
      end
    end)
    |> case do
      [] -> {0, 0}
      nums -> {Enum.min(nums), Enum.max(nums)}
    end
  end
end
