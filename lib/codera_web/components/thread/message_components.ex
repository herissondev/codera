defmodule CoderaWeb.Thread.MessageComponents do
  use Phoenix.Component
  use Gettext, backend: CoderaWeb.Gettext

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

  @doc """
  Renders a message in a thread.
  """
  attr :type, :atom, values: ~w(user assistant tool)a
  attr :message, :map, required: true
  attr :index, :integer, required: true

  def message(assigns) do
    ~H"""
    <div id={"message-#{assigns.index}"} class="message">
      <div class="message-content">
        <div class="message-text">{inspect(assigns.message.content)}</div>
      </div>
    </div>
    """
  end
end
