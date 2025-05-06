defmodule CymAppWeb.CymAppLive do
  use CymAppWeb, :live_view

  @max_cord_live 300
  @ttl 5000 # Time-to-live for coordinates in milliseconds
  @lerp_step 5
  @lerp_time 500

  @impl true
  def mount(_params, _session, socket) do
    # Subscribe to the "coordinates" topic
    if connected?(socket) do
      Phoenix.PubSub.subscribe(CymApp.PubSub, "coordinates")
    end

    # Initialize the socket with an empty list of coordinates
    {:ok, assign(socket, mode: :live, coordinates: [], page_title: "SVG Path Drawer", last_osc_time: nil)}
  end

  @impl true
  def handle_event("add_coordinate", %{"x" => x, "y" => y}, socket) do
    # Add a new coordinate to the list
    coordinates = [{String.to_integer(x), String.to_integer(y)} | socket.assigns.coordinates]
    |> Enum.take(@max_cord_live) # Limit to @max_cord_live
    schedule_ttl_removal(self(), {x, y})
    {:noreply, assign(socket, :coordinates, coordinates)}
  end

  @impl true
  def handle_info({:remove_coordinate, coord}, socket) do
    # Remove only the first occurrence of the coordinate from the list
    index = Enum.find_index(socket.assigns.coordinates, fn c -> c == coord end)

    coordinates =
      if index do
        List.delete_at(socket.assigns.coordinates, index)
      else
        socket.assigns.coordinates
      end

    {:noreply, assign(socket, :coordinates, coordinates)}
  end

  @impl true
  def handle_info({x, y}, socket) do
    # Add the received coordinates to the list
    coordinates = [{x, y} | socket.assigns.coordinates]
    coordinates = Enum.take(coordinates, @max_cord_live) # Limit to @max_cord_live
    |> interpolate_coords(socket.assigns.last_osc_time)
    schedule_ttl_removal(self(), {x, y})
    {:noreply, assign(socket, %{coordinates: coordinates, last_osc_time: System.monotonic_time(:millisecond)})}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <h1><%= @page_title %></h1>
      <form phx-submit="add_coordinate">
        <input type="number" name="x" placeholder="X Coordinate" required />
        <input type="number" name="y" placeholder="Y Coordinate" required />
        <button type="submit">Add Coordinate</button>
      </form>
      <svg width="500" height="500" style="border: 1px solid black;">
        <!-- Define an arrow marker -->
        <defs>
          <marker id="arrowhead" markerWidth="10" markerHeight="7" refX="10" refY="3.5" orient="auto">
            <polygon points="0 0, 10 3.5, 0 7" fill="blue" />
          </marker>
        </defs>

        <!-- Draw the path -->
        <%= if @coordinates != [] do %>
          <path d={svg_path(@coordinates)} fill="none" stroke="blue" stroke-width="2" stroke-dasharray="2,2" marker-end="url(#arrowhead)" />
        <% end %>

        <!-- Draw the first point as a circle -->
        <%= if length(@coordinates) > 0 do %>
          <% {x, y} = List.last(@coordinates) %>
          <circle cx={x} cy={y} r="5" fill="blue" />
        <% end %>
      </svg>
      <ul>
        <%= for {x, y} <- @coordinates do %>
          <li>(<%= x %>, <%= y %>)</li>
        <% end %>
      </ul>
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

  defp schedule_ttl_removal(pid, coord) do
    # Schedule the removal of the coordinate after @ttl milliseconds
    Process.send_after(pid, {:remove_coordinate, coord}, @ttl)
  end

  defp interpolate_coords(coords, last_osc_time) do
    current_time = System.monotonic_time(:millisecond)
    time_since_last_osc = current_time - (last_osc_time || 0)
    IO.inspect(time_since_last_osc > @lerp_time, label: "LERP")
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
