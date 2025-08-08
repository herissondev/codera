defmodule CoderaWeb.ThreadLive do
  import CoderaWeb.Thread.MessageComponents
  alias Codera.AI.AgentServer
  use CoderaWeb, :live_view

  def mount(params, _session, socket) do
    case socket.assigns.live_action do
      :index ->
        # Thread listing page
        threads = AgentServer.list_threads()
        socket = assign(socket, :threads, threads)
        {:ok, socket}
        
      :show ->
        # Individual thread page
        thread_name = params["thread_name"]
        
        # Subscribe to thread updates
        AgentServer.subscribe_to_thread(thread_name)
        
        # Get or start the thread
        case AgentServer.get_agent(thread_name) do
          {:ok, agent} ->
            {:ok, working_dir} = AgentServer.get_working_dir(thread_name)
            messages = agent.chain.messages || []
            grouped_messages = group_messages(messages)
            
            socket = socket
            |> assign(:thread_name, thread_name)
            |> assign(:working_dir, working_dir)
            |> assign(:agent, agent)
            |> assign(:messages, messages)
            |> assign(:grouped_messages, grouped_messages)
            
            {:ok, socket}
            
          {:error, :not_found} ->
            # Start new thread (defaults to current working directory)
            case AgentServer.start_thread(thread_name) do
              {:ok, ^thread_name} ->
                {:ok, agent} = AgentServer.get_agent(thread_name)
                {:ok, working_dir} = AgentServer.get_working_dir(thread_name)
                messages = agent.chain.messages || []
                grouped_messages = group_messages(messages)
                
                socket = socket
                |> assign(:thread_name, thread_name)
                |> assign(:working_dir, working_dir)
                |> assign(:agent, agent)
                |> assign(:messages, messages)
                |> assign(:grouped_messages, grouped_messages)
                
                {:ok, socket}
                
              {:error, reason} ->
                socket = socket
                |> put_flash(:error, "Failed to start thread: #{inspect(reason)}")
                |> push_navigate(to: ~p"/thread")
                
                {:ok, socket}
            end
        end
    end
  end

  def handle_info({:agent_updated, agent}, socket) do
    messages = agent.chain.messages || []
    grouped_messages = group_messages(messages)
    
    socket = socket
    |> assign(:agent, agent)
    |> assign(:messages, messages)
    |> assign(:grouped_messages, grouped_messages)
    |> push_event("scroll-to-bottom", %{})
    
    {:noreply, socket}
  end

  def handle_event("create_thread", %{"new_thread" => params}, socket) 
      when socket.assigns.live_action == :index do
    working_dir = String.trim(params["working_dir"] || "")
    thread_name = String.trim(params["thread_name"] || "")
    
    working_dir = if working_dir == "", do: nil, else: working_dir
    thread_name = if thread_name == "", do: nil, else: thread_name
    
    case AgentServer.start_thread(thread_name, working_dir) do
      {:ok, created_thread_name} ->
        socket = socket
        |> put_flash(:info, "Thread '#{created_thread_name}' created successfully")
        |> push_navigate(to: ~p"/thread/#{created_thread_name}")
        
        {:noreply, socket}
        
      {:error, reason} ->
        socket = socket
        |> put_flash(:error, "Failed to create thread: #{inspect(reason)}")
        
        {:noreply, socket}
    end
  end

  def handle_event("send_message", %{"message" => %{"content" => content}}, socket) 
      when socket.assigns.live_action == :show do
    thread_name = socket.assigns.thread_name
    
    socket = if String.trim(content) != "" do
      AgentServer.send_message(thread_name, String.trim(content))
      
      # Clear form and scroll to bottom
      socket
      |> push_event("clear-form", %{})
      |> push_event("scroll-to-bottom", %{})
    else
      socket
    end
    
    {:noreply, socket}
  end

  @doc """
  Groups messages to show tool calls and their results together
  """
  def group_messages(messages) do
    messages
    |> Enum.with_index()
    |> Enum.reduce([], fn {message, index}, acc ->
      case message.role do
        :assistant ->
          if is_list(message.tool_calls) and length(message.tool_calls) > 0 do
            # Look for the immediate next tool message
            tool_message =
              messages
              |> Enum.drop(index + 1)
              |> Enum.find(&(&1.role == :tool))

            group = %{
              type: :tool_group,
              assistant_message: message,
              tool_message: tool_message,
              is_pending: is_nil(tool_message)
            }
            [group | acc]
          else
            # Assistant message without tool calls
            group = %{type: :single, message: message}
            [group | acc]
          end
          
        :tool ->
          # Skip tool messages - they're handled in assistant tool groups
          acc
          
        _ ->
          # Regular message (system, user)
          group = %{type: :single, message: message}
          [group | acc]
      end
    end)
    |> Enum.reverse()
  end

  def render(%{live_action: :index} = assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto px-4">
      <h1 class="text-2xl font-bold mb-4">Threads</h1>
      
      <div class="mb-6">
        <.link navigate={~p"/thread/#{FriendlyID.generate(3, separator: "-", transform: &String.downcase/1)}"} 
              class="btn btn-primary mr-2">
          Quick Start (Current Dir)
        </.link>
        
        <details class="dropdown">
          <summary class="btn btn-outline">Create with Custom Directory</summary>
          <div class="dropdown-content bg-base-100 rounded-box z-[1] w-96 p-4 shadow border">
            <.form for={%{}} as={:new_thread} phx-submit="create_thread" class="space-y-3" id="thread-creation-form">
              <div>
                <label class="block text-sm font-medium mb-1">Working Directory</label>
                <div class="flex gap-2">
                  <input 
                    type="text" 
                    name="new_thread[working_dir]"
                    placeholder="/path/to/your/project" 
                    class="input input-bordered flex-1"
                    value={File.cwd!()}
                    id="working-dir-input"
                  />
                  <button 
                    type="button" 
                    class="btn btn-outline btn-sm"
                    onclick="selectDirectory()"
                    title="Browse and select a directory"
                  >
                    📁 Browse
                  </button>
                </div>
                <div class="text-xs text-gray-500 mt-1">
                  Click Browse to select a directory (Chrome/Edge), or type the full path manually
                </div>
              </div>
              <div>
                <label class="block text-sm font-medium mb-1">Thread Name (optional)</label>
                <input 
                  type="text" 
                  name="new_thread[thread_name]"
                  placeholder="my-project-thread" 
                  class="input input-bordered w-full"
                />
              </div>
              <button type="submit" class="btn btn-primary w-full">
                Create Thread
              </button>
            </.form>
          </div>
        </details>
      </div>
      
      <div class="space-y-2">
        <%= if @threads == [] do %>
          <p class="text-gray-600">No active threads</p>
        <% else %>
          <%= for thread <- @threads do %>
            <div class="border border-gray-300 rounded p-3">
              <div class="flex justify-between items-start">
                <div>
                  <.link navigate={~p"/thread/#{thread.name}"} class="text-blue-600 hover:underline font-medium">
                    {thread.name}
                  </.link>
                  <div class="text-sm text-gray-600 mt-1">
                    📁 {thread.working_dir}
                  </div>
                </div>
              </div>
            </div>
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end

  def render(%{live_action: :show} = assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto px-4 pb-8">
      <h1 class="text-2xl font-bold">Thread: {@thread_name}</h1>
      <div class="text-sm text-gray-600 mb-2">
        <.link navigate={~p"/thread"} class="text-blue-600 hover:underline">← Back to threads</.link>
      </div>
      <div class="text-sm text-gray-600 mb-4">
        📁 Working in: <code class="bg-gray-100 px-1 rounded">{@working_dir}</code>
      </div>
      
      <!-- Messages -->
      <div id="messages" class="mt-4 flex flex-col space-y-4 mb-8">
        <%= for {message_group, index} <- Enum.with_index(@grouped_messages) do %>
          <.message_group message_group={message_group} index={index} />
        <% end %>
      </div>
      
      <!-- Message Input Form -->
      <div class="sticky bottom-0 bg-white border-t border-gray-200 pt-4">
        <.form for={%{}} as={:message} phx-submit="send_message" class="flex gap-2" id="message-form">
          <input 
            type="text" 
            name="message[content]"
            placeholder="Type your message..." 
            class="flex-1 input input-bordered"
            autocomplete="off"
            id="message-input"
          />
          <button type="submit" class="btn btn-primary">
            Send
          </button>
        </.form>
      </div>
    </div>
    
    <script>
      // Auto-scroll to bottom when new messages arrive
      window.addEventListener("phx:scroll-to-bottom", () => {
        const messagesContainer = document.getElementById("messages");
        if (messagesContainer) {
          messagesContainer.scrollTop = messagesContainer.scrollHeight;
        }
      });
      
      // Clear form after message sent
      window.addEventListener("phx:clear-form", () => {
        const messageInput = document.getElementById("message-input");
        if (messageInput) {
          messageInput.value = "";
          messageInput.focus();
        }
      });
      
      // Modern directory picker using File System Access API
      async function selectDirectory() {
        const workingDirInput = document.getElementById("working-dir-input");
        
        try {
          // Check if the File System Access API is supported
          if ('showDirectoryPicker' in window) {
            // Modern browsers (Chrome 86+, Edge 86+)
            const directoryHandle = await window.showDirectoryPicker();
            
            // Get the directory name and try to construct a reasonable path
            const dirName = directoryHandle.name;
            
            // For security reasons, we can't get the full system path directly
            // But we can use the directory name to suggest a path
            const currentPath = workingDirInput.value;
            const parentDir = currentPath.substring(0, currentPath.lastIndexOf('/'));
            const suggestedPath = parentDir + '/' + dirName;
            
            workingDirInput.value = suggestedPath;
            
            // Show success feedback
            showDirectoryFeedback(dirName, "Directory selected successfully");
            
            // Visual feedback
            workingDirInput.style.backgroundColor = "#e6ffe6";
            setTimeout(() => {
              workingDirInput.style.backgroundColor = "";
            }, 1500);
            
          } else {
            // Fallback for browsers that don't support File System Access API
            alert("Directory picker not supported in this browser. Please type the path manually.\n\nSupported browsers: Chrome 86+, Edge 86+");
          }
        } catch (error) {
          if (error.name === 'AbortError') {
            // User cancelled the picker
            console.log('Directory selection cancelled');
          } else {
            console.error('Error selecting directory:', error);
            alert("Error selecting directory. Please type the path manually.");
          }
        }
      }
      
      // Function to show directory selection feedback
      function showDirectoryFeedback(dirName, message) {
        const workingDirInput = document.getElementById("working-dir-input");
        
        // Create or update feedback element
        let feedback = document.getElementById("dir-feedback");
        if (!feedback) {
          feedback = document.createElement("div");
          feedback.id = "dir-feedback";
          feedback.className = "text-xs text-green-600 mt-1";
          workingDirInput.parentNode.appendChild(feedback);
        }
        
        feedback.textContent = `✓ Selected "${dirName}" - ${message}`;
        feedback.style.display = "block";
        
        // Hide feedback after 3 seconds
        setTimeout(() => {
          if (feedback) {
            feedback.style.display = "none";
          }
        }, 3000);
      }
    </script>
    """
  end
end
