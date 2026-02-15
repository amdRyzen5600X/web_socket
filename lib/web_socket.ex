defmodule WebSocket do
  @moduledoc """
  A pure Elixir implementation of the WebSocket protocol (RFC 6455).

  This library provides a simple, low-level WebSocket implementation that can be
  embedded into any OTP application. It includes full support for the WebSocket
  handshake, frame encoding/decoding, and connection management.

  ## Features

  - Complete WebSocket protocol implementation (RFC 6455)
  - GenServer-based connection management
  - Support for text, binary, ping, pong, and close frames
  - Automatic frame fragmentation and reassembly
  - Configurable handler behavior
  - Zero dependencies (only Elixir standard library)

  ## Quick Start

  ### 1. Define Your Handler

  Create a module that implements the `WebSocket.Handler` behaviour:

  ```elixir
  defmodule MyApp.ChatHandler do
    use WebSocket.Handler

    @impl true
    def init(_socket, _opts) do
      {:ok, %{clients: []}}
    end

  @impl true
  def handle_text(socket, data, state) do
    # Broadcast message to all clients
    WebSocket.Connection.send_text(socket, "Echo: " <> data)
    {:noreply, state}
  end
  end
  ```

  ### 2. Start the Listener

  Start the WebSocket listener in your application supervisor:

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

  Connect to your WebSocket server from JavaScript:

  ```javascript
  const ws = new WebSocket('ws://localhost:8080');
  ws.onmessage = (event) => console.log(event.data);
  ws.send('Hello, server!');
  ```

  ## Architecture

  The library consists of several modules:

  - `WebSocket.Listener` - Accepts incoming TCP connections
  - `WebSocket.Connection` - Manages individual WebSocket connections as GenServers
  - `WebSocket.Handshake` - Handles the WebSocket upgrade handshake
  - `WebSocket.Frame` - Encodes and decodes WebSocket frames
  - `WebSocket.Handler` - Behaviour definition for connection handlers

  ## Connection Lifecycle

  1. **Accept**: `WebSocket.Listener` accepts a TCP connection
  2. **Handshake**: `WebSocket.Connection` parses and validates the HTTP upgrade request
  3. **Open**: Connection is established and handler is initialized
  4. **Messages**: Text and binary frames are routed to handler callbacks
  5. **Close**: Connection is closed via close frame or TCP shutdown

  ## Error Handling

  The library handles various error conditions:

  - Invalid handshake requests (400 Bad Request)
  - Missing required headers (400 Bad Request)
  - Protocol violations (1002 Protocol Error)
  - Network errors (connection termination)

  For custom error handling, implement the optional `c:WebSocket.Handler.handle_error/3` callback.
  """
end
