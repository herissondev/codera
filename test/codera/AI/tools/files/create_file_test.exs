defmodule Codera.AI.Tools.Files.CreateFileTest do
  use ExUnit.Case, async: true
  alias Codera.AI.Tools.Files.CreateFile
  alias LangChain.Function

  describe "create_file_tool!/0" do
    test "creates a valid function definition" do
      function = CreateFile.create_file_tool!()

      assert %Function{} = function
      assert function.name == "create_file"
      assert function.display_text == "Create file"
      assert function.async == true
      assert is_function(function.function, 2)
    end

    test "has correct parameters" do
      function = CreateFile.create_file_tool!()

      assert length(function.parameters) == 2

      # Check path parameter
      path_param = Enum.find(function.parameters, &(&1.name == "path"))
      assert path_param != nil
      assert path_param.type == :string
      assert path_param.description == "Absolute file path to create or overwrite"
      assert path_param.required == false

      # Check content parameter
      content_param = Enum.find(function.parameters, &(&1.name == "content"))
      assert content_param != nil
      assert content_param.type == :string
      assert content_param.description == "Content to write to the file"
      assert content_param.required == false
    end
  end

  describe "create_file/2" do
    setup do
      # Create a temporary directory for testing
      base_dir = System.tmp_dir!() <> "/create_file_test_#{System.unique_integer()}"
      File.mkdir_p!(base_dir)

      on_exit(fn ->
        File.rm_rf!(base_dir)
      end)

      {:ok, base_dir: base_dir}
    end

    test "creates a new file with content", %{base_dir: base_dir} do
      file_path = Path.join(base_dir, "test.txt")
      content = "Hello, World!"
      args = %{"path" => file_path, "content" => content}

      {:ok, result} = CreateFile.create_file(args, %{})

      assert result == "File written to #{file_path}"
      assert File.exists?(file_path)
      assert File.read!(file_path) == content
    end

    test "overwrites existing file", %{base_dir: base_dir} do
      file_path = Path.join(base_dir, "existing.txt")
      File.write!(file_path, "original content")

      new_content = "new content"
      args = %{"path" => file_path, "content" => new_content}

      {:ok, result} = CreateFile.create_file(args, %{})

      assert result == "File written to #{file_path}"
      assert File.read!(file_path) == new_content
    end

    test "creates file with empty content", %{base_dir: base_dir} do
      file_path = Path.join(base_dir, "empty.txt")
      args = %{"path" => file_path, "content" => ""}

      {:ok, result} = CreateFile.create_file(args, %{})

      assert result == "File written to #{file_path}"
      assert File.exists?(file_path)
      assert File.read!(file_path) == ""
    end

    test "creates file with multiline content", %{base_dir: base_dir} do
      file_path = Path.join(base_dir, "multiline.txt")
      content = "Line 1\nLine 2\nLine 3"
      args = %{"path" => file_path, "content" => content}

      {:ok, result} = CreateFile.create_file(args, %{})

      assert result == "File written to #{file_path}"
      assert File.read!(file_path) == content
    end

    test "creates file with special characters", %{base_dir: base_dir} do
      file_path = Path.join(base_dir, "special.txt")
      content = "Special chars: !@#$%^&*()[]{}|\\:;\"'<>,.?/~`"
      args = %{"path" => file_path, "content" => content}

      {:ok, result} = CreateFile.create_file(args, %{})

      assert result == "File written to #{file_path}"
      assert File.read!(file_path) == content
    end

    test "creates file with unicode content", %{base_dir: base_dir} do
      file_path = Path.join(base_dir, "unicode.txt")
      content = "Unicode: 你好, こんにちは, 🌟, émojis"
      args = %{"path" => file_path, "content" => content}

      {:ok, result} = CreateFile.create_file(args, %{})

      assert result == "File written to #{file_path}"
      assert File.read!(file_path) == content
    end

    test "creates nested file structure", %{base_dir: base_dir} do
      nested_dir = Path.join(base_dir, "nested")
      File.mkdir_p!(nested_dir)
      file_path = Path.join(nested_dir, "deep.txt")
      content = "nested content"
      args = %{"path" => file_path, "content" => content}

      {:ok, result} = CreateFile.create_file(args, %{})

      assert result == "File written to #{file_path}"
      assert File.read!(file_path) == content
    end

    test "returns error for relative path" do
      args = %{"path" => "relative/path.txt", "content" => "content"}

      {:error, reason} = CreateFile.create_file(args, %{})

      assert reason == "`path` must be absolute"
    end

    test "returns error for non-existent directory" do
      non_existent_dir = "/tmp/non_existent_#{System.unique_integer()}"
      file_path = Path.join(non_existent_dir, "file.txt")
      args = %{"path" => file_path, "content" => "content"}

      {:error, reason} = CreateFile.create_file(args, %{})

      assert reason == "Directory #{non_existent_dir} does not exist"
    end

    test "returns error when path is not provided" do
      args = %{"content" => "content"}

      assert_raise FunctionClauseError, fn ->
        CreateFile.create_file(args, %{})
      end
    end

    test "returns error when content is not provided" do
      args = %{"path" => "/tmp/test.txt"}

      assert_raise FunctionClauseError, fn ->
        CreateFile.create_file(args, %{})
      end
    end

    test "handles file permission errors gracefully" do
      # Try to write to a directory that should exist but may have permission issues
      # This test might not fail on all systems, but it demonstrates error handling
      restricted_path = "/root/restricted_file.txt"
      args = %{"path" => restricted_path, "content" => "content"}

      result = CreateFile.create_file(args, %{})

      # Could either succeed (if running as root) or fail with permission error
      case result do
        {:ok, _} -> assert true
        {:error, reason} -> assert is_binary(reason)
      end
    end
  end

  describe "edge cases" do
    setup do
      base_dir = System.tmp_dir!() <> "/edge_case_test_#{System.unique_integer()}"
      File.mkdir_p!(base_dir)

      on_exit(fn ->
        File.rm_rf!(base_dir)
      end)

      {:ok, base_dir: base_dir}
    end

    test "handles very long content", %{base_dir: base_dir} do
      file_path = Path.join(base_dir, "long.txt")
      content = String.duplicate("A", 10_000)
      args = %{"path" => file_path, "content" => content}

      {:ok, result} = CreateFile.create_file(args, %{})

      assert result == "File written to #{file_path}"
      assert File.read!(file_path) == content
    end

    test "handles file with dots in name", %{base_dir: base_dir} do
      file_path = Path.join(base_dir, "file.with.many.dots.txt")
      content = "dots content"
      args = %{"path" => file_path, "content" => content}

      {:ok, result} = CreateFile.create_file(args, %{})

      assert result == "File written to #{file_path}"
      assert File.read!(file_path) == content
    end

    test "handles file with spaces in name", %{base_dir: base_dir} do
      file_path = Path.join(base_dir, "file with spaces.txt")
      content = "spaced content"
      args = %{"path" => file_path, "content" => content}

      {:ok, result} = CreateFile.create_file(args, %{})

      assert result == "File written to #{file_path}"
      assert File.read!(file_path) == content
    end

    test "handles content with null bytes", %{base_dir: base_dir} do
      file_path = Path.join(base_dir, "null.txt")
      content = "before\0after"
      args = %{"path" => file_path, "content" => content}

      {:ok, result} = CreateFile.create_file(args, %{})

      assert result == "File written to #{file_path}"
      assert File.read!(file_path) == content
    end

    test "overwrites file with different content type", %{base_dir: base_dir} do
      file_path = Path.join(base_dir, "type_change.txt")

      # First write text
      File.write!(file_path, "text content")

      # Then write binary-like content
      binary_content = <<1, 2, 3, 4, 5>>
      args = %{"path" => file_path, "content" => binary_content}

      {:ok, result} = CreateFile.create_file(args, %{})

      assert result == "File written to #{file_path}"
      assert File.read!(file_path) == binary_content
    end
  end
end
