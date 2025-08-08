defmodule CoderaWeb.Thread.MessageComponents do
  use Phoenix.Component
  use Gettext, backend: CoderaWeb.Gettext
  import CoderaWeb.Thread.ToolsComponents

  @doc """
  Renders a message group in a thread.
  """

  attr :message_group, :map, required: true
  attr :index, :integer, required: true

  def message_group(assigns) do
    ~H"""
    <div id={"message-#{@index}"} class="">
      <%= case @message_group do %>
        <% %{type: :single, message: message} -> %>
          <.message_content message={message} />
        <% %{type: :tool_group, assistant_message: assistant_message, tool_message: tool_message, is_pending: is_pending} -> %>
          <.tool_interaction_group
            assistant_message={assistant_message}
            tool_message={tool_message}
            is_pending={is_pending}
          />
      <% end %>
    </div>
    """
  end

  @doc """
  Renders a tool interaction group (assistant message with tool calls + tool results)
  """
  attr :assistant_message, :map, required: true
  attr :tool_message, :map, default: nil
  attr :is_pending, :boolean, default: false

  def tool_interaction_group(assigns) do
    ~H"""
    <div>
      <%= if @assistant_message.content do %>
        <%= for {contentpart, _index} <- Enum.with_index(@assistant_message.content) do %>
          <div class="mb-2">
            {contentpart.content}
          </div>
        <% end %>
      <% end %>

      <%= if @assistant_message.tool_calls && length(@assistant_message.tool_calls) > 0 do %>
        <%= for tool_call <- @assistant_message.tool_calls do %>
          <% tool_result =
            if !@is_pending && @tool_message && @tool_message.tool_results do
              Enum.find(@tool_message.tool_results, &(&1.tool_call_id == tool_call.call_id))
            else
              nil
            end %>
          <.tool_call tool_call={tool_call} tool_result={tool_result} is_pending={@is_pending} />
        <% end %>
      <% end %>
    </div>
    """
  end

  attr :message, :map, required: true

  def message_content(%{message: %{role: :system}} = assigns) do
    ~H"""
    <%= for {contentpart, _index} <- Enum.with_index(@message.content) do %>
      <details class="collapse bg-base-100 border-base-300 border ">
        <summary class="collapse-title font-semibold">Message système</summary>
        <div class="collapse-content text-sm">
          {contentpart.content}
        </div>
      </details>
    <% end %>
    """
  end

  def message_content(%{message: %{role: :user}} = assigns) do
    ~H"""
    <%= for {contentpart, _index} <- Enum.with_index(@message.content) do %>
      <div class="border border-gray-300 rounded p-3 bg-gray-100">
        <div class="text-gray-800">
          {contentpart.content}
        </div>
      </div>
    <% end %>
    """
  end

  def message_content(%{message: %{role: :assistant}} = assigns) do
    ~H"""
    <div class="border border-blue-300 rounded p-3 bg-blue-50">
      <%= if @message.content do %>
        <%= for {contentpart, _index} <- Enum.with_index(@message.content) do %>
          <div class="mb-2 text-gray-800">
            {contentpart.content}
          </div>
        <% end %>
      <% end %>

      <%= if @message.tool_calls && length(@message.tool_calls) > 0 do %>
        <div class="mt-2">
          <div class="text-sm font-semibold text-blue-700 mb-1">Appels d'outils :</div>
          <%= for tool_call <- @message.tool_calls do %>
            <div class="text-xs bg-blue-100 p-1 rounded mb-1">
              <strong>{tool_call.name}</strong> - {inspect(tool_call.arguments)}
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  def message_content(%{message: %{role: :tool}} = assigns) do
    ~H"""
    <div class="border border-green-300 rounded p-2 bg-green-50">
      <%= if @message.tool_results && length(@message.tool_results) > 0 do %>
        <%= for tool_result <- @message.tool_results do %>
          <details class="collapse bg-green-100 border-green-300 border mb-2">
            <summary class="collapse-title font-semibold text-sm text-green-700">
              {tool_result.display_text || tool_result.name}
            </summary>
            <div class="collapse-content text-xs">
              <%= if tool_result.content do %>
                <%= for content_part <- tool_result.content do %>
                  <pre class="whitespace-pre-wrap">{content_part.content}</pre>
                <% end %>
              <% end %>
            </div>
          </details>
        <% end %>
      <% else %>
        <div class="text-sm text-green-700">Message d'outil (pas de résultats)</div>
      <% end %>
    </div>
    """
  end
end
