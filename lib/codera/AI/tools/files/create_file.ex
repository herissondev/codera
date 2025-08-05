defmodule Codera.AI.Tools.Files.CreateFile do
  @moduledoc """
  Create or overwrite a file in the workspace.

  Use this tool when you want to create a new file with the given content, or when you want to replace the contents of an existing file.

  Prefer this tool over `edit_file` when you want to overwrite the entire contents of a file.
  """

  alias LangChain.Function
  alias LangChain.FunctionParam

  # ---------------------------------------------------------------------------
  # Registration
  # ---------------------------------------------------------------------------
  def create_file_tool!() do
    Function.new!(%{
      name: "create_file",
      display_text: "Create file",
      description: @moduledoc,
      parameters: [
        FunctionParam.new!(%{
          name: "path",
          type: :string,
          description: "Absolute file path to create or overwrite"
        }),
        FunctionParam.new!(%{
          name: "content",
          type: :string,
          description: "Content to write to the file"
        })
      ],
      function: &create_file/2,
      async: true
    })
  end

  # ---------------------------------------------------------------------------
  # Callback
  # ---------------------------------------------------------------------------
  @spec create_file(map(), map()) :: {:ok, binary()} | {:error, binary()}
  def create_file(%{"path" => path, "content" => content}, _ctx) do
    dir = Path.dirname(path)

    with true <- String.starts_with?(path, "/") or {:error, "`path` must be absolute"},
         true <- File.dir?(dir) or {:error, "Directory #{dir} does not exist"} do
      case File.write(path, content) do
        :ok -> {:ok, "File written to #{path}"}
        {:error, reason} -> {:error, to_string(reason)}
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end
end
