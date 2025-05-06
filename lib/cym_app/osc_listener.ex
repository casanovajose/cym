defmodule CymApp.OSCListener do
  use GenServer

  require Logger

  @port 4333 # Replace with the port you want to listen on
  @map_coor 500

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{x: nil, y: nil}, name: __MODULE__)
  end

  @impl true
  def init(state) do
    # Open a UDP socket to listen for OSC messages
    {:ok, socket} = :gen_udp.open(@port, [:binary, active: true, reuseaddr: true])
    Logger.info("Listening for OSC messages on port #{@port}")
    {:ok, Map.put(state, :socket, socket)}
  end

  @impl true
  def handle_info({:udp, _socket, _ip, _port, data}, state) do
    # Parse the incoming OSC message
    case OSC.Message.parse(data) do
      %OSC.Message{path: path, args: args} ->
        #Logger.info("Received OSC message: #{path} with arguments #{inspect(args)}")
        {:noreply, handle_osc_message(path, args, state)}
      a -> IO.inspect(a, label: "OSC message")
      # {:error, reason} ->
      #   Logger.error("Failed to parse OSC message: #{inspect(reason)}")
      #   {:noreply, state}
    end
  end

  defp handle_osc_message("/x", [x], state) do
    # Update the buffer with the new x value
    state = Map.put(state, :x, Float.round(x, 2) * @map_coor)

    # Check if both x and y are present
    maybe_broadcast_coordinates(state)
  end

  defp handle_osc_message("/y", [y], state) do
    # Update the buffer with the new y value
    state = Map.put(state, :y, Float.round(1 - y, 2) * @map_coor)

    # Check if both x and y are present
    maybe_broadcast_coordinates(state)
  end

  defp handle_osc_message(_path, _args, state) do
    # Handle other OSC messages if needed
    state
  end

  defp maybe_broadcast_coordinates(%{x: x, y: y} = state) when not is_nil(x) and not is_nil(y) do
    # Broadcast the coordinates to the LiveView process
    Phoenix.PubSub.broadcast(CymApp.PubSub, "coordinates", {x, y})
    IO.puts("Broadcasting coordinates: #{x}, #{y}")
    # Clear the buffer after broadcasting
    %{state | x: nil, y: nil}
  end

  defp maybe_broadcast_coordinates(state), do: state
end
