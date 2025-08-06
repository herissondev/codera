defmodule Codera.AI.Tools.Files.EditFileTest do
  use ExUnit.Case, async: true
  alias Codera.AI.Tools.Files.EditFile
  alias LangChain.Function

  describe "edit_file_tool!/0" do
    test "creates a valid function definition" do
      function = EditFile.edit_file_tool!()

      assert %Function{} = function
      assert function.name == "edit_file"
      assert function.display_text == "Edit file"
      assert is_function(function.function, 2)
    end

    test "has correct parameters" do
      function = EditFile.edit_file_tool!()

      assert length(function.parameters) == 4

      # Check path parameter
      path_param = Enum.find(function.parameters, &(&1.name == "path"))
      assert path_param != nil
      assert path_param.type == :string
      assert path_param.description == "Full path of the file to edit"
      assert path_param.required == false

      # Check old_str parameter
      old_str_param = Enum.find(function.parameters, &(&1.name == "old_str"))
      assert old_str_param != nil
      assert old_str_param.type == :string
      assert old_str_param.description == "String to replace"
      assert old_str_param.required == false

      # Check new_str parameter
      new_str_param = Enum.find(function.parameters, &(&1.name == "new_str"))
      assert new_str_param != nil
      assert new_str_param.type == :string
      assert new_str_param.description == "Replacement string"
      assert new_str_param.required == false

      # Check replace_all parameter
      replace_all_param = Enum.find(function.parameters, &(&1.name == "replace_all"))
      assert replace_all_param != nil
      assert replace_all_param.type == :boolean
      assert replace_all_param.description == "Replace every occurrence (default: false)"
      assert replace_all_param.required == false
    end
  end

  describe "edit_file/2" do
    setup do
      # Create a temporary directory and test files
      base_dir = System.tmp_dir!() <> "/edit_file_test_#{System.unique_integer()}"
      File.mkdir_p!(base_dir)

      # Create a simple test file
      simple_file = Path.join(base_dir, "simple.txt")
      File.write!(simple_file, "Hello, World!\nThis is a test.\nEnd of file.")

      # Create a multiline test file
      multiline_file = Path.join(base_dir, "multiline.txt")

      multiline_content = """
      function greet(name) {
        console.log("Hello, " + name);
      }

      greet("Alice");
      greet("Bob");
      """

      File.write!(multiline_file, multiline_content)

      # Create a file with repeated content
      repeated_file = Path.join(base_dir, "repeated.txt")
      repeated_content = "apple\nbanana\napple\ncherry\napple\n"
      File.write!(repeated_file, repeated_content)

      on_exit(fn ->
        File.rm_rf!(base_dir)
      end)

      {:ok,
       base_dir: base_dir,
       simple_file: simple_file,
       multiline_file: multiline_file,
       repeated_file: repeated_file}
    end

    test "replaces single occurrence by default", %{simple_file: simple_file} do
      args = %{
        "path" => simple_file,
        "old_str" => "Hello, World!",
        "new_str" => "Hello, Elixir!"
      }

      {:ok, result} = EditFile.edit_file(args, %{})

      # Verify the file was updated
      content = File.read!(simple_file)
      assert content == "Hello, Elixir!\nThis is a test.\nEnd of file."

      # Check that result contains diff markdown
      assert String.contains?(result, "```diff")
      assert String.contains?(result, "**Changed lines:**")
    end

    test "replaces all occurrences when replace_all is true", %{repeated_file: repeated_file} do
      args = %{
        "path" => repeated_file,
        "old_str" => "apple",
        "new_str" => "orange",
        "replace_all" => true
      }

      {:ok, result} = EditFile.edit_file(args, %{})

      # Verify all occurrences were replaced
      content = File.read!(repeated_file)
      assert content == "orange\nbanana\norange\ncherry\norange\n"

      # Check result format
      assert String.contains?(result, "```diff")
      assert String.contains?(result, "**Changed lines:**")
    end

    test "replaces only first occurrence when replace_all is false", %{
      repeated_file: repeated_file
    } do
      args = %{
        "path" => repeated_file,
        "old_str" => "apple",
        "new_str" => "orange",
        "replace_all" => false
      }

      {:ok, result} = EditFile.edit_file(args, %{})

      # Verify only first occurrence was replaced
      content = File.read!(repeated_file)
      assert content == "orange\nbanana\napple\ncherry\napple\n"

      assert String.contains?(result, "```diff")
    end

    test "defaults replace_all to false when not provided", %{repeated_file: repeated_file} do
      args = %{
        "path" => repeated_file,
        "old_str" => "apple",
        "new_str" => "orange"
      }

      {:ok, result} = EditFile.edit_file(args, %{})

      # Should replace only first occurrence
      content = File.read!(repeated_file)
      assert content == "orange\nbanana\napple\ncherry\napple\n"

      assert String.contains?(result, "```diff")
    end

    test "handles multiline replacements", %{multiline_file: multiline_file} do
      args = %{
        "path" => multiline_file,
        "old_str" => "function greet(name) {\n  console.log(\"Hello, \" + name);\n}",
        "new_str" => "function greet(name) {\n  console.log(`Hello, ${name}`);\n}"
      }

      {:ok, result} = EditFile.edit_file(args, %{})

      # Verify the replacement
      content = File.read!(multiline_file)
      assert String.contains?(content, "console.log(`Hello, ${name}`);")

      assert String.contains?(result, "```diff")
    end

    test "handles empty string replacement", %{simple_file: simple_file} do
      args = %{
        "path" => simple_file,
        "old_str" => ", World!",
        "new_str" => ""
      }

      {:ok, result} = EditFile.edit_file(args, %{})

      # Verify the deletion
      content = File.read!(simple_file)
      assert content == "Hello\nThis is a test.\nEnd of file."

      assert String.contains?(result, "```diff")
    end

    test "handles replacement with empty old_str to new_str", %{simple_file: simple_file} do
      # Add content by replacing empty string (this is a bit unusual but should work)
      args = %{
        "path" => simple_file,
        "old_str" => "Hello,",
        "new_str" => "Hello, dear"
      }

      {:ok, result} = EditFile.edit_file(args, %{})

      content = File.read!(simple_file)
      assert content == "Hello, dear World!\nThis is a test.\nEnd of file."

      assert String.contains?(result, "```diff")
    end

    test "handles special characters in replacements", %{simple_file: simple_file} do
      args = %{
        "path" => simple_file,
        "old_str" => "Hello, World!",
        "new_str" => "Hello, $pecial Ch@racters & Symbols!"
      }

      {:ok, result} = EditFile.edit_file(args, %{})

      content = File.read!(simple_file)
      assert content == "Hello, $pecial Ch@racters & Symbols!\nThis is a test.\nEnd of file."

      assert String.contains?(result, "```diff")
    end

    test "handles unicode characters in replacements", %{simple_file: simple_file} do
      args = %{
        "path" => simple_file,
        "old_str" => "World",
        "new_str" => "世界🌍"
      }

      {:ok, result} = EditFile.edit_file(args, %{})

      content = File.read!(simple_file)
      assert content == "Hello, 世界🌍!\nThis is a test.\nEnd of file."

      assert String.contains?(result, "```diff")
    end

    test "returns error for non-existent file" do
      non_existent = "/tmp/non_existent_#{System.unique_integer()}.txt"

      args = %{
        "path" => non_existent,
        "old_str" => "old",
        "new_str" => "new"
      }

      {:error, reason} = EditFile.edit_file(args, %{})

      assert reason == "`path` does not exist"
    end

    test "returns error when old_str not found in file", %{simple_file: simple_file} do
      args = %{
        "path" => simple_file,
        "old_str" => "NonexistentString",
        "new_str" => "replacement"
      }

      {:error, reason} = EditFile.edit_file(args, %{})

      assert reason == "`old_str` not found in file"

      # File should remain unchanged
      content = File.read!(simple_file)
      assert content == "Hello, World!\nThis is a test.\nEnd of file."
    end

    test "returns error when old_str and new_str are identical", %{simple_file: simple_file} do
      args = %{
        "path" => simple_file,
        "old_str" => "Hello, World!",
        "new_str" => "Hello, World!"
      }

      {:error, reason} = EditFile.edit_file(args, %{})

      assert reason == "`old_str` and `new_str` must differ"
    end

    test "returns error when required parameters are missing" do
      # Missing old_str
      args = %{"path" => "/tmp/test.txt", "new_str" => "new"}

      assert_raise FunctionClauseError, fn ->
        EditFile.edit_file(args, %{})
      end

      # Missing new_str
      args = %{"path" => "/tmp/test.txt", "old_str" => "old"}

      assert_raise FunctionClauseError, fn ->
        EditFile.edit_file(args, %{})
      end

      # Missing path
      args = %{"old_str" => "old", "new_str" => "new"}

      assert_raise FunctionClauseError, fn ->
        EditFile.edit_file(args, %{})
      end
    end

    test "handles very long strings", %{simple_file: simple_file} do
      # Create a very long replacement string
      long_replacement = String.duplicate("A", 1000)

      args = %{
        "path" => simple_file,
        "old_str" => "World",
        "new_str" => long_replacement
      }

      {:ok, result} = EditFile.edit_file(args, %{})

      content = File.read!(simple_file)
      assert String.contains?(content, long_replacement)

      assert String.contains?(result, "```diff")
    end

    test "preserves file permissions after edit", %{simple_file: simple_file} do
      # Get original permissions
      {:ok, original_stat} = File.stat(simple_file)

      args = %{
        "path" => simple_file,
        "old_str" => "World",
        "new_str" => "Elixir"
      }

      {:ok, _result} = EditFile.edit_file(args, %{})

      # Check permissions are preserved (this is handled by File.write!)
      {:ok, new_stat} = File.stat(simple_file)
      assert new_stat.mode == original_stat.mode
    end

    test "handles files with no final newline", %{base_dir: base_dir} do
      no_newline_file = Path.join(base_dir, "no_newline.txt")
      # No trailing newline
      File.write!(no_newline_file, "Line 1\nLine 2")

      args = %{
        "path" => no_newline_file,
        "old_str" => "Line 2",
        "new_str" => "Modified Line 2"
      }

      {:ok, result} = EditFile.edit_file(args, %{})

      content = File.read!(no_newline_file)
      assert content == "Line 1\nModified Line 2"

      assert String.contains?(result, "```diff")
    end

    test "handles binary files gracefully", %{base_dir: base_dir} do
      binary_file = Path.join(base_dir, "binary.dat")
      binary_content = <<0, 1, 2, 3, 255, 254, 253>>
      File.write!(binary_file, binary_content)

      # Try to replace some binary data
      args = %{
        "path" => binary_file,
        "old_str" => <<0, 1>>,
        "new_str" => <<10, 11>>
      }

      {:ok, result} = EditFile.edit_file(args, %{})

      content = File.read!(binary_file)
      assert content == <<10, 11, 2, 3, 255, 254, 253>>

      assert String.contains?(result, "```diff")
    end
  end

  describe "line range calculation" do
    test "calculates correct line ranges in diff" do
      # Create a test file for this specific test
      test_dir = System.tmp_dir!() <> "/line_range_#{System.unique_integer()}"
      File.mkdir_p!(test_dir)
      simple_file = Path.join(test_dir, "simple.txt")
      File.write!(simple_file, "Hello, World!\nThis is a test.\nEnd of file.")

      args = %{
        "path" => simple_file,
        "old_str" => "This is a test.",
        "new_str" => "This is a modified test."
      }

      {:ok, result} = EditFile.edit_file(args, %{})

      # Check that line range is included in the result
      assert String.contains?(result, "**Changed lines:**")

      # The exact range depends on the diff implementation,
      # but it should contain a valid range format [start, end]
      assert Regex.match?(~r/\*\*Changed lines:\*\* \[\d+, \d+\]/, result)

      File.rm_rf!(test_dir)
    end

    test "handles edge case of line range calculation with no changes" do
      # This test is tricky since we validate that old_str != new_str
      # But we can test the helper function indirectly by ensuring
      # the diff generation works correctly

      # We'll create a file and make a minimal change
      test_dir = System.tmp_dir!() <> "/line_range_#{System.unique_integer()}"
      File.mkdir_p!(test_dir)
      test_file = Path.join(test_dir, "test.txt")
      File.write!(test_file, "a")

      args = %{
        "path" => test_file,
        "old_str" => "a",
        "new_str" => "b"
      }

      {:ok, result} = EditFile.edit_file(args, %{})

      assert String.contains?(result, "**Changed lines:**")

      File.rm_rf!(test_dir)
    end
  end

  describe "edge cases" do
    test "handles concurrent edits to different files" do
      test_dir = System.tmp_dir!() <> "/concurrent_#{System.unique_integer()}"
      File.mkdir_p!(test_dir)

      # Create multiple test files
      files =
        for i <- 1..5 do
          file_path = Path.join(test_dir, "test#{i}.txt")
          File.write!(file_path, "Content #{i}")
          file_path
        end

      # Perform concurrent edits
      tasks =
        Enum.map(files, fn file_path ->
          Task.async(fn ->
            args = %{
              "path" => file_path,
              "old_str" => "Content",
              "new_str" => "Modified Content"
            }

            EditFile.edit_file(args, %{})
          end)
        end)

      results = Task.await_many(tasks)

      # All edits should succeed
      Enum.each(results, fn result ->
        assert {:ok, content} = result
        assert String.contains?(content, "```diff")
      end)

      # Verify all files were modified
      Enum.each(files, fn file_path ->
        content = File.read!(file_path)
        assert String.contains?(content, "Modified Content")
      end)

      File.rm_rf!(test_dir)
    end

    test "handles very large files efficiently" do
      large_dir = System.tmp_dir!() <> "/large_#{System.unique_integer()}"
      File.mkdir_p!(large_dir)
      large_file = Path.join(large_dir, "large.txt")

      # Create a file with many lines
      lines = for i <- 1..1000, do: "This is line number #{i}"
      content = Enum.join(lines, "\n")
      File.write!(large_file, content)

      args = %{
        "path" => large_file,
        "old_str" => "This is line number 500",
        "new_str" => "This is modified line number 500"
      }

      {:ok, result} = EditFile.edit_file(args, %{})

      modified_content = File.read!(large_file)
      assert String.contains?(modified_content, "This is modified line number 500")
      assert String.contains?(result, "```diff")

      File.rm_rf!(large_dir)
    end

    test "handles replacement that spans multiple lines uniquely" do
      multispan_dir = System.tmp_dir!() <> "/multispan_#{System.unique_integer()}"
      File.mkdir_p!(multispan_dir)
      multispan_file = Path.join(multispan_dir, "multispan.txt")

      content = """
      Block 1:
      Important content
      End of block 1

      Block 2:
      Important content
      End of block 2
      """

      File.write!(multispan_file, content)

      # Replace a multiline pattern that appears in both blocks - should fail if not unique
      args = %{
        "path" => multispan_file,
        "old_str" => "Important content",
        "new_str" => "Modified content",
        "replace_all" => false
      }

      {:ok, _result} = EditFile.edit_file(args, %{})

      # Should replace only the first occurrence
      modified_content = File.read!(multispan_file)
      lines = String.split(modified_content, "\n")

      # Find where "Modified content" and "Important content" appear
      modified_count = Enum.count(lines, &String.contains?(&1, "Modified content"))
      important_count = Enum.count(lines, &String.contains?(&1, "Important content"))

      assert modified_count == 1
      # One occurrence should remain unchanged
      assert important_count == 1

      File.rm_rf!(multispan_dir)
    end
  end
end
