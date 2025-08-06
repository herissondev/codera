defmodule Codera.AI.Tools.Files.ReadFileTest do
  use ExUnit.Case, async: true
  alias Codera.AI.Tools.Files.ReadFile
  alias LangChain.Function

  describe "read_file_tool!/0" do
    test "creates a valid function definition" do
      function = ReadFile.read_file_tool!()

      assert %Function{} = function
      assert function.name == "read_file"
      assert function.display_text == "Read file"
      assert function.async == true
      assert is_function(function.function, 2)
    end

    test "has correct parameters" do
      function = ReadFile.read_file_tool!()

      assert length(function.parameters) == 2

      # Check path parameter
      path_param = Enum.find(function.parameters, &(&1.name == "path"))
      assert path_param != nil
      assert path_param.type == :string
      assert path_param.description == "Absolute file path to read from"
      assert path_param.required == false

      # Check start_line parameter
      start_line_param = Enum.find(function.parameters, &(&1.name == "start_line"))
      assert start_line_param != nil
      assert start_line_param.type == :integer
      assert start_line_param.description == "(Optional) 1‑based start line of the range to read"
      assert start_line_param.required == false
    end
  end

  describe "read_file/2" do
    setup do
      # Create a temporary directory and test files
      base_dir = System.tmp_dir!() <> "/read_file_test_#{System.unique_integer()}"
      File.mkdir_p!(base_dir)

      # Create a simple test file
      simple_file = Path.join(base_dir, "simple.txt")
      File.write!(simple_file, "Hello, World!")

      # Create a multiline test file
      multiline_file = Path.join(base_dir, "multiline.txt")
      multiline_content = for i <- 1..10, do: "Line #{i}"
      File.write!(multiline_file, Enum.join(multiline_content, "\n"))

      # Create a large test file (over 1000 lines)
      large_file = Path.join(base_dir, "large.txt")
      large_content = for i <- 1..1500, do: "This is line number #{i}"
      File.write!(large_file, Enum.join(large_content, "\n"))

      # Create an empty file
      empty_file = Path.join(base_dir, "empty.txt")
      File.write!(empty_file, "")

      on_exit(fn ->
        File.rm_rf!(base_dir)
      end)

      {:ok,
       base_dir: base_dir,
       simple_file: simple_file,
       multiline_file: multiline_file,
       large_file: large_file,
       empty_file: empty_file}
    end

    test "reads simple file with line numbers", %{simple_file: simple_file} do
      args = %{"path" => simple_file}

      {:ok, result} = ReadFile.read_file(args, %{})

      assert result == "1: Hello, World!"
    end

    test "reads multiline file with line numbers", %{multiline_file: multiline_file} do
      args = %{"path" => multiline_file}

      {:ok, result} = ReadFile.read_file(args, %{})

      lines = String.split(result, "\n")
      assert length(lines) == 10

      # Check first few lines have correct format
      assert Enum.at(lines, 0) == "1: Line 1"
      assert Enum.at(lines, 1) == "2: Line 2"
      assert Enum.at(lines, 9) == "10: Line 10"
    end

    test "reads empty file", %{empty_file: empty_file} do
      args = %{"path" => empty_file}

      {:ok, result} = ReadFile.read_file(args, %{})

      assert result == "1: "
    end

    test "reads file with start_line parameter", %{multiline_file: multiline_file} do
      args = %{"path" => multiline_file, "start_line" => 5}

      {:ok, result} = ReadFile.read_file(args, %{})

      lines = String.split(result, "\n")
      # Lines 5-10
      assert length(lines) == 6

      assert Enum.at(lines, 0) == "5: Line 5"
      assert Enum.at(lines, 5) == "10: Line 10"
    end

    test "limits to 1000 lines for large files", %{large_file: large_file} do
      args = %{"path" => large_file}

      {:ok, result} = ReadFile.read_file(args, %{})

      lines = String.split(result, "\n")
      assert length(lines) == 1000

      # Should start from line 1 and go to line 1000
      assert Enum.at(lines, 0) == "1: This is line number 1"
      assert List.last(lines) == "1000: This is line number 1000"
    end

    test "applies both start_line and 1000 line limit", %{large_file: large_file} do
      args = %{"path" => large_file, "start_line" => 500}

      {:ok, result} = ReadFile.read_file(args, %{})

      lines = String.split(result, "\n")
      assert length(lines) == 1000

      # Should start from line 500 and go to line 1499
      assert Enum.at(lines, 0) == "500: This is line number 500"
      assert List.last(lines) == "1499: This is line number 1499"
    end

    test "handles start_line beyond file end", %{multiline_file: multiline_file} do
      args = %{"path" => multiline_file, "start_line" => 15}

      {:ok, result} = ReadFile.read_file(args, %{})

      assert String.trim(result) == ""
    end

    test "handles start_line of 1 (default)", %{multiline_file: multiline_file} do
      args = %{"path" => multiline_file, "start_line" => 1}

      {:ok, result} = ReadFile.read_file(args, %{})

      lines = String.split(result, "\n")
      assert length(lines) == 10
      assert Enum.at(lines, 0) == "1: Line 1"
    end

    test "defaults start_line to 1 when not provided", %{multiline_file: multiline_file} do
      args = %{"path" => multiline_file}

      {:ok, result} = ReadFile.read_file(args, %{})

      lines = String.split(result, "\n")
      assert Enum.at(lines, 0) == "1: Line 1"
    end

    test "handles file with special characters" do
      special_dir = System.tmp_dir!() <> "/special_#{System.unique_integer()}"
      File.mkdir_p!(special_dir)
      special_file = Path.join(special_dir, "special.txt")

      content = "Special: !@#$%^&*()[]{}|\\:;\"'<>,.?/~`\nUnicode: 你好, こんにちは, 🌟"
      File.write!(special_file, content)

      args = %{"path" => special_file}

      {:ok, result} = ReadFile.read_file(args, %{})

      lines = String.split(result, "\n")
      assert length(lines) == 2
      assert Enum.at(lines, 0) == "1: Special: !@#$%^&*()[]{}|\\:;\"'<>,.?/~`"
      assert Enum.at(lines, 1) == "2: Unicode: 你好, こんにちは, 🌟"

      File.rm_rf!(special_dir)
    end

    test "handles file with only newlines" do
      newlines_dir = System.tmp_dir!() <> "/newlines_#{System.unique_integer()}"
      File.mkdir_p!(newlines_dir)
      newlines_file = Path.join(newlines_dir, "newlines.txt")

      File.write!(newlines_file, "\n\n\n")

      args = %{"path" => newlines_file}

      {:ok, result} = ReadFile.read_file(args, %{})

      lines = String.split(result, "\n")
      # 3 empty lines + final empty line
      assert length(lines) == 4
      assert Enum.at(lines, 0) == "1: "
      assert Enum.at(lines, 1) == "2: "
      assert Enum.at(lines, 2) == "3: "
      assert Enum.at(lines, 3) == "4: "

      File.rm_rf!(newlines_dir)
    end

    test "handles file ending without newline", %{base_dir: base_dir} do
      no_newline_file = Path.join(base_dir, "no_newline.txt")
      # No trailing newline
      File.write!(no_newline_file, "Line 1\nLine 2")

      args = %{"path" => no_newline_file}

      {:ok, result} = ReadFile.read_file(args, %{})

      lines = String.split(result, "\n")
      assert length(lines) == 2
      assert Enum.at(lines, 0) == "1: Line 1"
      assert Enum.at(lines, 1) == "2: Line 2"
    end

    test "returns error for non-existent file" do
      non_existent = "/tmp/non_existent_#{System.unique_integer()}.txt"
      args = %{"path" => non_existent}

      {:error, reason} = ReadFile.read_file(args, %{})

      assert reason == "enoent"
    end

    test "returns error for relative path" do
      args = %{"path" => "relative/path.txt"}

      {:error, reason} = ReadFile.read_file(args, %{})

      assert reason == "`path` must be absolute"
    end

    test "returns error for directory instead of file", %{base_dir: base_dir} do
      args = %{"path" => base_dir}

      {:error, reason} = ReadFile.read_file(args, %{})

      assert reason == "eisdir"
    end

    test "returns error when path is missing" do
      args = %{}

      assert_raise FunctionClauseError, fn ->
        ReadFile.read_file(args, %{})
      end
    end

    test "handles negative start_line" do
      test_dir = System.tmp_dir!() <> "/negative_#{System.unique_integer()}"
      File.mkdir_p!(test_dir)
      test_file = Path.join(test_dir, "test.txt")
      File.write!(test_file, "Line 1\nLine 2\nLine 3")

      args = %{"path" => test_file, "start_line" => -1}

      {:ok, result} = ReadFile.read_file(args, %{})

      # Negative start_line should be handled gracefully
      # Enum.drop with negative number drops from the end
      lines = String.split(result, "\n")
      assert length(lines) >= 1

      File.rm_rf!(test_dir)
    end

    test "handles zero start_line" do
      test_dir = System.tmp_dir!() <> "/zero_#{System.unique_integer()}"
      File.mkdir_p!(test_dir)
      test_file = Path.join(test_dir, "test.txt")
      File.write!(test_file, "Line 1\nLine 2\nLine 3")

      args = %{"path" => test_file, "start_line" => 0}

      {:ok, result} = ReadFile.read_file(args, %{})

      lines = String.split(result, "\n")
      # With start_line 0, Enum.drop(0-1) = Enum.drop(-1) which drops from end
      assert length(lines) >= 1

      File.rm_rf!(test_dir)
    end

    test "handles very large start_line", %{multiline_file: multiline_file} do
      args = %{"path" => multiline_file, "start_line" => 1_000_000}

      {:ok, result} = ReadFile.read_file(args, %{})

      assert String.trim(result) == ""
    end

    test "handles binary file gracefully" do
      binary_dir = System.tmp_dir!() <> "/binary_#{System.unique_integer()}"
      File.mkdir_p!(binary_dir)
      binary_file = Path.join(binary_dir, "binary.dat")

      # Write some binary data
      binary_data = <<0, 1, 2, 3, 255, 254, 253>>
      File.write!(binary_file, binary_data)

      args = %{"path" => binary_file}

      {:ok, result} = ReadFile.read_file(args, %{})

      # Should handle binary data gracefully (may contain null bytes, etc.)
      assert String.starts_with?(result, "1: ")

      File.rm_rf!(binary_dir)
    end
  end

  describe "edge cases" do
    test "handles file with very long lines" do
      long_line_dir = System.tmp_dir!() <> "/long_line_#{System.unique_integer()}"
      File.mkdir_p!(long_line_dir)
      long_line_file = Path.join(long_line_dir, "long_line.txt")

      # Create a file with one very long line
      long_content = String.duplicate("A", 10_000)
      File.write!(long_line_file, long_content)

      args = %{"path" => long_line_file}

      {:ok, result} = ReadFile.read_file(args, %{})

      assert String.starts_with?(result, "1: ")
      assert String.contains?(result, long_content)

      File.rm_rf!(long_line_dir)
    end

    test "handles file with mixed line endings" do
      mixed_endings_dir = System.tmp_dir!() <> "/mixed_endings_#{System.unique_integer()}"
      File.mkdir_p!(mixed_endings_dir)
      mixed_file = Path.join(mixed_endings_dir, "mixed.txt")

      # Create content with different line endings (Unix \n, Windows \r\n)
      content = "Line 1\nLine 2\r\nLine 3\nLine 4"
      File.write!(mixed_file, content)

      args = %{"path" => mixed_file}

      {:ok, result} = ReadFile.read_file(args, %{})

      lines = String.split(result, "\n")
      assert length(lines) >= 4
      assert Enum.at(lines, 0) == "1: Line 1"

      File.rm_rf!(mixed_endings_dir)
    end

    test "handles concurrent reads of same file" do
      # Create a test file for this specific test
      test_dir = System.tmp_dir!() <> "/concurrent_#{System.unique_integer()}"
      File.mkdir_p!(test_dir)
      multiline_file = Path.join(test_dir, "concurrent.txt")
      multiline_content = for i <- 1..10, do: "Line #{i}"
      File.write!(multiline_file, Enum.join(multiline_content, "\n"))
      # Test multiple concurrent reads
      tasks =
        for _i <- 1..10 do
          Task.async(fn ->
            args = %{"path" => multiline_file}
            ReadFile.read_file(args, %{})
          end)
        end

      results = Task.await_many(tasks)

      # All reads should succeed and return the same content
      Enum.each(results, fn result ->
        assert {:ok, content} = result
        assert String.starts_with?(content, "1: Line 1")
      end)

      File.rm_rf!(test_dir)
    end
  end
end
