# Advanced Usage

This guide covers advanced WebSocket patterns and best practices.

## Connection Pooling

For applications that need to handle many concurrent connections, you can implement connection pooling:

```elixir
defmodule WebSocket.Pool do
  use DynamicSupervisor

  def start_link(_opts), do: DynamicSupervisor.start_link(__MODULE__, [], name: __MODULE__)

  def init(_), do: DynamicSupervisor.init(strategy: :one_for_one)

  def start_child(handler_module, socket, opts) do
    child_spec = {WebSocket.Connection, {socket, handler_module, nil, nil, nil, nil}}
    DynamicSupervisor.start_child(__MODULE__, child_spec)
  end
end
```

## Broadcasting to Multiple Connections

Implement efficient message broadcasting:

```elixir
defmodule Broadcaster do
  use GenServer

  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  def subscribe(topic, socket) do
    GenServer.cast(__MODULE__, {:subscribe, topic, socket})
  end

  def unsubscribe(topic, socket) do
    GenServer.cast(__MODULE__, {:unsubscribe, topic, socket})
  end

  def broadcast(topic, message) do
    GenServer.cast(__MODULE__, {:broadcast, topic, message})
  end

  def init(_), do: {:ok, %{}}

  def handle_cast({:subscribe, topic, socket}, topics) do
    {:noreply, Map.update(topics, topic, [socket], fn sockets -> [socket | sockets] end)}
  end

  def handle_cast({:unsubscribe, topic, socket}, topics) do
    {:noreply, Map.update!(topics, topic, &List.delete(&1, socket))}
  end

  def handle_cast({:broadcast, topic, message}, topics) do
    case Map.get(topics, topic) do
      nil -> :ok
      sockets -> Enum.each(sockets, &WebSocket.Connection.send_text(&1, message))
    end

    {:noreply, topics}
  end
end
```

## Rate Limiting

Protect your server from abuse with rate limiting:

```elixir
defmodule RateLimiter do
  use GenServer

  def check_rate(socket, action, limit, window_ms) do
    GenServer.call(__MODULE__, {:check_rate, socket, action, limit, window_ms})
  end

  def init(_), do: {:ok, %{}}

  def handle_call({:check_rate, socket, action, limit, window_ms}, _from, state) do
    key = {socket, action}
    now = System.monotonic_time(:millisecond)
    window_start = now - window_ms

    requests =
      state
      |> Map.get(key, [])
      |> Enum.filter(&(&1 > window_start))

    {allowed, new_requests} =
      if length(requests) < limit do
        {true, [now | requests]}
      else
        {false, requests}
      end

    {:reply, allowed, Map.put(state, key, new_requests)}
  end
end
```

## Authentication

Implement authentication in your handler:

```elixir
defmodule AuthenticatedHandler do
  use WebSocket.Handler

  @impl true
  def init(socket, _opts) do
    # Check for authentication token in query params
    case Map.get(socket.query_params, "token") do
      [token] ->
        if verify_token(token) do
          {:ok, %{user_id: extract_user_id(token)}}
        else
          WebSocket.Connection.close(socket, {4008, "Invalid token"})
          {:stop, :authentication_failed}
        end

      _ ->
        WebSocket.Connection.close(socket, {4008, "Missing token"})
        {:stop, :authentication_failed}
    end
  end

  defp verify_token(token), do: true
  defp extract_user_id(_token), do: "user_123"
end
```

## Heartbeat and Keep-Alive

Implement heartbeat to detect dead connections:

```elixir
defmodule HeartbeatHandler do
  use WebSocket.Handler
  require Logger

  @heartbeat_interval 30_000

  @impl true
  def init(socket, _opts) do
    :timer.send_interval(@heartbeat_interval, :heartbeat)
    {:ok, %{last_pong: System.monotonic_time(:millisecond)}}
  end

  @impl true
  def handle_info(:heartbeat, state) do
    now = System.monotonic_time(:millisecond)
    timeout = 60_000

    if now - state.last_pong > timeout do
      Logger.warn("Connection timeout")
      {:close, state}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_text(_socket, "pong", state) do
    {:noreply, %{state | last_pong: System.monotonic_time(:millisecond)}}
  end
end
```

## Message Persistence

Persist messages for offline clients:

```elixir
defmodule PersistentHandler do
  use WebSocket.Handler

  @impl true
  def init(socket, _opts) do
    user_id = get_user_id(socket)

    # Send queued messages
    case MessageQueue.pop(user_id) do
      {:ok, messages} ->
        Enum.each(messages, &WebSocket.Connection.send_text(socket, &1))

      {:error, :not_found} ->
        :ok
    end

    {:ok, %{user_id: user_id}}
  end

  @impl true
  def terminate(socket, _reason, state) do
    # Mark user as offline
    MessageQueue.queue(state.user_id, "User went offline")
    :ok
  end

  defp get_user_id(socket), do: Map.get(socket.query_params, "user_id", ["guest"]) |> List.first()
end
```

## Connection State Synchronization

Synchronize state across multiple connections:

```elixir
defmodule GameStateHandler do
  use WebSocket.Handler

  @impl true
  def init(socket, _opts) do
    # Join the game room
    GameState.join(socket)
    state = GameState.get_state()

    # Send initial state
    WebSocket.Connection.send_text(socket, Jason.encode!(state))

    {:ok, %{}}
  end

  @impl true
  def handle_text(socket, message, state) do
    # Update game state
    case Jason.decode(message) do
      {:ok, action} ->
        GameState.apply_action(action)
        new_state = GameState.get_state()

        # Broadcast to all players
        GameState.broadcast(Jason.encode!(new_state))
        {:noreply, state}

      {:error, _} ->
        {:noreply, state}
    end
  end

  @impl true
  def terminate(socket, _reason, _state) do
    GameState.leave(socket)
    :ok
  end
end
```

## Error Recovery

Implement robust error recovery:

```elixir
defmodule ResilientHandler do
  use WebSocket.Handler
  require Logger

  @max_retries 3

  @impl true
  def init(socket, _opts) do
    {:ok, %{retry_count: 0}}
  end

  @impl true
  def handle_error(socket, :invalid_opcode, state) do
    Logger.warn("Invalid opcode received")

    if state.retry_count < @max_retries do
      {:noreply, %{state | retry_count: state.retry_count + 1}}
    else
      WebSocket.Connection.close(socket, {1002, "Too many errors"})
      {:close, state}
    end
  end

  @impl true
  def terminate(socket, {code, reason}, state) do
    Logger.info("Connection closed: #{code} - #{reason}")

    # Attempt to recover from certain errors
    if recoverable?(code) do
      schedule_reconnect(state)
    end

    :ok
  end

  defp recoverable?(1006), do: true
  defp recoverable?(_), do: false

  defp schedule_reconnect(_state) do
    # Implement reconnection logic
    :ok
  end
end
```

## Compression

Implement message compression for large payloads:

```elixir
defmodule CompressedHandler do
  use WebSocket.Handler

  @impl true
  def handle_text(socket, data, state) do
    compressed = compress(data)
    WebSocket.Connection.send_binary(socket, compressed)
    {:noreply, state}
  end

  def handle_binary(socket, data, state) do
    case decompress(data) do
      {:ok, decompressed} ->
        WebSocket.Connection.send_text(socket, decompressed)
        {:noreply, state}

      {:error, _} ->
        {:noreply, state}
    end
  end

  defp compress(data), do: :zlib.compress(data)
  defp decompress(data), do: :zlib.decompress(data)
end
```

## Message Queue

Implement a message queue for guaranteed delivery:

```elixir
defmodule MessageQueue do
  use GenServer

  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  def publish(topic, message) do
    GenServer.cast(__MODULE__, {:publish, topic, message})
  end

  def subscribe(topic, subscriber) do
    GenServer.cast(__MODULE__, {:subscribe, topic, subscriber})
  end

  def init(_), do: {:ok, %{topics: %{}, queues: %{}}}

  def handle_cast({:publish, topic, message}, state) do
    case Map.get(state.topics, topic) do
      nil ->
        # Queue for offline subscribers
        queue = Map.get(state.queues, topic, []) ++ [message]
        {:noreply, %{state | queues: Map.put(state.queues, topic, queue)}}

      subscribers ->
        Enum.each(subscribers, &send_message(&1, message))
        {:noreply, state}
    end
  end

  def handle_cast({:subscribe, topic, subscriber}, state) do
    # Send queued messages
    queued = Map.get(state.queues, topic, [])
    Enum.each(queued, &send_message(subscriber, &1))

    topics = Map.update(state.topics, topic, [subscriber], fn subs -> [subscriber | subs] end)
    queues = Map.delete(state.queues, topic)

    {:noreply, %{topics: topics, queues: queues}}
  end

  defp send_message(socket, message) do
    WebSocket.Connection.send_text(socket, message)
  rescue
    _ -> :ok
  end
end
```

## Monitoring and Metrics

Track connection metrics:

```elixir
defmodule MetricsHandler do
  use WebSocket.Handler

  @impl true
  def init(socket, _opts) do
    Metrics.increment(:connections_established)
    Metrics.gauge(:active_connections, 1)
    {:ok, %{}}
  end

  @impl true
  def handle_text(_socket, data, state) do
    Metrics.increment(:messages_received)
    Metrics.histogram(:message_size, byte_size(data))
    {:noreply, state}
  end

  @impl true
  def handle_binary(_socket, data, state) do
    Metrics.increment(:bytes_received, byte_size(data))
    {:noreply, state}
  end

  @impl true
  def terminate(_socket, _reason, _state) do
    Metrics.increment(:connections_closed)
    Metrics.gauge(:active_connections, -1)
    :ok
  end
end
```

## Best Practices

1. **Handle Errors Gracefully**: Always implement `handle_error/3` to handle protocol errors
2. **Clean Up Resources**: Use `terminate/3` to clean up resources when connections close
3. **Rate Limit**: Protect your server from abuse with rate limiting
4. **Monitor Connections**: Track connection metrics for observability
5. **Use Supervision**: Ensure proper supervision of all processes
6. **Test Thoroughly**: Test all edge cases including disconnections and errors
7. **Log Important Events**: Log connection lifecycle events for debugging
8. **Timeout Connections**: Implement heartbeat to detect dead connections
9. **Validate Input**: Always validate incoming messages
10. **Handle Backpressure**: Be mindful of message queue sizes
