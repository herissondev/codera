defmodule Codera.AI.Tools.Files.ListDirectory do
  @moduledoc """
  List the files in the workspace in a given directory. Use the `glob` tool for filtering files by pattern.
  """

  alias LangChain.Function
  alias LangChain.FunctionParam

  # ---------------------------------------------------------------------------
  # Registration
  # ---------------------------------------------------------------------------
  def list_directory_tool!() do
    Function.new!(%{
      name: "list_directory",
      display_text: "List directory",
      description: @moduledoc,
      parameters: [
        FunctionParam.new!(%{
          name: "path",
          type: :string,
          description: "Absolute directory path to list"
        })
      ],
      function: &list_directory/2
    })
  end


  # ---------------------------------------------------------------------------
  # Callback
  # ---------------------------------------------------------------------------
  @spec list_directory(map(), map()) :: {:ok, binary()} | {:error, binary()}
  def list_directory(params, _ctx) do
    path =
      case params do
        %{"path" => p} -> p
        %{path: p} -> p
        _ -> nil
      end

    with true <-
           (is_binary(path) and String.trim(path) != "") or
             {:error, "`path` is required and cannot be blank"},
         true <- String.starts_with?(path, "/") or {:error, "`path` must be absolute"},
         true <- File.dir?(path) or {:error, "#{path} is not a directory"},
         {:ok, entries} <- File.ls(path) do
      sorted = Enum.sort(entries)

      content =
        case Enum.join(sorted, "\n") do
          "" -> "[]"
          s -> s
        end

      {:ok, content}
    else
      {:error, reason} -> {:error, to_string(reason)}
    end
  end
end
