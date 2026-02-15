# Getting Started

This guide will walk you through setting up a basic WebSocket server.

## Prerequisites

- Elixir 1.19 or higher
- A web browser or WebSocket client for testing

## Installation

Add `web_socket` to your dependencies in `mix.exs`:

```elixir
defp deps do
  [
    {:web_socket, "~> 0.1.0"}
  ]
end
```

Fetch the dependencies:

```bash
mix deps.get
```

## Your First WebSocket Server

### Step 1: Create a Handler

Create a new file at `lib/my_app/echo_handler.ex`:

```elixir
defmodule MyApp.EchoHandler do
  @moduledoc """
  A simple echo handler that sends back any message it receives.
  """

  use WebSocket.Handler

  @impl true
  def init(socket, _opts) do
    IO.puts("New connection established from #{inspect(socket.peer)}")
    {:ok, %{}}
  end

  @impl true
  def handle_text(socket, data, state) do
    # Echo the message back to the client
    WebSocket.Connection.send_text(socket, "Echo: " <> data)
    {:noreply, state}
  end

  @impl true
  def handle_binary(socket, data, state) do
    # Echo binary data back
    WebSocket.Connection.send_binary(socket, data)
    {:noreply, state}
  end

  @impl true
  def terminate(_socket, {code, reason}, _state) do
    IO.puts("Connection closed: #{code} - #{reason}")
    :ok
  end
end
```

### Step 2: Start the Listener

Update your application module in `lib/my_app/application.ex`:

```elixir
defmodule MyApp.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {WebSocket.Listener, {8080, MyApp.EchoHandler}}
    ]

    opts = [strategy: :one_for_one, name: MyApp.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

### Step 3: Run the Server

Start your application:

```bash
mix run --no-halt
```

### Step 4: Test the Connection

You can test your WebSocket server in several ways:

#### Using JavaScript

Open your browser console and run:

```javascript
const ws = new WebSocket('ws://localhost:8080');

ws.onopen = () => {
  console.log('Connected!');
  ws.send('Hello, WebSocket!');
};

ws.onmessage = (event) => {
  console.log('Received:', event.data);
};

ws.onclose = () => {
  console.log('Connection closed');
};

// Try sending a message
ws.send('Test message');
```

#### Using wscat (command-line tool)

Install wscat globally:

```bash
npm install -g wscat
```

Connect to your server:

```bash
wscat -c ws://localhost:8080
```

Send messages:

```
> Hello, WebSocket!
< Echo: Hello, WebSocket!
> Test message
< Echo: Test message!
```

#### Using Elixir

Create a test file `test/websocket_test.exs`:

```elixir
defmodule WebSocketIntegrationTest do
  use ExUnit.Case

  test "can connect and send messages" do
    # Start the listener
    {:ok, _listener} = WebSocket.Listener.start_link({8081, TestHandler})

    # Connect as a client
    {:ok, socket} = :gen_tcp.connect('localhost', 8081, [:binary, active: false])

    # Send handshake
    handshake = "GET / HTTP/1.1\r\n" <>
      "Host: localhost:8081\r\n" <>
      "Upgrade: websocket\r\n" <>
      "Connection: Upgrade\r\n" <>
      "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n" <>
      "Sec-WebSocket-Version: 13\r\n\r\n"

    :gen_tcp.send(socket, handshake)
    {:ok, response} = :gen_tcp.recv(socket, 0)

    # Verify handshake response
    assert response =~ "101 Switching Protocols"

    # Send a text frame
    text_frame = WebSocket.Frame.encode(:text, "Hello")
    :gen_tcp.send(socket, text_frame)

    # Receive echo response
    {:ok, data} = :gen_tcp.recv(socket, 0)
    {:ok, [frame], ""} = WebSocket.Frame.parse(data, <<>>)

    assert frame.opcode == :text
    assert frame.data == "Echo: Hello"

    # Close connection
    close_frame = WebSocket.Frame.encode(:close, {1000, "Normal Closure"})
    :gen_tcp.send(socket, close_frame)
  end
end
```

## Building a Chat Server

Let's build a simple multi-client chat server.

### Step 1: Create a Chat Room

Create `lib/my_app/chat_room.ex`:

```elixir
defmodule MyApp.ChatRoom do
  @moduledoc """
  Manages chat room participants and broadcasts messages.
  """

  use Agent

  def start_link(_opts) do
    Agent.start_link(fn -> [] end, name: __MODULE__)
  end

  def join(socket) do
    Agent.update(__MODULE__, fn clients -> [socket | clients] end)
  end

  def leave(socket) do
    Agent.update(__MODULE__, fn clients -> List.delete(clients, socket) end)
  end

  def broadcast(message) do
    Agent.get(__MODULE__, fn clients ->
      Enum.each(clients, &WebSocket.Connection.send_text(&1, message))
    end)
  end

  def member_count do
    Agent.get(__MODULE__, &length/1)
  end
end
```

### Step 2: Create the Chat Handler

Create `lib/my_app/chat_handler.ex`:

```elixir
defmodule MyApp.ChatHandler do
  @moduledoc """
  Handler for chat room connections.
  """

  use WebSocket.Handler

  @impl true
  def init(socket, _opts) do
    MyApp.ChatRoom.join(socket)
    count = MyApp.ChatRoom.member_count()

    welcome = "Welcome! There are #{count} members in the chat."
    WebSocket.Connection.send_text(socket, welcome)

    MyApp.ChatRoom.broadcast("A new member joined. Total: #{count}")

    {:ok, %{}}
  end

  @impl true
  def handle_text(socket, data, state) do
    # Broadcast message to all clients including sender
    MyApp.ChatRoom.broadcast(data)
    {:noreply, state}
  end

  @impl true
  def handle_binary(socket, data, state) do
    # Echo binary data to sender only
    WebSocket.Connection.send_binary(socket, data)
    {:noreply, state}
  end

  @impl true
  def terminate(socket, _reason, _state) do
    MyApp.ChatRoom.leave(socket)
    count = MyApp.ChatRoom.member_count()
    MyApp.ChatRoom.broadcast("A member left. Total: #{count}")
    :ok
  end
end
```

### Step 3: Update Application

Update `lib/my_app/application.ex`:

```elixir
defmodule MyApp.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      MyApp.ChatRoom,
      {WebSocket.Listener, {8080, MyApp.ChatHandler}}
    ]

    opts = [strategy: :one_for_one, name: MyApp.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

### Step 4: Test the Chat Room

Open multiple browser windows and connect to `ws://localhost:8080`. Messages sent from one window will be broadcast to all connected clients.

## Building a Simple Game

Let's create a simple number guessing game.

### Game Handler

Create `lib/my_app/game_handler.ex`:

```elixir
defmodule MyApp.GameHandler do
  @moduledoc """
  WebSocket handler for a number guessing game.
  """

  use WebSocket.Handler

  @impl true
  def init(socket, _opts) do
    target = Enum.random(1..100)
    IO.puts("Target number: #{target}")

    message = "Guess the number between 1 and 100!"
    WebSocket.Connection.send_text(socket, message)

    {:ok, %{target: target, guesses: 0}}
  end

  @impl true
  def handle_text(socket, data, state) do
    case Integer.parse(data) do
      {guess, _} ->
        state = %{state | guesses: state.guesses + 1}
        {response, new_state} = check_guess(guess, state.target, state.guesses)

        WebSocket.Connection.send_text(socket, response)

        if guess == state.target do
          {:close, new_state}
        else
          {:noreply, new_state}
        end

      :error ->
        WebSocket.Connection.send_text(socket, "Please enter a valid number!")
        {:noreply, state}
    end
  end

  defp check_guess(guess, target, guesses) when guess == target do
    {"Correct! You guessed it in #{guesses} attempts!", %{target: target, guesses: guesses}}
  end

  defp check_guess(guess, target, guesses) when guess > target do
    {"Too high! Try again.", %{target: target, guesses: guesses}}
  end

  defp check_guess(guess, target, guesses) do
    {"Too low! Try again.", %{target: target, guesses: guesses}}
  end
end
```

## Common Patterns

### Authentication

```elixir
@impl true
def init(socket, _opts) do
  case authenticate(socket) do
    {:ok, user_id} ->
      {:ok, %{user_id: user_id}}

    {:error, reason} ->
      WebSocket.Connection.close(socket, {4008, "Authentication failed"})
      {:stop, reason}
  end
end

defp authenticate(socket) do
  # Extract token from query params or headers
  case Map.get(socket.query_params, "token") do
    [token] -> verify_token(token)
    _ -> {:error, :no_token}
  end
end

defp verify_token(token), do: {:ok, "user_123"}
```

### Sending Periodic Updates

```elixir
@impl true
def init(socket, _opts) do
  :timer.send_interval(1000, :send_time)
  {:ok, %{}}
end

@impl true
def handle_info(:send_time, socket, state) do
  time = DateTime.utc_now() |> DateTime.to_iso8601()
  WebSocket.Connection.send_text(socket, "Current time: #{time}")
  {:noreply, state}
end
```

### Handling Different Message Types

```elixir
@impl true
def handle_text(socket, data, state) do
  case Jason.decode(data) do
    {:ok, %{"type" => "chat", "message" => msg}} ->
      handle_chat(socket, msg, state)

    {:ok, %{"type" => "action", "action" => action}} ->
      handle_action(socket, action, state)

    {:error, _} ->
      WebSocket.Connection.send_text(socket, "Invalid JSON")
      {:noreply, state}
  end
end
```

## Next Steps

- Check out the [Advanced Usage Guide](advanced_usage.md) for more complex patterns
- Read the [API Documentation](https://hexdocs.pm/web_socket) for detailed API reference
- Explore the [RFC 6455](https://tools.ietf.org/html/rfc6455) specification for protocol details
