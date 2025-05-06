defmodule CymApp.OSCListener do
  use GenServer

  require Logger

  @port 4333 # Replace with the port you want to listen on
  @map_coor 500
  @max_users 8

  def start_link(_) do
    # Initialize state with a map to track multiple users
    initial_state = %{
      socket: nil,
      users: Map.new(1..@max_users, fn id ->
        {id, %{x: nil, y: nil}}
      end)
    }
    GenServer.start_link(__MODULE__, initial_state, name: __MODULE__)
  end

  @impl true
  def init(state) do
    # Open a UDP socket to listen for OSC messages
    {:ok, socket} = :gen_udp.open(@port, [:binary, active: true, reuseaddr: true])
    Logger.info("Listening for OSC messages on port #{@port}")
    {:ok, Map.put(state, :socket, socket)}
  end

  @impl true
  def handle_info({:udp, _socket, ip, port, data}, state) do
    # Extract user_id from IP/port combination or use a default
    user_id = get_user_id(ip, port)

    case OSC.Message.parse(data) do
      %OSC.Message{path: path, args: args} ->
        Logger.debug("User #{user_id}: Received OSC message: #{path} with arguments #{inspect(args)}")
        {:noreply, handle_osc_message(path, args, user_id, state)}
      {:error, reason} ->
        Logger.error("Failed to parse OSC message: #{inspect(reason)}")
        {:noreply, state}
    end
  end

   # Handle x coordinate for specific user
   defp handle_osc_message("/x", [x], user_id, state) do
    user_data = get_in(state, [:users, user_id]) || %{x: nil, y: nil}
    updated_user = %{user_data | x: Float.round(x, 2) * @map_coor}

    state = put_in(state, [:users, user_id], updated_user)
    maybe_broadcast_coordinates(user_id, state)
  end

  # Handle y coordinate for specific user
  defp handle_osc_message("/y", [y], user_id, state) do
    user_data = get_in(state, [:users, user_id]) || %{x: nil, y: nil}
    updated_user = %{user_data | y: Float.round(1 - y, 2) * @map_coor}

    state = put_in(state, [:users, user_id], updated_user)
    maybe_broadcast_coordinates(user_id, state)
  end

  defp handle_osc_message(_path, _args, _user_id, state) do
    state
  end

  defp maybe_broadcast_coordinates(user_id, state) do
    case get_in(state, [:users, user_id]) do
      %{x: x, y: y} when not is_nil(x) and not is_nil(y) ->
        # Broadcast coordinates with user_id
        Phoenix.PubSub.broadcast(
          CymApp.PubSub,
          "coordinates",
          {{:coordinates, user_id}, {x, y}}
        )
        Logger.debug("Broadcasting coordinates for user #{user_id}: #{x}, #{y}")

        # Clear the coordinates for this user
        put_in(state, [:users, user_id], %{x: nil, y: nil})

      _incomplete ->
        state
    end
  end

  # Helper function to determine user_id from IP/port
  defp get_user_id(ip, port) do
    # Create a deterministic user_id from IP and port
    # This ensures the same client gets the same user_id
    hash = :erlang.phash2({ip, port}, @max_users)
    rem(hash, @max_users) + 1
  end
end
