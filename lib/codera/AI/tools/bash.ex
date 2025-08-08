defmodule Codera.AI.Tools.Bash do
  @moduledoc """
  Executes the given shell command in the user's default shell.

  ## Important notes

  1. Directory verification:
     - If the command will create new directories or files, first use the list_directory tool to verify the parent directory exists and is the correct location
     - For example, before running a mkdir command, first use list_directory to check if the parent directory exists

  2. Working directory:
     - If no `cwd` parameter is provided, the working directory is the first workspace root folder.
     - If you need to run the command in a specific directory, set the `cwd` parameter to an absolute path to the directory.
     - Avoid using `cd` (unless the user explicitly requests it); set the `cwd` parameter instead.

  3. Multiple independent commands:
     - Do NOT chain multiple independent commands with `;`
     - Do NOT chain multiple independent commands with `&&` when the operating system is Windows
     - Instead, make multiple separate tool calls for each command you want to run

  4. Escaping & Quoting:
     - Escape any special characters in the command if those are not to be interpreted by the shell
     - ALWAYS quote file paths with double quotes (eg. cat "path with spaces/file.txt")
     - Examples of proper quoting:
       - cat "path with spaces/file.txt" (correct)
       - cat path with spaces/file.txt (incorrect - will fail)

  5. Truncated output:
     - Only the last 50000 characters of the output will be returned to you along with how many lines got truncated, if any
     - If necessary, when the output is truncated, consider running the command again with a grep or head filter to search through the truncated lines

  6. Stateless environment:
     - Setting an environment variable or using `cd` only impacts a single command, it does not persist between commands

  7. Cross platform support:
      - When the Operating system is Windows, use `powershell` commands instead of Linux commands
      - When the Operating system is Windows, the path separator is '``' NOT '`/`'

  ## Examples

  - To run 'go test ./...': use { cmd: 'go test ./...' }
  - To run 'cargo build' in the core/src subdirectory: use { cmd: 'cargo build', cwd: '/home/user/projects/foo/core/src' }
  - To run 'ps aux | grep node', use { cmd: 'ps aux | grep node' }
  - To print a special character like $ with some command `cmd`, use { cmd: 'cmd \$' }

  ## Git

  Use this tool to interact with git. You can use it to run 'git log', 'git show', or other 'git' commands.

  When the user shares a git commit SHA, you can use 'git show' to look it up. When the user asks when a change was introduced, you can use 'git log'.

  If the user asks you to, use this tool to create git commits too. But only if the user asked.

  <git-example>
  user: commit the changes
  assistant: [uses Bash to run 'git status']
  [uses Bash to 'git add' the changes from the 'git status' output]
  [uses Bash to run 'git commit -m "commit message"']
  </git-example>

  <git-example>
  user: commit the changes
  assistant: [uses Bash to run 'git status']
  there are already files staged, do you want me to add the changes?
  user: yes
  assistant: [uses Bash to 'git add' the unstaged changes from the 'git status' output]
  [uses Bash to run 'git commit -m "commit message"']
  </git-example>

  ## Prefer specific tools

  It's VERY IMPORTANT to use specific tools when searching for files, instead of issuing terminal commands with find/grep/ripgrep. Use codebase_search or Grep instead. Use Read tool rather than cat, and edit_file rather than sed.

  IT IS ALSO IMPORTANT TO NEVER START BLOCKING COMMANDS. For example starting a server or a daemon, this will block you from using other tools.
  """

  alias LangChain.Function
  alias LangChain.FunctionParam

  @cmd_result_char_output 50_000

  # ---------------------------------------------------------------------------
  # Registration
  # ---------------------------------------------------------------------------
  def bash_tool!() do
    Function.new!(%{
      name: "bash",
      display_text: "Bash",
      description: @moduledoc,
      parameters: [
        FunctionParam.new!(%{
          name: "cmd",
          type: :string,
          description: "The shell command to execute"
        }),
        FunctionParam.new!(%{
          name: "cwd",
          type: :string,
          description: "(Optional) Absolute path to the working directory",
          optional: true
        })
      ],
      function: &run/2
    })
  end

  # ---------------------------------------------------------------------------
  # Callback
  # ---------------------------------------------------------------------------
  def run(%{"cmd" => command} = args, _context) do
    opts = [stderr_to_stdout: true]

    opts =
      case Map.get(args, "cwd") do
        nil -> opts
        cwd -> Keyword.put(opts, :cd, cwd)
      end

    case System.cmd("sh", ["-c", command], opts) do
      {result, 0} -> {:ok, format_result(command, result)}
      {result, _exit_code} -> {:error, format_result(command, result)}
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------
  defp format_result(command, result) do
    len = String.length(result)

    truncated =
      if len > @cmd_result_char_output do
        String.slice(result, len - @cmd_result_char_output, @cmd_result_char_output)
      else
        result
      end

    info =
      if len > @cmd_result_char_output do
        "(truncated to last #{@cmd_result_char_output} chars)"
      else
        "(not truncated)"
      end

    "Result of #{command}:\nOutput #{info}:\n" <> truncated
  end
end
