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
  def test do
    IO.puts("⚡ Chat interactif — « exit / quit » pour sortir.")
    config = CodingAgent.config()

    agent =
      Agent.new("toto", config.chain)
      |> Agent.add_tools(Bash.bash_tool!())
      |> Agent.add_tools(Files.all_files_tools!())
      |> Agent.add_tools(Task.task_tool!())

    loop(agent)
  end

  @doc """
  Écrit l’état complet d’un agent/chaîne dans
  ./debug/mardkwon/<name>_<id>.md et renvoie ce chemin.
  """
  @spec to_mardown(%Agent{}) :: binary()
  def to_mardown(%Agent{name: name, id: id, chain: %LLMChain{} = ch}) do
    File.mkdir_p!("./debug/mardkwon")

    filename =
      "./debug/mardkwon/#{sanitize(name)}_#{Base.encode16(id)}.md"

    File.write!(filename, chain_to_md(ch))
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
    unless is_nil(m.content), do: put_line(:blue, "[assistant] #{join(m.content)}")
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

    put_line(:light_black, "↪  (tool) #{n}: #{cmd}")
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
    """
    ## #{i}. #{role_label(r)}

    #{content_md(c, tc, tr)}

    #{usage_md(md)}
    """
  end

  defp role_label(:assistant), do: "Assistant"
  defp role_label(:user), do: "User"
  defp role_label(:system), do: "System"
  defp role_label(:tool), do: "Tool"
  defp role_label(other), do: to_string(other)

  defp content_md(c, tc, tr) do
    # ← nouveau
    tc = tc || []
    # ← nouveau
    tr = tr || []

    [
      maybe_text_md(c),
      Enum.map_join(tc, "\n", &tool_call_md/1),
      Enum.map_join(tr, "\n", &tool_result_md/1)
    ]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  defp maybe_text_md(nil), do: ""

  defp maybe_text_md(parts),
    do: Enum.map_join(parts, "", & &1.content) |> wrap("```text", "```")

  defp tool_call_md(%Message.ToolCall{name: n, arguments: a}) do
    args = inspect(a, pretty: true, limit: :infinity)
    wrap("```tool-call #{n}", "#{args}\n```")
  end

  defp tool_result_md(%Message.ToolResult{name: n, content: c}) do
    txt = Enum.map_join(c, "", & &1.content)
    wrap("```tool-result #{n}", "#{txt}\n```")
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
