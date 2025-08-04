defmodule CoderaWeb.AgentChatLive do
  use CoderaWeb, :live_view

  alias Codera.AI.Agent
  alias Codera.AI.Tools.Files
  alias Codera.AI.Tools.Bash
  alias Codera.AI.Configs.CodingAgent
  alias LangChain.Message
  alias Phoenix.LiveView.AsyncResult

  def mount(_params, _session, socket) do
    config = CodingAgent.config()

    agent =
      Agent.new("chat_agent", config.chain)
      |> Agent.add_tools(Bash.bash_tool!())
      |> Agent.add_tools(Files.all_files_tools!())

    {:ok,
     socket
     |> assign(:agent, agent)
     |> assign(:messages, [])
     |> assign(:form, to_form(%{"message" => ""}, as: :chat))
     |> assign(:chat_response, AsyncResult.ok(nil))}
  end

  def handle_event("send_message", %{"chat" => %{"message" => message}}, socket) do
    if String.trim(message) == "" do
      {:noreply, socket}
    else
      agent = socket.assigns.agent

      {:noreply,
       socket
       |> assign(:form, to_form(%{"message" => ""}, as: :chat))
       |> assign(:chat_response, AsyncResult.loading())
       |> start_async(:agent_response, fn -> Agent.chat_response(agent, message) end)}
    end
  end

  def handle_async(:agent_response, {:ok, {:ok, updated_agent}}, socket) do
    messages = updated_agent.chain.exchanged_messages
    display_messages = prepare_messages_for_display(messages)

    {:noreply,
     socket
     |> assign(:agent, updated_agent)
     |> assign(:messages, display_messages)
     |> assign(:chat_response, AsyncResult.ok(nil))}
  end

  def handle_async(:agent_response, {:ok, {:error, _agent, error}}, socket) do
    {:noreply,
     socket
     |> assign(:chat_response, AsyncResult.failed(socket.assigns.chat_response, error))
     |> put_flash(:error, "Erreur lors de la communication avec l'agent")}
  end

  def handle_async(:agent_response, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:chat_response, AsyncResult.failed(socket.assigns.chat_response, reason))
     |> put_flash(:error, "L'agent a rencontré une erreur inattendue")}
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
    tools_section = if tool_calls && length(tool_calls) > 0 do
      tool_calls
      |> Enum.map(fn tool_call ->
        %{
          type: :tool_call,
          name: tool_call.name,
          arguments: tool_call.arguments,
          result: nil  # Will be filled by tool results
        }
      end)
    else
      []
    end

    content_section = if content && join_content(content) != "" do
      %{
        type: :assistant_text,
        content: join_content(content)
      }
    else
      nil
    end

    %{
      type: :assistant,
      content: content_section,
      tools: tools_section,
      timestamp: DateTime.utc_now()
    }
  end

  defp format_message(%Message{role: :tool, tool_results: tool_results}) do
    # Tool results will be merged with the previous assistant message's tool calls
    if tool_results && length(tool_results) > 0 do
      %{
        type: :tool_results,
        results: Enum.map(tool_results, fn result ->
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

  defp join_content(nil), do: ""
  defp join_content([]), do: ""
  defp join_content(content) when is_list(content) do
    Enum.map_join(content, "", fn
      %{content: c} when is_binary(c) -> c
      c when is_binary(c) -> c
      _ -> ""
    end)
  end
  defp join_content(content) when is_binary(content), do: content

  def render(assigns) do
    ~H"""
    <div class="container mx-auto max-w-4xl p-4 h-screen flex flex-col">
      <div class="mb-4">
        <h1 class="text-3xl font-bold">🤖 Agent Chat</h1>
        <p class="text-base-content/70">Chattez avec l'agent IA - Il peut utiliser des outils comme bash et la gestion de fichiers</p>
      </div>

      <!-- Messages Container -->
      <div class="flex-1 overflow-y-auto mb-4 space-y-4" id="messages-container" phx-hook="ScrollToBottom">
        <div :if={length(@messages) == 0} class="text-center text-base-content/50 mt-8">
          <div class="text-6xl mb-4">💬</div>
          <p>Commencez une conversation avec l'agent...</p>
        </div>

        <div :for={message <- merge_tool_results(@messages)} class="space-y-2">
          <!-- User Message -->
          <div :if={message.type == :user} class="chat chat-end">
            <div class="chat-bubble chat-bubble-primary">
              <pre class="whitespace-pre-wrap font-sans">{message.content}</pre>
            </div>
            <div class="chat-footer opacity-50 text-xs">
              {format_time(message.timestamp)}
            </div>
          </div>

          <!-- Assistant Message -->
          <div :if={message.type == :assistant} class="chat chat-start">
            <!-- Assistant Text Content -->
            <div :if={message.content} class="chat-bubble chat-bubble-secondary mb-2">
              <pre class="whitespace-pre-wrap font-sans">{message.content.content}</pre>
            </div>

            <!-- Tool Calls and Results -->
            <div :if={message.tools && length(message.tools) > 0} class="space-y-2">
              <div :for={tool <- message.tools} class="card bg-base-200 shadow-sm">
                <div class="card-body p-3">
                  <div class="flex items-center gap-2 mb-2">
                    <span class="badge badge-accent badge-sm">🛠️ {tool.name}</span>
                  </div>
                  
                  <!-- Tool Arguments -->
                  <div class="mb-3">
                    <details class="collapse collapse-arrow bg-base-300">
                      <summary class="collapse-title text-sm font-medium">Arguments</summary>
                      <div class="collapse-content">
                        <pre class="text-xs overflow-x-auto bg-base-100 p-2 rounded">{format_tool_args(tool.arguments)}</pre>
                      </div>
                    </details>
                  </div>

                  <!-- Tool Result -->
                  <div :if={tool.result} class="bg-base-100 rounded p-3">
                    <div class="text-sm font-medium mb-2 text-success">Résultat:</div>
                    <div class="max-h-64 overflow-y-auto">
                      <pre class="text-xs whitespace-pre-wrap">{tool.result}</pre>
                    </div>
                  </div>
                </div>
              </div>
            </div>

            <div class="chat-footer opacity-50 text-xs">
              {format_time(message.timestamp)}
            </div>
          </div>
        </div>

        <!-- Loading indicator -->
        <div :if={@chat_response.loading} class="chat chat-start">
          <div class="chat-bubble">
            <span class="loading loading-dots loading-sm"></span>
            L'agent réfléchit...
          </div>
        </div>
      </div>

      <!-- Input Form -->
      <div class="bg-base-200 rounded-lg p-4">
        <.form for={@form} phx-submit="send_message" class="flex gap-2">
          <input
            type="text"
            name="chat[message]"
            value={@form.data["message"]}
            placeholder="Tapez votre message..."
            class="input input-bordered flex-1"
            disabled={@chat_response.loading}
            autocomplete="off"
          />
          <button 
            type="submit" 
            class="btn btn-primary" 
            disabled={@chat_response.loading}
          >
            <span :if={!@chat_response.loading}>Envoyer</span>
            <span :if={@chat_response.loading} class="loading loading-spinner loading-sm"></span>
          </button>
        </.form>
      </div>
    </div>

    <script>
      // Auto-scroll to bottom when new messages arrive
      window.addEventListener("phx:update", () => {
        const container = document.getElementById("messages-container");
        if (container) {
          container.scrollTop = container.scrollHeight;
        }
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
          # Merge with the last assistant message
          case List.last(acc) do
            %{type: :assistant, tools: tools} = last_msg when is_list(tools) ->
              updated_tools = 
                tools
                |> Enum.map(fn tool ->
                  result = Enum.find(message.results, &(&1.name == tool.name))
                  if result do
                    %{tool | result: result.content}
                  else
                    tool
                  end
                end)
              
              updated_msg = %{last_msg | tools: updated_tools}
              List.replace_at(acc, -1, updated_msg)
            
            _ ->
              acc
          end
        
        _ ->
          acc ++ [message]
      end
    end)
  end

  defp format_tool_args(args) do
    case Jason.encode(args, pretty: true) do
      {:ok, json} -> json
      _ -> inspect(args, pretty: true)
    end
  end

  defp format_time(datetime) do
    datetime
    |> DateTime.to_time()
    |> Time.to_string()
    |> String.slice(0, 8)
  end
end