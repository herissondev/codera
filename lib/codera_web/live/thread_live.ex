defmodule CoderaWeb.ThreadLive do
  alias Codera.AI.Agent
  use CoderaWeb, :live_view

  def mount(_params, _session, socket) do
    # start agent
    random_3_name_slug = "red-sweaty-potato"

    FriendlyID.generate(3, separator: "-", transform: &String.downcase/1)

    %{chain: chain} = Codera.AI.Configs.CodingAgent.config()
    agent = Agent.new(random_3_name_slug, chain)

    {:ok, assign(socket, :agent, agent)}
  end

  def render(assigns) do
    ~H"""
    <div>
      <h1>Thread Live</h1>
      name: {@agent.name}
      <div id="messages">
        <%= for {message, index} <- Enum.with_index(@agent.chain.messages) do %>
          <div id={"message-#{index}"} class="message">
            <div class="message-content">
              <div class="message-text">{inspect(message.content)}</div>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
