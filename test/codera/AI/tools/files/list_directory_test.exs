defmodule Codera.AI.Tools.Files.ListDirectoryTest do
  use ExUnit.Case, async: true
  alias Codera.AI.Tools.Files.ListDirectory
  alias LangChain.Function

  describe "list_directory_tool!/0" do
    test "creates a valid function definition" do
      function = ListDirectory.list_directory_tool!()

      assert %Function{} = function
      assert function.name == "list_directory"
      assert function.display_text == "List directory"
      assert function.async == true
      assert is_function(function.function, 2)
    end

    test "has correct parameters" do
      function = ListDirectory.list_directory_tool!()

      assert length(function.parameters) == 1

      # Check path parameter
      path_param = Enum.find(function.parameters, &(&1.name == "path"))
      assert path_param != nil
      assert path_param.type == :string
      assert path_param.description == "Absolute directory path to list"
      assert path_param.required == false
    end
  end

  describe "list_directory/2" do
    setup do
      # Create a temporary directory structure for testing
      base_dir = System.tmp_dir!() <> "/list_dir_test_#{System.unique_integer()}"
      File.mkdir_p!(base_dir)

      # Create test files and directories
      File.write!(Path.join(base_dir, "file1.txt"), "content1")
      File.write!(Path.join(base_dir, "file2.js"), "content2")
      File.write!(Path.join(base_dir, "zzz_last.md"), "content3")
      File.write!(Path.join(base_dir, "aaa_first.ex"), "content4")
      File.mkdir_p!(Path.join(base_dir, "subdir1"))
      File.mkdir_p!(Path.join(base_dir, "subdir2"))

      on_exit(fn ->
        File.rm_rf!(base_dir)
      end)

      {:ok, base_dir: base_dir}
    end

    test "lists directory contents in sorted order", %{base_dir: base_dir} do
      args = %{"path" => base_dir}

      {:ok, result} = ListDirectory.list_directory(args, %{})

      entries = String.split(result, "\n")

      # Should be sorted alphabetically
      expected = ["aaa_first.ex", "file1.txt", "file2.js", "subdir1", "subdir2", "zzz_last.md"]
      assert entries == expected
    end

    test "accepts string key parameters", %{base_dir: base_dir} do
      args = %{"path" => base_dir}

      {:ok, result} = ListDirectory.list_directory(args, %{})

      assert is_binary(result)
      assert String.contains?(result, "file1.txt")
    end

    test "accepts atom key parameters", %{base_dir: base_dir} do
      args = %{path: base_dir}

      {:ok, result} = ListDirectory.list_directory(args, %{})

      assert is_binary(result)
      assert String.contains?(result, "file1.txt")
    end

    test "returns empty directory indicator for empty directory" do
      empty_dir = System.tmp_dir!() <> "/empty_#{System.unique_integer()}"
      File.mkdir_p!(empty_dir)

      args = %{"path" => empty_dir}

      {:ok, result} = ListDirectory.list_directory(args, %{})

      assert result == "[]"

      File.rm_rf!(empty_dir)
    end

    test "includes hidden files (dot files)" do
      hidden_dir = System.tmp_dir!() <> "/hidden_test_#{System.unique_integer()}"
      File.mkdir_p!(hidden_dir)
      File.write!(Path.join(hidden_dir, ".hidden"), "hidden content")
      File.write!(Path.join(hidden_dir, "visible.txt"), "visible content")

      args = %{"path" => hidden_dir}

      {:ok, result} = ListDirectory.list_directory(args, %{})

      entries = String.split(result, "\n")
      assert ".hidden" in entries
      assert "visible.txt" in entries

      File.rm_rf!(hidden_dir)
    end

    test "handles directory with special characters in filenames" do
      special_dir = System.tmp_dir!() <> "/special_#{System.unique_integer()}"
      File.mkdir_p!(special_dir)

      special_files = [
        "file with spaces.txt",
        "file-with-dashes.txt",
        "file_with_underscores.txt",
        "file.with.dots.txt",
        "file@symbol.txt"
      ]

      Enum.each(special_files, fn filename ->
        File.write!(Path.join(special_dir, filename), "content")
      end)

      args = %{"path" => special_dir}

      {:ok, result} = ListDirectory.list_directory(args, %{})

      entries = String.split(result, "\n")

      Enum.each(special_files, fn filename ->
        assert filename in entries
      end)

      File.rm_rf!(special_dir)
    end

    test "handles directory with unicode filenames" do
      unicode_dir = System.tmp_dir!() <> "/unicode_#{System.unique_integer()}"
      File.mkdir_p!(unicode_dir)

      unicode_files = ["файл.txt", "こんにちは.txt", "🌟.txt"]

      Enum.each(unicode_files, fn filename ->
        File.write!(Path.join(unicode_dir, filename), "content")
      end)

      args = %{"path" => unicode_dir}

      {:ok, result} = ListDirectory.list_directory(args, %{})

      entries = String.split(result, "\n")

      Enum.each(unicode_files, fn filename ->
        assert filename in entries
      end)

      File.rm_rf!(unicode_dir)
    end

    test "returns error for non-existent directory" do
      non_existent = "/tmp/non_existent_#{System.unique_integer()}"
      args = %{"path" => non_existent}

      {:error, reason} = ListDirectory.list_directory(args, %{})

      assert reason == "#{non_existent} is not a directory"
    end

    test "returns error for file instead of directory", %{base_dir: base_dir} do
      file_path = Path.join(base_dir, "regular_file.txt")
      File.write!(file_path, "content")

      args = %{"path" => file_path}

      {:error, reason} = ListDirectory.list_directory(args, %{})

      assert reason == "#{file_path} is not a directory"
    end

    test "returns error for relative path" do
      args = %{"path" => "relative/path"}

      {:error, reason} = ListDirectory.list_directory(args, %{})

      assert reason == "`path` must be absolute"
    end

    test "returns error for empty path" do
      args = %{"path" => ""}

      {:error, reason} = ListDirectory.list_directory(args, %{})

      assert reason == "`path` is required and cannot be blank"
    end

    test "returns error for whitespace-only path" do
      args = %{"path" => "   "}

      {:error, reason} = ListDirectory.list_directory(args, %{})

      assert reason == "`path` is required and cannot be blank"
    end

    test "returns error when path parameter is missing" do
      args = %{}

      {:error, reason} = ListDirectory.list_directory(args, %{})

      assert reason == "`path` is required and cannot be blank"
    end

    test "returns error when path is not a string" do
      args = %{"path" => 123}

      {:error, reason} = ListDirectory.list_directory(args, %{})

      assert reason == "`path` is required and cannot be blank"
    end

    test "returns error when path is nil" do
      args = %{"path" => nil}

      {:error, reason} = ListDirectory.list_directory(args, %{})

      assert reason == "`path` is required and cannot be blank"
    end

    test "handles very deep directory structure" do
      deep_dir = System.tmp_dir!() <> "/deep_#{System.unique_integer()}"
      very_deep_path = Path.join([deep_dir, "a", "b", "c", "d", "e"])
      File.mkdir_p!(very_deep_path)
      File.write!(Path.join(very_deep_path, "deep_file.txt"), "content")

      args = %{"path" => very_deep_path}

      {:ok, result} = ListDirectory.list_directory(args, %{})

      assert result == "deep_file.txt"

      File.rm_rf!(deep_dir)
    end

    test "handles directory with many files", %{base_dir: base_dir} do
      many_files_dir = Path.join(base_dir, "many_files")
      File.mkdir_p!(many_files_dir)

      # Create 50 files
      file_names = for i <- 1..50, do: "file_#{String.pad_leading(to_string(i), 2, "0")}.txt"

      Enum.each(file_names, fn filename ->
        File.write!(Path.join(many_files_dir, filename), "content")
      end)

      args = %{"path" => many_files_dir}

      {:ok, result} = ListDirectory.list_directory(args, %{})

      entries = String.split(result, "\n")
      assert length(entries) == 50

      # Should be properly sorted
      assert List.first(entries) == "file_01.txt"
      assert List.last(entries) == "file_50.txt"
    end
  end

  describe "edge cases" do
    test "handles directory with mixed file types" do
      mixed_dir = System.tmp_dir!() <> "/mixed_#{System.unique_integer()}"
      File.mkdir_p!(mixed_dir)

      # Create different types of entries
      File.write!(Path.join(mixed_dir, "regular_file.txt"), "content")
      File.mkdir_p!(Path.join(mixed_dir, "directory"))
      File.mkdir_p!(Path.join(mixed_dir, "another_dir"))

      # Create a symlink if supported on the system
      symlink_path = Path.join(mixed_dir, "symlink")

      case File.ln_s(Path.join(mixed_dir, "regular_file.txt"), symlink_path) do
        :ok -> :ok
        # Symlinks might not be supported
        {:error, _} -> :ok
      end

      args = %{"path" => mixed_dir}

      {:ok, result} = ListDirectory.list_directory(args, %{})

      entries = String.split(result, "\n")
      assert "regular_file.txt" in entries
      assert "directory" in entries
      assert "another_dir" in entries

      # Symlink might or might not be present depending on system support
      # We don't assert on it specifically

      File.rm_rf!(mixed_dir)
    end

    test "handles directory with no read permissions" do
      # This test may behave differently based on system permissions
      # We test the error handling gracefully
      # Commonly restricted directory
      restricted_dir = "/root"
      args = %{"path" => restricted_dir}

      result = ListDirectory.list_directory(args, %{})

      # Should either succeed (if we have permissions) or fail gracefully
      case result do
        {:ok, _content} -> assert true
        {:error, reason} -> assert is_binary(reason)
      end
    end
  end
end
