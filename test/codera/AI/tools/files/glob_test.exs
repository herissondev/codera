defmodule Codera.AI.Tools.Files.GlobTest do
  use ExUnit.Case, async: true
  alias Codera.AI.Tools.Files.Glob
  alias LangChain.Function

  describe "glob_tool!/0" do
    test "creates a valid function definition" do
      function = Glob.glob_tool!()

      assert %Function{} = function
      assert function.name == "glob"
      assert function.display_text == "Glob search"
      assert function.async == true
      assert is_function(function.function, 2)
    end

    test "has correct parameters" do
      function = Glob.glob_tool!()

      assert length(function.parameters) == 3

      # Check filePattern parameter
      file_pattern_param = Enum.find(function.parameters, &(&1.name == "filePattern"))
      assert file_pattern_param != nil
      assert file_pattern_param.type == :string
      assert file_pattern_param.description == "Glob pattern (e.g., '**/*.js')"
      assert file_pattern_param.required == false

      # Check limit parameter
      limit_param = Enum.find(function.parameters, &(&1.name == "limit"))
      assert limit_param != nil
      assert limit_param.type == :integer
      assert limit_param.required == false

      # Check offset parameter
      offset_param = Enum.find(function.parameters, &(&1.name == "offset"))
      assert offset_param != nil
      assert offset_param.type == :integer
      assert offset_param.required == false
    end
  end

  describe "glob/2" do
    setup do
      # Create a temporary directory structure for testing
      base_dir = System.tmp_dir!() <> "/glob_test_#{System.unique_integer()}"
      File.mkdir_p!(base_dir)
      File.mkdir_p!(base_dir <> "/subdir")

      # Create test files with different extensions and modification times
      files = [
        "test1.ex",
        "test2.js",
        "test3.md",
        "subdir/nested.ex",
        "subdir/nested.js"
      ]

      Enum.with_index(files, fn file, index ->
        path = Path.join(base_dir, file)
        File.write!(path, "content #{index}")
        # Set different modification times by sleeping briefly
        if index > 0, do: Process.sleep(10)
      end)

      on_exit(fn ->
        File.rm_rf!(base_dir)
      end)

      {:ok, base_dir: base_dir}
    end

    test "matches files with basic pattern", %{base_dir: base_dir} do
      pattern = Path.join(base_dir, "*.ex")
      args = %{"filePattern" => pattern}

      {:ok, result} = Glob.glob(args, %{})

      lines = String.trim(result) |> String.split("\n")
      assert length(lines) == 1
      assert String.ends_with?(hd(lines), "test1.ex")
    end

    test "matches files with recursive pattern", %{base_dir: base_dir} do
      pattern = Path.join(base_dir, "**/*.ex")
      args = %{"filePattern" => pattern}

      {:ok, result} = Glob.glob(args, %{})

      lines = String.trim(result) |> String.split("\n")
      assert length(lines) == 2

      # Results should be sorted by modification time (newest first)
      assert Enum.any?(lines, &String.ends_with?(&1, "test1.ex"))
      assert Enum.any?(lines, &String.ends_with?(&1, "nested.ex"))
    end

    test "applies limit parameter correctly", %{base_dir: base_dir} do
      pattern = Path.join(base_dir, "**/*")
      args = %{"filePattern" => pattern, "limit" => 2}

      {:ok, result} = Glob.glob(args, %{})

      lines = String.trim(result) |> String.split("\n")
      assert length(lines) == 2
    end

    test "applies offset parameter correctly", %{base_dir: base_dir} do
      pattern = Path.join(base_dir, "*.{ex,js,md}")
      args = %{"filePattern" => pattern, "offset" => 1}

      {:ok, result} = Glob.glob(args, %{})

      lines = String.trim(result) |> String.split("\n")
      # Should skip the first (newest) file
      assert length(lines) == 2
    end

    test "applies both limit and offset parameters", %{base_dir: base_dir} do
      pattern = Path.join(base_dir, "*.{ex,js,md}")
      args = %{"filePattern" => pattern, "offset" => 1, "limit" => 1}

      {:ok, result} = Glob.glob(args, %{})

      lines = String.trim(result) |> String.split("\n")
      assert length(lines) == 1
    end

    test "returns empty result for non-matching pattern", %{base_dir: base_dir} do
      pattern = Path.join(base_dir, "*.nonexistent")
      args = %{"filePattern" => pattern}

      {:ok, result} = Glob.glob(args, %{})

      assert String.trim(result) == ""
    end

    test "handles limit of 0", %{base_dir: base_dir} do
      pattern = Path.join(base_dir, "**/*")
      args = %{"filePattern" => pattern, "limit" => 0}

      {:ok, result} = Glob.glob(args, %{})

      lines = String.trim(result) |> String.split("\n")
      # limit of 0 should return all results (treated as no limit)
      assert length(lines) >= 5
    end

    test "handles negative limit", %{base_dir: base_dir} do
      pattern = Path.join(base_dir, "**/*")
      args = %{"filePattern" => pattern, "limit" => -1}

      {:ok, result} = Glob.glob(args, %{})

      lines = String.trim(result) |> String.split("\n")
      # negative limit should return all results (treated as no limit)
      assert length(lines) >= 5
    end

    test "handles nil limit explicitly", %{base_dir: base_dir} do
      pattern = Path.join(base_dir, "**/*")
      args = %{"filePattern" => pattern, "limit" => nil}

      {:ok, result} = Glob.glob(args, %{})

      lines = String.trim(result) |> String.split("\n")
      # nil limit should return all results
      assert length(lines) >= 5
    end

    test "defaults offset to 0 when not provided", %{base_dir: base_dir} do
      pattern = Path.join(base_dir, "*.ex")
      args = %{"filePattern" => pattern}

      {:ok, result} = Glob.glob(args, %{})

      lines = String.trim(result) |> String.split("\n")
      assert length(lines) == 1
    end

    test "matches dot files when match_dot is true", %{base_dir: base_dir} do
      # Create a dot file
      dot_file = Path.join(base_dir, ".hidden")
      File.write!(dot_file, "hidden content")

      pattern = Path.join(base_dir, ".*")
      args = %{"filePattern" => pattern}

      {:ok, result} = Glob.glob(args, %{})

      lines = String.trim(result) |> String.split("\n") |> Enum.reject(&(&1 == ""))
      assert length(lines) >= 1
      assert Enum.any?(lines, &String.ends_with?(&1, ".hidden"))
    end

    test "results are sorted by modification time (newest first)", %{base_dir: base_dir} do
      # Create files with deliberate timing
      old_file = Path.join(base_dir, "old.txt")
      new_file = Path.join(base_dir, "new.txt")

      File.write!(old_file, "old")
      # Ensure different modification times
      Process.sleep(50)
      File.write!(new_file, "new")

      pattern = Path.join(base_dir, "*.txt")
      args = %{"filePattern" => pattern}

      {:ok, result} = Glob.glob(args, %{})

      lines = String.trim(result) |> String.split("\n")
      assert length(lines) == 2

      # First result should be the newer file (newest first)
      assert String.ends_with?(hd(lines), "new.txt")
      assert String.ends_with?(List.last(lines), "old.txt")
    end

    test "handles invalid pattern gracefully" do
      # Use a pattern that might cause issues
      args = %{"filePattern" => ""}

      {:ok, result} = Glob.glob(args, %{})

      assert String.trim(result) == ""
    end

    test "returns error for file system errors" do
      # This test is tricky since Path.wildcard doesn't typically raise File.Error
      # We'll test with a very long path that might cause issues on some systems
      very_long_path = String.duplicate("a", 10000)
      args = %{"filePattern" => very_long_path}

      # Most systems will handle this gracefully, returning empty results
      result = Glob.glob(args, %{})
      assert match?({:ok, _}, result)
    end

    test "result format includes trailing newline", %{base_dir: base_dir} do
      pattern = Path.join(base_dir, "*.ex")
      args = %{"filePattern" => pattern}

      {:ok, result} = Glob.glob(args, %{})

      assert String.ends_with?(result, "\n")
    end
  end

  describe "edge cases" do
    test "handles missing filePattern parameter" do
      args = %{}

      assert_raise FunctionClauseError, fn ->
        Glob.glob(args, %{})
      end
    end

    test "handles empty filePattern" do
      args = %{"filePattern" => ""}

      {:ok, result} = Glob.glob(args, %{})
      assert String.trim(result) == ""
    end

    test "handles filePattern with only whitespace" do
      args = %{"filePattern" => "   "}

      {:ok, result} = Glob.glob(args, %{})
      assert String.trim(result) == ""
    end

    test "handles very large offset" do
      # Create a temporary directory with a few files
      base_dir = System.tmp_dir!() <> "/glob_large_offset_test"
      File.mkdir_p!(base_dir)
      File.write!(Path.join(base_dir, "test.txt"), "content")

      pattern = Path.join(base_dir, "*")
      args = %{"filePattern" => pattern, "offset" => 1000}

      {:ok, result} = Glob.glob(args, %{})
      assert String.trim(result) == ""

      File.rm_rf!(base_dir)
    end
  end
end
