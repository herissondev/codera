defmodule Codera.AI.Tools.Files do
  # alias Codera.AI.Tools.Files.ListFiles
  alias Codera.AI.Tools.Files.Glob
  alias Codera.AI.Tools.Files.CreateFile
  alias Codera.AI.Tools.Files.ListDirectory
  alias Codera.AI.Tools.Files.EditFile
  alias Codera.AI.Tools.Files.ReadFile

  def all_files_tools!() do
    [
      ReadFile.read_file_tool!(),
      EditFile.edit_file_tool!(),
      ListDirectory.list_directory_tool!(),
      CreateFile.create_file_tool!(),
      Glob.glob_tool!()
      # ListFiles.list_files_tool!()
    ]
  end
end
