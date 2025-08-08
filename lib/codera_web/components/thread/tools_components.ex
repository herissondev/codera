defmodule CoderaWeb.Thread.ToolsComponents do
  use Phoenix.Component
  use Gettext, backend: CoderaWeb.Gettext

  @doc """
  Renders a tool call with its result, with custom rendering per tool type
  """
  attr :tool_call, :map, required: true
  attr :tool_result, :map, default: nil
  attr :is_pending, :boolean, default: false

  def tool_call(assigns) do
    ~H"""
    <details class="collapse bg-base-100 border-base-300 border mb-2">
      <summary class="collapse-title font-semibold">
        <.tool_icon name={@tool_call.name} />
        {@tool_call.name}
        <%= if @is_pending do %>
          (en cours...)
        <% end %>
      </summary>
      <div class="collapse-content text-sm">
        <.tool_content tool_call={@tool_call} tool_result={@tool_result} is_pending={@is_pending} />
      </div>
    </details>
    """
  end

  @doc """
  Renders the tool icon based on tool name
  """
  attr :name, :string, required: true

  def tool_icon(%{name: "glob"} = assigns) do
    ~H"""
    <span class="mr-2">🔍</span>
    """
  end

  def tool_icon(%{name: "Grep"} = assigns) do
    ~H"""
    <span class="mr-2">🔍</span>
    """
  end

  def tool_icon(%{name: "codebase_search_agent"} = assigns) do
    ~H"""
    <span class="mr-2">🔍</span>
    """
  end

  def tool_icon(%{name: "Read"} = assigns) do
    ~H"""
    <span class="mr-2">📖</span>
    """
  end

  def tool_icon(%{name: "read_file"} = assigns) do
    ~H"""
    <span class="mr-2">📖</span>
    """
  end

  def tool_icon(%{name: "list_directory"} = assigns) do
    ~H"""
    <span class="mr-2">📁</span>
    """
  end

  def tool_icon(%{name: "edit_file"} = assigns) do
    ~H"""
    <span class="mr-2">✏️</span>
    """
  end

  def tool_icon(%{name: "create_file"} = assigns) do
    ~H"""
    <span class="mr-2">📄</span>
    """
  end

  def tool_icon(%{name: "Bash"} = assigns) do
    ~H"""
    <span class="mr-2">⚡</span>
    """
  end

  # Fallback for unknown tools
  def tool_icon(assigns) do
    ~H"""
    <span class="mr-2">🔧</span>
    """
  end

  @doc """
  Renders tool content with custom rendering per tool type
  """
  attr :tool_call, :map, required: true
  attr :tool_result, :map, default: nil
  attr :is_pending, :boolean, default: false

  def tool_content(%{tool_call: %{name: "glob"}} = assigns) do
    ~H"""
    <.search_tool_content tool_call={@tool_call} tool_result={@tool_result} is_pending={@is_pending} />
    """
  end

  def tool_content(%{tool_call: %{name: "Grep"}} = assigns) do
    ~H"""
    <.search_tool_content tool_call={@tool_call} tool_result={@tool_result} is_pending={@is_pending} />
    """
  end

  def tool_content(%{tool_call: %{name: "codebase_search_agent"}} = assigns) do
    ~H"""
    <.search_tool_content tool_call={@tool_call} tool_result={@tool_result} is_pending={@is_pending} />
    """
  end

  # Fallback for all other tools
  def tool_content(assigns) do
    ~H"""
    <.default_tool_content tool_call={@tool_call} tool_result={@tool_result} is_pending={@is_pending} />
    """
  end

  @doc """
  Default tool content rendering
  """
  attr :tool_call, :map, required: true
  attr :tool_result, :map, default: nil
  attr :is_pending, :boolean, default: false

  def default_tool_content(assigns) do
    ~H"""
    <div class="mb-2">
      <strong>Arguments:</strong> {inspect(@tool_call.arguments)}
    </div>

    <%= if !@is_pending && @tool_result do %>
      <div>
        <strong>Résultat:</strong>
        <%= if @tool_result.content do %>
          <%= for content_part <- @tool_result.content do %>
            <pre class="whitespace-pre-wrap">{content_part.content}</pre>
          <% end %>
        <% end %>
      </div>
    <% end %>
    """
  end

  @doc """
  Search tool content rendering (for glob, Grep, codebase_search_agent)
  """
  attr :tool_call, :map, required: true
  attr :tool_result, :map, default: nil
  attr :is_pending, :boolean, default: false

  def search_tool_content(assigns) do
    ~H"""
    <div class="mb-2">
      <strong>Recherche:</strong> {get_search_query(@tool_call)}
    </div>

    <%= if !@is_pending && @tool_result do %>
      <div>
        <strong>Résultats trouvés:</strong>
        <%= if @tool_result.content do %>
          <%= for content_part <- @tool_result.content do %>
            <pre class="whitespace-pre-wrap text-green-700">{content_part.content}</pre>
          <% end %>
        <% end %>
      </div>
    <% end %>
    """
  end

  # Helper function to extract search query from tool arguments
  defp get_search_query(%{arguments: %{"pattern" => pattern}}), do: pattern
  defp get_search_query(%{arguments: %{"filePattern" => pattern}}), do: pattern
  defp get_search_query(%{arguments: %{"query" => query}}), do: query
  defp get_search_query(%{arguments: args}), do: inspect(args)

  @doc """
  Renders a button with navigation support.

  ## Examples

      <.button>Send!</.button>
      <.button phx-click="go" variant="primary">Send!</.button>
      <.button navigate={~p"/"}>Home</.button>
  """
  attr :rest, :global, include: ~w(href navigate patch method download name value disabled)
  attr :class, :string
  attr :variant, :string, values: ~w(primary)
  slot :inner_block, required: true

  def button(%{rest: rest} = assigns) do
    variants = %{"primary" => "btn-primary", nil => "btn-primary btn-soft"}

    assigns =
      assign_new(assigns, :class, fn ->
        ["btn", Map.fetch!(variants, assigns[:variant])]
      end)

    if rest[:href] || rest[:navigate] || rest[:patch] do
      ~H"""
      <.link class={@class} {@rest}>
        {render_slot(@inner_block)}
      </.link>
      """
    else
      ~H"""
      <button class={@class} {@rest}>
        {render_slot(@inner_block)}
      </button>
      """
    end
  end
end
