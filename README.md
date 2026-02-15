# WebSocket

A pure Elixir implementation of the WebSocket protocol (RFC 6455).

This library provides a simple, low-level WebSocket implementation with zero
dependencies. It's perfect for embedding into any OTP application that needs
WebSocket functionality.

## Features

- **Complete Protocol Support** - Full implementation of RFC 6455
- **Zero Dependencies** - Built with only the Elixir standard library
- **GenServer Architecture** - Connection management via OTP
- **Frame Encoding/Decoding** - Support for all frame types (text, binary, ping, pong, close)
- **Fragmentation** - Automatic handling of fragmented messages
- **Customizable Handlers** - Easy-to-use behaviour for defining connection logic
- **Automatic Handshake** - RFC-compliant WebSocket upgrade handshake

## Installation

Add `web_socket` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:web_socket, "~> 0.1.0"}
  ]
end
```

## Quick Start

### 1. Define Your Handler

Create a module that implements the `WebSocket.Handler` behaviour:

```elixir
defmodule MyApp.ChatHandler do
  use WebSocket.Handler

  @impl true
  def init(_socket, _opts) do
    # Initialize your state
    {:ok, %{clients: []}}
  end

  @impl true
  def handle_text(socket, data, state) do
    # Echo messages back to the client
    WebSocket.Connection.send_text(socket, "Echo: #{data}")
    {:noreply, state}
  end
end
```

### 2. Start the Listener

Add the WebSocket listener to your application supervisor:

```elixir
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    children = [
      {WebSocket.Listener, {8080, MyApp.ChatHandler}}
    ]

    opts = [strategy: :one_for_one, name: MyApp.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

### 3. Connect from a Client

Now connect to your WebSocket server from JavaScript:

```javascript
const ws = new WebSocket('ws://localhost:8080');

ws.onopen = () => {
  console.log('Connected to WebSocket server');
};

ws.onmessage = (event) => {
  console.log('Received:', event.data);
};

ws.onclose = () => {
  console.log('Disconnected from WebSocket server');
};

ws.send('Hello, server!');
```

## Usage Examples

### Broadcasting Messages

```elixir
defmodule ChatRoom do
  use Agent
  use WebSocket.Handler

  def start_link(_opts), do: Agent.start_link(fn -> [] end, name: __MODULE__)

  def add_client(socket), do: Agent.update(__MODULE__, fn clients -> [socket | clients] end)

  def broadcast(message) do
    Agent.get(__MODULE__, fn clients ->
      Enum.each(clients, &WebSocket.Connection.send_text(&1, message))
    end)
  end

  @impl true
  def init(socket, _opts) do
    add_client(socket)
    {:ok, %{}}
  end

  @impl true
  def handle_text(socket, data, state) do
    broadcast("#{data}")
    {:noreply, state}
  end
end
```

### Handling Binary Data

```elixir
defmodule ImageHandler do
  use WebSocket.Handler

  @impl true
  def handle_binary(socket, data, state) do
    # Process binary data
    processed = process_image(data)

    # Send back the result
    WebSocket.Connection.send_binary(socket, processed)
    {:noreply, state}
  end

  defp process_image(data), do: data
end
```

### Custom Error Handling

```elixir
defmodule SecureHandler do
  use WebSocket.Handler

  @impl true
  def handle_error(_socket, reason, state) do
    Logger.warn("WebSocket error: #{inspect(reason)}")
    {:close, state}
  end
end
```

### Connection Metadata

```elixir
defmodule AuthHandler do
  use WebSocket.Handler

  @impl true
  def init(socket, _opts) do
    # Access connection metadata
    socket_id = socket.id
    path = socket.path
    query_params = socket.query_params

    IO.puts("New connection: #{socket_id} at #{path}")

    {:ok, %{authenticated: true}}
  end
end
```

## Architecture

The library consists of several modules that work together:

- **`WebSocket.Listener`** - Accepts incoming TCP connections on a port
- **`WebSocket.Connection`** - GenServer managing individual WebSocket connections
- **`WebSocket.Handshake`** - Handles the HTTP upgrade handshake
- **`WebSocket.Frame`** - Encodes and decodes WebSocket frames
- **`WebSocket.Handler`** - Behaviour for defining connection handlers

### Connection Lifecycle

```
Client Request → TCP Accept → Handshake → Open → Messages → Close
                     ↓              ↓         ↓
               Listener     Handshake   Connection
                               ↓
                           Handler.init()
```

### Supervisor Tree

```
Application
  └── WebSocket.Listener
       └── WebSocket.Connection (dynamic)
            └── Handler Module
```

## API Reference

### WebSocket.Listener

```elixir
# Start listener on port 8080 with MyHandler
{:ok, pid} = WebSocket.Listener.start_link({8080, MyHandler})
```

### WebSocket.Connection

```elixir
# Send text message
WebSocket.Connection.send_text(socket, "Hello!")

# Send binary message
WebSocket.Connection.send_binary(socket, <<1, 2, 3>>)

# Close connection (default code 1000)
WebSocket.Connection.close(socket)

# Close connection with custom code
WebSocket.Connection.close(socket, {1001, "Server shutting down"})
```

### WebSocket.Frame

```elixir
# Encode a frame
frame = WebSocket.Frame.encode(:text, "Hello")

# Decode frames
{:ok, [frame], ""} = WebSocket.Frame.parse(data, buffer)
```

## Close Codes

Common WebSocket close codes (RFC 6455):

- `1000` - Normal Closure
- `1001` - Going Away
- `1002` - Protocol Error
- `1003` - Unsupported Data
- `1008` - Policy Violation
- `1009` - Message Too Big
- `1011` - Internal Error

## Performance Considerations

- Each connection is a separate GenServer process
- Control frames (ping, pong, close) are handled automatically
- Frame fragmentation is handled transparently
- Use `{:reply, frame, state}` for immediate responses
- Use `{:noreply, state}` when you don't need to respond

## Testing

```elixir
# Integration test example
defmodule MyAppWebTest do
  use ExUnit.Case

  test "handshake and message exchange" do
    # Start your application
    {:ok, listener} = WebSocket.Listener.start_link({8080, TestHandler})

    # Connect as a client
    {:ok, socket} = :gen_tcp.connect('localhost', 8080, [:binary, active: false])

    # Send handshake
    handshake = "GET / HTTP/1.1\r\n" <>
      "Host: localhost:8080\r\n" <>
      "Upgrade: websocket\r\n" <>
      "Connection: Upgrade\r\n" <>
      "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n" <>
      "Sec-WebSocket-Version: 13\r\n\r\n"

    :gen_tcp.send(socket, handshake)
    {:ok, response} = :gen_tcp.recv(socket, 0)
    assert response =~ "101 Switching Protocols"
  end
end
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

[Your License Here]

## Resources

- [RFC 6455 - The WebSocket Protocol](https://tools.ietf.org/html/rfc6455)
- [MDN Web Docs - WebSocket API](https://developer.mozilla.org/en-US/docs/Web/API/WebSocket)
- [Elixir Documentation](https://hexdocs.pm/elixir)

## Acknowledgments

Built with using Elixir and the power of the BEAM.
