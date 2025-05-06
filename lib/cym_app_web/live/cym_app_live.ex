defmodule CymAppWeb.CymAppLive do
  use CymAppWeb, :live_view

  @max_cord_live 50
  @ttl 2000 # Time-to-live for coordinates in milliseconds
  @lerp_step 1
  @lerp_time 1000



  # 16-color palette
  @colors [
    "#FF0000", # Red
    "#00FF00", # Green
    "#0000FF", # Blue
    "#FFFF00", # Yellow
    "#FF00FF", # Magenta
    "#00FFFF", # Cyan
    "#FF8000", # Orange
    "#8000FF", # Purple
    "#0080FF", # Light Blue
    "#FF0080", # Pink
    "#80FF00", # Lime
    "#FF8080", # Light Red
    "#8080FF", # Light Purple
    "#80FF80", # Light Green
    "#FFB366", # Light Orange
    "#B366FF"  # Lavender
  ]

  # debug
  @d_coord false

  @max_users 8
  # User structure to hold per-user properties
  defmodule User do
    defstruct coordinates: [],
              last_osc_time: nil,
              stroke_color: nil
  end


  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(CymApp.PubSub, "coordinates")
    end

    # Initialize users map with empty user structs and random colors
    users = 1..@max_users
    |> Enum.map(fn id ->
      {id, %User{
        stroke_color: Enum.random(@colors),
        coordinates: [],
        last_osc_time: nil
      }}
    end)
    |> Map.new()

    {:ok, assign(socket,
      mode: :live,
      session_id: nil,
      users: users,
      page_title: "XY PAD",
      d_coord: @d_coord
    )}
  end

  @impl true
  def handle_event("add_coordinate", %{"x" => x, "y" => y}, socket) do
    # Add a new coordinate to the list
    coordinates = [{String.to_integer(x), String.to_integer(y)} | socket.assigns.coordinates]
    |> Enum.take(@max_cord_live) # Limit to @max_cord_live
    schedule_ttl_removal(self(), {x, y})
    {:noreply, assign(socket, :coordinates, coordinates)}
  end

  # @impl true
  # def handle_info({:remove_coordinate, coord}, socket) do
  #   # Remove only the first occurrence of the coordinate from the list
  #   index = Enum.find_index(socket.assigns.coordinates, fn c -> c == coord end)

  #   coordinates =
  #     if index do
  #       List.delete_at(socket.assigns.coordinates, index)
  #     else
  #       socket.assigns.coordinates
  #     end

  #   {:noreply, assign(socket, :coordinates, coordinates)}
  # end

  # @impl true
  # def handle_info({x, y}, socket) do
  #   # Add the received coordinates to the list
  #   coordinates = [{x, y} | socket.assigns.coordinates]
  #   coordinates = Enum.take(coordinates, @max_cord_live) # Limit to @max_cord_live
  #   |> interpolate_coords(socket.assigns.last_osc_time)
  #   schedule_ttl_removal(self(), {x, y})
  #   {:noreply, assign(socket, %{coordinates: coordinates, last_osc_time: System.monotonic_time(:millisecond)})}
  # end

  @impl true
  def handle_info({{:coordinates, user_id}, {x, y}}, socket) when user_id in 1..@max_users do
    users = Map.update!(socket.assigns.users, user_id, fn user ->
      coordinates = [{x, y} | user.coordinates]
      |> Enum.take(@max_cord_live)
      |> interpolate_coords(user.last_osc_time)

      schedule_ttl_removal(self(), {user_id, {x, y}})

      %{user |
        coordinates: coordinates,
        last_osc_time: System.monotonic_time(:millisecond)
      }
    end)

    {:noreply, assign(socket, :users, users)}
  end

  @impl true
  def handle_info({:remove_coordinate, {user_id, coord}}, socket) do
    users = Map.update!(socket.assigns.users, user_id, fn user ->
      index = Enum.find_index(user.coordinates, fn c -> c == coord end)
      coordinates = if index do
        List.delete_at(user.coordinates, index)
      else
        user.coordinates
      end
      %{user | coordinates: coordinates}
    end)

    {:noreply, assign(socket, :users, users)}
  end


  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <h1><%= @page_title %></h1>
      <svg width="500" height="500" style="border: 1px solid black;">
        <defs>
          <%= for {id, user} <- @users do %>
            <marker id={"arrowhead-#{id}"} markerWidth="10" markerHeight="7" refX="10" refY="3.5" orient="auto">
              <polygon points="0 0, 10 3.5, 0 7" fill={user.stroke_color} />
            </marker>
          <% end %>
        </defs>

        <%= for {id, user} <- @users do %>
          <%= if user.coordinates != [] do %>
            <path
              d={svg_path(user.coordinates)}
              fill="none"
              stroke={user.stroke_color}
              stroke-width="2"
              stroke-dasharray="2,2"
              marker-end={"url(#arrowhead-#{id})"}
            />
            <% {x, y} = List.last(user.coordinates) %>
            <circle cx={x} cy={y} r="5" fill={user.stroke_color} />
          <% end %>
        <% end %>
      </svg>

      <%= if @d_coord do %>
        <%= for {id, user} <- @users do %>
          <div style={"color: #{user.stroke_color}; margin-top: 1em;"}>
            <strong>User <%= id %></strong>
            <ul>
              <%= for {x, y} <- user.coordinates do %>
                <li>(<%= Float.round(x, 2) %>, <%= Float.round(y, 2) %>)</li>
              <% end %>
            </ul>
          </div>
        <% end %>
      <% end %>
    </div>
    """
  end

  defp svg_path(coordinates) do
    # Ensure the list of coordinates is not empty
    if coordinates == [] do
      ""
    else
      coordinates
      |> Enum.reverse()
      |> Enum.map_join(" ", fn {x, y} -> "L #{x} #{y}" end)
      |> String.replace_prefix("L", "M")
    end
  end

  # defp schedule_ttl_removal(pid, coord) do
  #   # Schedule the removal of the coordinate after @ttl milliseconds
  #   Process.send_after(pid, {:remove_coordinate, coord}, @ttl)
  # end

  # Update the schedule_ttl_removal to include user_id
  defp schedule_ttl_removal(pid, {user_id, coord}) do
    Process.send_after(pid, {:remove_coordinate, {user_id, coord}}, @ttl)
  end

  defp interpolate_coords(coords, last_osc_time) do
    current_time = System.monotonic_time(:millisecond)
    time_since_last_osc = current_time - (last_osc_time || 0)
    # IO.inspect(time_since_last_osc > @lerp_time, label: "LERP")
    if time_since_last_osc > @lerp_time do
      IO.puts("INTERPOLATING")
      coords
      |> Enum.chunk_every(2, 1, :discard) # Create pairs of consecutive points
      |> Enum.flat_map(fn [{x1, y1}, {x2, y2}] ->
        distance = :math.sqrt(:math.pow(x2 - x1, 2) + :math.pow(y2 - y1, 2))

        if distance > @lerp_step do
          # Calculate the number of interpolation steps
          steps = Float.ceil(distance / @lerp_step) |> trunc()

          # Generate interpolated points
          for step <- 1..steps do
            t = step / steps
            {
              x1 + t * (x2 - x1),
              y1 + t * (y2 - y1)
            }
          end
        else
          # No interpolation needed, return the second point
          [{x2, y2}]
        end
      end)
    else
      coords
    end
    #|> Enum.uniq() # Ensure no duplicate points
  end
end
