defmodule WebSocket.Handler do
  @moduledoc """
  Behaviour for defining WebSocket connection handlers.

  This behaviour defines the callbacks that a module must implement to handle
  WebSocket connections. Use `use WebSocket.Handler` to get default implementations
  for all callbacks.

  ## Defining a Handler

  ```elixir
  defmodule MyHandler do
    use WebSocket.Handler

    @impl true
    def init(socket, _opts) do
      # Initialize your state
      {:ok, %{count: 0}}
    end

    @impl true
    def handle_text(socket, data, state) do
      # Handle incoming text messages
      WebSocket.Connection.send_text(socket, "Received: " <> data)
      {:noreply, %{state | count: state.count + 1}}
    end

    @impl true
    def handle_binary(socket, data, state) do
      # Handle incoming binary messages
      WebSocket.Connection.send_binary(socket, data)
      {:noreply, state}
    end

    @impl true
    def terminate(socket, _reason, _state) do
      # Clean up resources
      IO.puts("Connection closed")
      :ok
    end
  end
  ```

  ## Callback Return Values

  ### `handle_text/3` and `handle_binary/3`

  - `{:noreply, state}` - Continue without sending a response
  - `{:reply, frame, state}` - Send a text or binary frame back to client
  - `{:close, state}` - Close the connection with default code
  - `{:close, {code, reason}, state}` - Close with custom code and reason

  ### `handle_error/3`

  - `{:continue, state}` - Continue processing (default)
  - `{:close, state}` - Close the connection
  - `{:error, reason, state}` - Custom error handling

  ## Default Implementations

  When using `use WebSocket.Handler`, all callbacks get default implementations:

  - `init/2` - Returns `{:ok, %{}}`
  - `handle_text/3` - Returns `{:noreply, state}`
  - `handle_binary/3` - Returns `{:noreply, state}`
  - `handle_error/3` - Returns `{:continue, state}`
  - `terminate/3` - Returns `:ok`
  """

  @doc """
  Called when a new WebSocket connection is established.

  This is the place to initialize your connection state.

  ## Parameters

  - `socket` - The WebSocket connection struct
  - `opts` - Options passed during connection startup (currently empty)

  ## Returns

  `{:ok, state}` - The initial state for this connection
  """
  @callback init(socket :: WebSocket.Connection.t(), opts :: map()) :: {:ok, state :: any()}

  @doc """
  Called when a text frame is received from the client.

  ## Parameters

  - `socket` - The WebSocket connection struct
  - `data` - The text payload (UTF-8 string)
  - `state` - The current handler state

  ## Returns

  - `{:noreply, new_state}` - Continue without sending a response
  - `{:reply, frame, new_state}` - Send a text frame back
  - `{:close, new_state}` - Close the connection
  - `{:close, {code, reason}, new_state}` - Close with custom code

  ## Example

  ```elixir
  @impl true
  def handle_text(socket, "ping", state) do
    WebSocket.Connection.send_text(socket, "pong")
    {:noreply, state}
  end

  def handle_text(socket, message, state) do
    {:reply, "Echo: " <> message, state}
  end
  ```
  """
  @callback handle_text(socket :: WebSocket.Connection.t(), data :: binary(), state :: any()) ::
              {:noreply, new_state :: any()}
              | {:reply, frame :: bitstring(), new_state :: any()}
              | {:close, new_state :: any()}
              | {:close, {code :: integer(), reason :: binary()}, new_state :: any()}

  @doc """
  Called when a binary frame is received from the client.

  ## Parameters

  - `socket` - The WebSocket connection struct
  - `data` - The binary payload
  - `state` - The current handler state

  ## Returns

  - `{:noreply, new_state}` - Continue without sending a response
  - `{:reply, frame, new_state}` - Send a binary frame back
  - `{:close, new_state}` - Close the connection
  - `{:close, {code, reason}, new_state}` - Close with custom code

  ## Example

  ```elixir
  @impl true
  def handle_binary(socket, data, state) do
    # Process binary data
    processed = process_data(data)
    WebSocket.Connection.send_binary(socket, processed)
    {:noreply, state}
  end
  ```
  """
  @callback handle_binary(socket :: WebSocket.Connection.t(), data :: binary(), state :: any()) ::
              {:noreply, new_state :: any()}
              | {:reply, frame :: bitstring(), new_state :: any()}
              | {:close, new_state :: any()}
              | {:close, {code :: integer(), reason :: binary()}, new_state :: any()}

  @doc """
  Called when the WebSocket connection is terminated.

  This is the place to perform cleanup operations such as closing database
  connections, removing from tracking lists, etc.

  ## Parameters

  - `socket` - The WebSocket connection struct
  - `{code, reason}` - Close code and reason tuple
  - `state` - The current handler state

  ## Returns

  Any term (typically `:ok`)

  ## Example

  ```elixir
  @impl true
  def terminate(_socket, {code, reason}, state) do
    Logger.info("Connection closed: " <> Integer.to_string(code) <> " - " <> reason)
    # Clean up resources
    :ok
  end
  ```
  """
  @callback terminate(
              socket :: WebSocket.Connection.t(),
              {code :: integer(), reason :: binary()},
              state :: any()
            ) :: term()
  @doc """
  Called when a protocol error occurs during connection.

  This callback allows custom error handling for various protocol violations.
  It's optional and defaults to continuing with the current state.

  ## Parameters

  - `socket` - The WebSocket connection struct
  - `reason` - The error reason atom
  - `state` - The current handler state

  ## Error Reasons

  ### Handshake Errors

  - `:invalid_method` - Not a GET request
  - `:invalid_path` - Invalid request path
  - `:invalid_http_version` - Not HTTP/1.1
  - `:invalid_header_syntax` - Malformed header line
  - `:invalid_header_upgrade` - Missing/invalid Upgrade header
  - `:invalid_header_connection` - Missing/invalid Connection header
  - `:invalid_header_sec_ws_key` - Missing/invalid Sec-WebSocket-Key
  - `:invalid_header_sec_ws_version` - Not version 13
  - `:invalid_header_not_enough` - Missing required headers

  ### Frame Errors

  - `:invalid_opcode` - Unknown frame opcode
  - `:use_of_reserved` - Use of reserved bits

  ## Returns

  - `{:continue, new_state}` - Continue processing (default)
  - `{:close, new_state}` - Close the connection
  - `{:error, reason, new_state}` - Custom error handling

  ## Example

  ```elixir
  @impl true
  def handle_error(_socket, :invalid_opcode, state) do
    Logger.warn("Received invalid opcode")
    {:close, state}
  end

  def handle_error(_socket, reason, state) do
    Logger.debug("Protocol error: " <> Atom.to_string(reason))
    {:continue, state}
  end
  ```
  """
  @callback handle_error(
              socket :: WebSocket.Connection.t(),
              reason ::
                :invalid_method
                | :invalid_path
                | :invalid_http_version
                | :invalid_header_syntax
                | :invalid_header_upgrade
                | :invalid_header_connection
                | :invalid_header_sec_ws_key
                | :invalid_header_sec_ws_version
                | :invalid_header_not_enough
                | :invalid_opcode
                | :use_of_reserved,
              state :: any()
            ) ::
              {:continue, new_state :: any()}
              | {:close, new_state :: any()}
              | {:error, reason :: any(), new_state :: any()}

  @optional_callbacks [terminate: 3, handle_error: 3]

  @doc """
  Imports default implementations of all callbacks.

  When you `use WebSocket.Handler`, all callbacks get default implementations
  that you can override as needed.

  ## Example

  ```elixir
  defmodule MyHandler do
    use WebSocket.Handler

    # Only override what you need
    @impl true
    def handle_text(socket, data, state) do
      {:reply, "Echo: " <> data, state}
    end
  end
  ```
  """
  defmacro __using__(_opts) do
    quote do
      @behaviour WebSocket.Handler

      @impl true
      def init(_, _) do
        {:ok, %{}}
      end

      @impl true
      def handle_text(_, _, state) do
        {:noreply, state}
      end

      @impl true
      def handle_binary(_, _, state) do
        {:noreply, state}
      end

      @impl true
      def handle_error(_, _, state) do
        {:continue, state}
      end

      @impl true
      def terminate(_, _, _) do
        :ok
      end
    end
  end
end
