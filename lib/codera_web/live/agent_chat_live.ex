defmodule CoderaWeb.AgentChatLive do
  use CoderaWeb, :live_view

  alias Codera.AI.Agent
  alias Codera.AI.Tools.Files
  alias Codera.AI.Tools.Bash
  alias Codera.AI.Configs.CodingAgent
  alias LangChain.Message
  alias Phoenix.LiveView.AsyncResult

  @max_message_len 8000

  @impl true
  def mount(_params, _session, socket) do
    config = CodingAgent.config()

    agent =
      Agent.new("chat_agent", config.chain)
      |> Agent.add_tools(Bash.bash_tool!())
      |> Agent.add_tools(Files.all_files_tools!())

    form = to_form(%{"message" => ""}, as: :chat)

    {:ok,
     socket
     |> assign(:agent, agent)
     |> assign(:messages, [])
     |> assign(:pending_user_input, nil)
     |> assign(:form, form)
     |> assign(:chat_response, AsyncResult.ok(nil))
     |> assign(:persist_history, true)
     |> assign(:error, nil)
     |> update_form_state()}
  end

  # Toggle storing history (wire up to storage if desired)
  @impl true
  def handle_event("toggle_persist", %{"persist" => persist}, socket) do
    {:noreply, assign(socket, :persist_history, persist == "true")}
  end

  # Track textarea changes to enable/disable send button properly
  @impl true
  def handle_event("change_message", %{"chat" => %{"message" => msg}}, socket) do
    {:noreply,
     socket
     |> assign(:form, to_form(%{"message" => msg}, as: :chat))
     |> update_form_state()}
  end

  @impl true
  def handle_event("send_message", %{"chat" => %{"message" => raw}}, socket) do
    message = raw |> String.slice(0, @max_message_len) |> String.trim()

    cond do
      message == "" ->
        {:noreply,
         socket |> assign(:form, to_form(%{"message" => ""}, as: :chat)) |> update_form_state()}

      socket.assigns.chat_response.loading ->
        {:noreply, socket}

      true ->
        user_msg = %{
          type: :user,
          content: message,
          timestamp: DateTime.utc_now(),
          optimistic?: true
        }

        agent = socket.assigns.agent

        {:noreply,
         socket
         |> assign(:form, to_form(%{"message" => ""}, as: :chat))
         |> update_form_state()
         |> assign(:messages, socket.assigns.messages ++ [user_msg])
         |> assign(:pending_user_input, message)
         |> clear_flash()
         |> assign(:error, nil)
         |> assign(:chat_response, AsyncResult.loading())
         |> start_async(:agent_response, fn -> Agent.chat_response(agent, message) end)}
    end
  end

  @impl true
  def handle_async(:agent_response, {:ok, {:ok, updated_agent}}, socket) do
    full_chain_msgs = updated_agent.chain.exchanged_messages
    display_messages = full_chain_msgs |> prepare_messages_for_display() |> merge_tool_results()

    {:noreply,
     socket
     |> assign(:agent, updated_agent)
     |> assign(:messages, display_messages)
     |> assign(:pending_user_input, nil)
     |> assign(:chat_response, AsyncResult.ok(nil))}
  end

  @impl true
  def handle_async(:agent_response, {:ok, {:error, _agent, error}}, socket) do
    {:noreply,
     socket
     |> assign(:error, format_error(error))
     |> assign(:chat_response, AsyncResult.failed(socket.assigns.chat_response, error))
     |> put_flash(:error, "Erreur lors de la communication avec l'agent")}
  end

  @impl true
  def handle_async(:agent_response, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:error, format_error(reason))
     |> assign(:chat_response, AsyncResult.failed(socket.assigns.chat_response, reason))
     |> put_flash(:error, "L'agent a rencontré une erreur inattendue")}
  end

  # Compute send button disabled state in assigns (fixes HEEx boolean expression issue)
  defp update_form_state(socket) do
    msg = get_in(socket.assigns.form.data, ["message"]) || ""
    trimmed = String.trim(msg)
    loading = socket.assigns.chat_response.loading

    send_disabled =
      if loading do
        true
      else
        trimmed == ""
      end

    assign(socket, :send_disabled, send_disabled)
  end

  # Prepare messages for display by grouping tool calls with their results
  defp prepare_messages_for_display(messages) do
    messages
    |> Enum.map(&format_message/1)
    |> Enum.reject(&is_nil/1)
  end

  defp format_message(%Message{role: :user, content: content}) do
    %{
      type: :user,
      content: join_content(content),
      timestamp: DateTime.utc_now()
    }
  end

  defp format_message(%Message{role: :assistant, content: content, tool_calls: tool_calls}) do
    tools_section =
      if is_list(tool_calls) and tool_calls != [] do
        Enum.map(tool_calls, fn tool_call ->
          %{
            type: :tool_call,
            name: tool_call.name,
            arguments: tool_call.arguments,
            result: nil
          }
        end)
      else
        []
      end

    content_section =
      case safe_join_content(content) do
        "" -> nil
        text -> %{type: :assistant_text, content: text}
      end

    %{
      type: :assistant,
      content: content_section,
      tools: tools_section,
      timestamp: DateTime.utc_now()
    }
  end

  defp format_message(%Message{role: :tool, tool_results: tool_results}) do
    if is_list(tool_results) and tool_results != [] do
      %{
        type: :tool_results,
        results:
          Enum.map(tool_results, fn result ->
            %{
              name: result.name,
              content: join_content(result.content)
            }
          end)
      }
    else
      nil
    end
  end

  defp format_message(_), do: nil

  defp safe_join_content(nil), do: ""
  defp safe_join_content([]), do: ""
  defp safe_join_content(content), do: join_content(content)

  defp join_content(nil), do: ""
  defp join_content([]), do: ""

  defp join_content(content) when is_list(content) do
    Enum.map_join(content, "", fn
      %{content: c} when is_binary(c) -> c
      c when is_binary(c) -> c
      other -> inspect(other)
    end)
  end

  defp join_content(content) when is_binary(content), do: content

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto h-dvh max-h-dvh w-full max-w-5xl grid grid-rows-[auto_1fr_auto]">
      <!-- Header -->
      <header class="px-4 py-3 border-b bg-base-100/80 backdrop-blur sticky top-0 z-10">
        <div class="flex items-center justify-between gap-4">
          <div class="flex items-center gap-3">
            <div class="avatar">
              <div class="w-10 rounded-full ring ring-secondary ring-offset-base-100 ring-offset-2">
                🤖
              </div>
            </div>
            <div>
              <h1 class="text-2xl font-bold">Agent Chat</h1>
              <p class="text-sm text-base-content/70">Bash, fichiers et plus</p>
            </div>
          </div>

          <div class="flex items-center gap-3">
            <label class="label cursor-pointer gap-2">
              <span class="label-text text-sm">Sauver l'historique</span>
              <input
                type="checkbox"
                checked={@persist_history}
                phx-click="toggle_persist"
                phx-value-persist={!@persist_history |> to_string()}
                class="toggle toggle-primary"
                aria-label="Sauvegarder l'historique de chat"
              />
            </label>
            <button
              class="btn btn-ghost btn-sm"
              phx-click={JS.push("send_message", value: %{"chat" => %{"message" => "/help"}})}
              title="Aide"
            >
              ❓ Aide
            </button>
          </div>
        </div>
      </header>
      
    <!-- Messages -->
      <main
        id="messages-container"
        class="overflow-y-auto px-4 py-4 space-y-4 bg-base-200"
        phx-hook="ScrollToBottom"
      >
        <div :if={Enum.empty?(@messages)} class="text-center text-base-content/60 mt-16">
          <div class="text-6xl mb-4">💬</div>
          <p class="text-lg">Commencez une conversation avec l'agent…</p>
          <p class="text-sm">Astuce: décrivez votre tâche, ou demandez une commande bash.</p>
        </div>

        <div :for={{message, idx} <- Enum.with_index(@messages)} id={"msg-#{idx}"} class="space-y-2">
          <!-- User -->
          <div :if={message.type == :user} class="chat chat-end">
            <div class="chat-image avatar placeholder">
              <div class="bg-primary text-primary-content w-10 rounded-full">Vous</div>
            </div>
            <div class={"chat-bubble chat-bubble-primary shadow #{if message[:optimistic?], do: "opacity-90"}"}>
              <.render_text text={message.content} />
            </div>
            <div class="chat-footer opacity-60 text-xs">{format_time(message.timestamp)}</div>
          </div>
          
    <!-- Assistant -->
          <div :if={message.type == :assistant} class="chat chat-start">
            <div class="chat-image avatar">
              <div class="w-10 rounded-full ring ring-secondary ring-offset-base-100 ring-offset-2">
                🤖
              </div>
            </div>

            <div :if={message.content} class="chat-bubble chat-bubble-secondary shadow mb-2">
              <.render_text text={message.content.content} />
            </div>

            <div :if={message.tools && length(message.tools) > 0} class="space-y-2">
              <div
                :for={tool <- message.tools}
                class="card bg-base-100 shadow-sm border border-base-200"
              >
                <div class="card-body p-3">
                  <div class="flex items-center justify-between mb-2">
                    <div class="flex items-center gap-2">
                      <span class="badge badge-accent badge-sm">🛠️ {tool.name}</span>
                      <span :if={!tool.result} class="text-xs opacity-70">en cours…</span>
                    </div>
                    <button
                      :if={tool.result}
                      class="btn btn-ghost btn-xs"
                      phx-click={
                        JS.dispatch("codera:copy",
                          detail: %{selector: "#tool-result-#{idx}-#{tool.name}"}
                        )
                      }
                    >
                      Copier
                    </button>
                  </div>

                  <details class="collapse collapse-arrow bg-base-200">
                    <summary class="collapse-title text-sm font-medium">Arguments</summary>
                    <div class="collapse-content">
                      <pre class="text-xs overflow-x-auto bg-base-100 p-2 rounded">{format_tool_args(tool.arguments)}</pre>
                    </div>
                  </details>

                  <div :if={tool.result} class="bg-base-200/60 rounded p-3 mt-2">
                    <div class="text-sm font-medium mb-2 text-success">Résultat:</div>
                    <div class="max-h-64 overflow-y-auto">
                      <pre id={"tool-result-#{idx}-#{tool.name}"} class="text-xs whitespace-pre-wrap"><%= tool.result %></pre>
                    </div>
                  </div>

                  <div :if={!tool.result} class="text-xs opacity-60 italic mt-1">
                    En attente du résultat de l'outil…
                  </div>
                </div>
              </div>
            </div>

            <div class="chat-footer opacity-60 text-xs">{format_time(message.timestamp)}</div>
          </div>
        </div>
        
    <!-- Typing indicator -->
        <div :if={@chat_response.loading} class="chat chat-start">
          <div class="chat-bubble bg-base-100">
            <span class="loading loading-dots loading-sm"></span> L'agent réfléchit…
          </div>
        </div>
        
    <!-- Error -->
        <div :if={@error} role="alert" class="alert alert-error mt-2">
          <span>Erreur: {@error}</span>
        </div>
      </main>
      
    <!-- Input -->
      <footer class="px-4 py-3 border-t bg-base-100 sticky bottom-0">
        <.form
          for={@form}
          id="chat-form"
          phx-submit="send_message"
          phx-change="change_message"
          class="flex items-end gap-3"
        >
          <div class="flex-1">
            <div class="relative">
              <textarea
                name="chat[message]"
                value={@form.data["message"]}
                placeholder="Tapez votre message… (Entrée pour envoyer, Maj+Entrée pour nouvelle ligne)"
                class="textarea textarea-bordered w-full min-h-12 pr-12"
                disabled={@chat_response.loading}
                autocomplete="off"
                phx-hook="TextAreaSubmit"
                id="message-input"
              />
              <div class="absolute right-2 bottom-2 text-xs opacity-50 select-none">
                {String.length(@form.data["message"] || "")}/{100}
              </div>
            </div>
          </div>

          <button
            type="submit"
            class={"btn btn-primary #{if @chat_response.loading, do: "btn-disabled"}"}
            disabled={@chat_response.loading}
            aria-label="Envoyer"
            phx-hook="RefocusOnSend"
            id="send-button"
          >
            <span :if={!@chat_response.loading}>Envoyer</span>
            <span :if={@chat_response.loading} class="loading loading-spinner loading-sm"></span>
          </button>
        </.form>
      </footer>
    </div>

    <script>
      // Auto-scroll
      window.ScrollToBottom = {
        mounted() { this.scroll() },
        updated() { this.scroll() },
        scroll() { this.el.scrollTop = this.el.scrollHeight }
      };

      // Submit on Enter, newline on Shift+Enter
      window.TextAreaSubmit = {
        mounted() {
          const ta = this.el;
          ta.addEventListener("keydown", (e) => {
            if (e.key === "Enter" && !e.shiftKey) {
              e.preventDefault();
              const form = document.getElementById("chat-form");
              if (form) form.requestSubmit();
            }
          });
        }
      };

      // Refocus textarea after sending
      window.RefocusOnSend = {
        updated() {
          const ta = document.querySelector('#chat-form textarea[name="chat[message]"]');
          if (ta && !ta.disabled) ta.focus();
        }
      };

      // Copy helper event
      window.addEventListener("codera:copy", (e) => {
        try {
          const sel = e.detail?.selector;
          const node = sel ? document.querySelector(sel) : null;
          if (!node) return;
          const text = node.innerText || node.textContent || "";
          navigator.clipboard.writeText(text);
        } catch (_) {}
      });
    </script>
    """
  end

  # Merge tool results with their corresponding tool calls
  defp merge_tool_results(messages) do
    messages
    |> Enum.reduce([], fn message, acc ->
      case message.type do
        :tool_results ->
          case List.last(acc) do
            %{type: :assistant, tools: tools} = last_msg when is_list(tools) ->
              updated_tools =
                Enum.map(tools, fn tool ->
                  with %{content: content} <- Enum.find(message.results, &(&1.name == tool.name)) do
                    %{tool | result: join_tool_results(tool.result, content)}
                  else
                    _ -> tool
                  end
                end)

              List.replace_at(acc, -1, %{last_msg | tools: updated_tools})

            _ ->
              acc
          end

        _ ->
          acc ++ [message]
      end
    end)
  end

  defp join_tool_results(nil, content), do: content

  defp join_tool_results(existing, content) when is_binary(existing),
    do: existing <> "\n" <> content

  defp join_tool_results(existing, content), do: "#{existing}\n#{content}"

  defp format_tool_args(args) do
    case Jason.encode(args, pretty: true) do
      {:ok, json} -> json
      _ -> inspect(args, pretty: true, limit: :infinity)
    end
  end

  defp format_time(datetime) do
    datetime
    |> DateTime.to_time()
    |> Time.truncate(:second)
    |> Time.to_string()
  end

  defp format_error(%{message: msg}), do: msg
  defp format_error(msg) when is_binary(msg), do: msg
  defp format_error(other), do: inspect(other)

  # Text rendering: simple markdown-style code fence support
  attr :text, :string, required: true

  defp render_text(assigns) do
    ~H"""
    <%= for block <- split_blocks(@text) do %>
      <%= if block.type == :code do %>
        <div class="mockup-code my-1">
          <pre class="overflow-x-auto"><code><%= block.content %></code></pre>
        </div>
      <% else %>
        <p class="whitespace-pre-wrap break-words">{block.content}</p>
      <% end %>
    <% end %>
    """
  end

  defp split_blocks(text) when is_binary(text) do
    parts = String.split(text, ~r/```/, trim: false)

    parts
    |> Enum.with_index()
    |> Enum.map(fn {segment, idx} ->
      type = if rem(idx, 2) == 1, do: :code, else: :text
      %{type: type, content: String.trim_trailing(segment)}
    end)
    |> Enum.reject(&(&1.content == ""))
  end

  defp split_blocks(_), do: []
end
