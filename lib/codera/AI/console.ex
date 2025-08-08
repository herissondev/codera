defmodule Codera.AI.Agent.Console do
  @moduledoc """
  Outils de débogage / console pour les agents :
    • `test/0`  – mini-chat interactif couleur
    • `to_mardown/1` – dump complet du `LLMChain` dans un fichier Markdown
  """

  require Logger
  alias Codera.AI.Tools.Task
  alias Codera.AI.Tools.Files
  alias Codera.AI.Tools.Bash
  alias Codera.AI.Configs.CodingAgent
  alias LangChain.{Chains.LLMChain, Message}
  alias Codera.AI.Agent

  # ─────────────────────────────────────
  # PUBLIC API
  # ─────────────────────────────────────

  @doc "Boucle interactif : tapez exit / quit pour quitter."
  def test(working_dir \\ "./") do
    wd = Path.expand(working_dir)
    File.cd!(wd)
    IO.puts("⚡ Chat interactif — « exit / quit » pour sortir.")
    IO.puts("Working directory: #{wd}")
    config = CodingAgent.config()

    agent =
      Agent.new("toto", config.chain)
      |> Agent.add_tools(Bash.bash_tool!())
      |> Agent.add_tools(Files.all_files_tools!())
      |> Agent.add_tools(Task.task_tool!())

    v = DateTime.utc_now() |> Calendar.strftime("%Y%m%d-%H%M%S")
    Process.put(:console_start_ts, v)
    loop(agent)
  end

  @doc """
  Écrit l’état complet d’un agent/chaîne dans
  ./debug/mardkwon/<name>_<id>.md et renvoie ce chemin.
  """
  @spec to_mardown(%Agent{}) :: binary()
  def to_mardown(%Agent{name: name, id: _id, chain: %LLMChain{} = ch}) do
    File.mkdir_p!("./debug/mardkwon")
    File.mkdir_p!("./debug/messages")

    # Use a stable start-timestamp per agent process to keep path constant across saves.
    ts =
      case Process.get(:console_start_ts) do
        nil ->
          v = DateTime.utc_now() |> Calendar.strftime("%Y%m%d-%H%M%S")
          Process.put(:console_start_ts, v)
          v

        v ->
          v
      end

    filename = "./debug/mardkwon/#{ts}-#{sanitize(name)}.md"

    message_export = "./debug/messages/#{ts}-#{sanitize(name)}.ex"

    File.write!(filename, chain_to_md(ch))
    IO.inspect(ch.messages, limit: :infinity, pretty: true)
    File.write!(message_export, :erlang.term_to_binary(ch.messages))

    filename
  end

  # ─────────────────────────────────────
  # REPL LOOP
  # ─────────────────────────────────────

  defp loop(agent) do
    prompt =
      IO.gets(IO.ANSI.format([:green, "[you] "]))
      |> case do
        nil -> "exit"
        p -> String.trim_trailing(p, "\n")
      end

    case prompt do
      p when p in ["exit", "quit"] ->
        IO.puts(IO.ANSI.format([:yellow, "👋  À bientôt !\n"]))
        _ = to_mardown(agent)

      _ ->
        case Agent.chat_response(agent, prompt) do
          {:ok, updated} ->
            Enum.each(updated.chain.exchanged_messages, &pretty_print/1)
            _ = to_mardown(updated)
            loop(updated)

          {:error, _ag, err} ->
            File.write!("./log.html", err.original)
            IO.inspect(err, label: "error")
            loop(agent)
        end
    end
  end

  # ─────────────────────────────────────
  # PRETTY PRINT
  # ─────────────────────────────────────

  defp pretty_print(%Message{role: :user, content: c} = m) do
    put_line(:green, "[you] #{join(c)}")
    usage(m)
  end

  defp pretty_print(%Message{role: :assistant} = m) do
    Enum.each(m.tool_calls, &print_tool_call/1)

    # Fold assistant text by default; allow quick glance of first line
    if is_nil(m.content) do
      :ok
    else
      txt = join(m.content)
      _first_line = txt |> String.split("\n") |> List.first()
      put_line(:blue, "[assistant] " <> txt)
    end

    usage(m)
  end

  defp pretty_print(%Message{role: :tool, tool_results: rs}) do
    Enum.each(rs, &print_tool_result/1)
  end

  defp print_tool_call(%Message.ToolCall{name: n, arguments: a}) do
    cmd =
      case a do
        %{"command" => c} -> c
        other -> inspect(other)
      end

    # Always show tool name; fold the rest (show truncated command)
    truncated = if String.length(cmd) > 120, do: String.slice(cmd, 0, 120) <> "…", else: cmd
    put_line(:light_black, "↪  (tool) #{n}: #{truncated}")
  end

  defp print_tool_result(%Message.ToolResult{name: n, content: c}) do
    txt = c |> join() |> String.slice(0, 200)
    put_line(:light_black, "←  (result #{n}) #{txt}…")
  end

  defp usage(%Message{metadata: %{usage: u}}) do
    put_line(:light_black, "(tokens in=#{u.input} out=#{u.output})")
  end

  defp usage(_), do: :ok

  defp join(nil), do: ""
  defp join(lst), do: Enum.map_join(lst, "", & &1.content)

  defp put_line(color, s), do: IO.puts(IO.ANSI.format([color, s, :reset]))

  # ─────────────────────────────────────
  # MARKDOWN DUMP
  # ─────────────────────────────────────

  defp chain_to_md(%LLMChain{messages: msgs} = ch) do
    header = """
    # Debug dump

    * Model: `#{ch.llm.model}`
    * Dump date: #{DateTime.utc_now() |> DateTime.to_iso8601()}

    ## Index

    #{build_index(msgs)}

    ---
    """

    body =
      msgs
      |> Enum.with_index(1)
      |> Enum.map_join("\n\n---\n\n", fn {m, idx} -> message_to_md(m, idx) end)

    header <> body <> "\n"
  end

  defp message_to_md(
         %Message{role: r, content: c, tool_calls: tc, tool_results: tr, metadata: md},
         i
       ) do
    id = "m#{i}"
    header = "## <a id=\"#{id}\"></a>#{i}. #{role_label(r)}"

    """
    #{header}

    #{content_md_collapsed(r, c, tc, tr)}

    #{usage_md(md)}
    """
  end

  defp role_label(:assistant), do: "Assistant"
  defp role_label(:user), do: "User"
  defp role_label(:system), do: "System"
  defp role_label(:tool), do: "Tool"
  defp role_label(other), do: to_string(other)

  defp build_index(msgs) do
    msgs
    |> Enum.with_index(1)
    |> Enum.map(fn {m, i} ->
      label = role_label(m.role)
      "- [#{i}. #{label}](#m#{i})"
    end)
    |> Enum.join("\n")
  end

  defp content_md_collapsed(role, c, tc, tr) do
    tc = tc || []
    tr = tr || []

    [
      maybe_text_md_collapsed(role, c),
      Enum.map_join(tc, "\n", &tool_call_md/1),
      Enum.map_join(tr, "\n", &tool_result_md/1)
    ]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  defp maybe_text_md_collapsed(_role, nil), do: ""

  defp maybe_text_md_collapsed(:system, parts),
    do: collapsible_block("System prompt", Enum.map_join(parts, "", & &1.content), "text")

  defp maybe_text_md_collapsed(role, parts) when role in [:assistant, :user] do
    # Show assistant/user content directly (not collapsed)
    Enum.map_join(parts, "", & &1.content) |> wrap("```text", "```")
  end

  defp maybe_text_md_collapsed(_role, parts),
    do: Enum.map_join(parts, "", & &1.content) |> wrap("```text", "```")

  defp collapsible_block(summary, body_text, lang) do
    code_open = "```" <> (lang || "text")
    body = wrap(code_open, body_text <> "\n````")
    "<details><summary>#{escape_summary(summary)}</summary>\n\n" <> body <> "\n\n</details>"
  end

  defp escape_summary(s) do
    s
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end

  defp tool_call_md(%Message.ToolCall{name: n, arguments: a}) do
    args = inspect(a, pretty: true, limit: :infinity)
    summary = "Tool call: #{n}"
    body = wrap("```json", "#{args}\n````")

    "<details><summary>#{summary}</summary>\n\n" <> body <> "\n\n</details>"
  end

  defp tool_result_md(%Message.ToolResult{name: n, content: c}) do
    txt = Enum.map_join(c, "", & &1.content)
    summary = "Tool result: #{n}"
    body = wrap("```text", "#{txt}\n````")

    "<details><summary>#{summary}</summary>\n\n" <> body <> "\n\n</details>"
  end

  defp usage_md(%{usage: u}),
    do: "*Tokens → prompt: #{u.input}, completion: #{u.output}*"

  defp usage_md(_), do: ""

  defp wrap(content, open, close),
    do: open <> "\n" <> content <> "\n" <> close

  defp wrap(open, txt), do: open <> "\n" <> txt

  defp sanitize(str) do
    str
    |> String.replace(~r/[^A-Za-z0-9_\-]/, "_")
    |> String.downcase()
  end
end
