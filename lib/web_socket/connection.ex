defmodule WebSocket.Connection do
  @moduledoc """
  GenServer-based WebSocket connection manager.

  This module manages the lifecycle of an individual WebSocket connection.
  It handles the handshake, frame parsing, and message routing to handler
  callbacks.

  ## Usage

  Connections are started automatically by `WebSocket.Listener`. You typically
  don't need to start them manually, but you can:

  ```elixir
  {:ok, client_socket} = :gen_tcp.connect("localhost", 8080, [])
  {:ok, pid} = WebSocket.Connection.start({client_socket, MyHandler, nil, nil, nil, nil})
  ```

  ## Sending Messages

  Use the following functions to send messages to the client:

  ```elixir
  # Send text
  WebSocket.Connection.send_text(socket, "Hello!")

  # Send binary
  WebSocket.Connection.send_binary(socket, <<1, 2, 3>>)

  # Close connection
  WebSocket.Connection.close(socket)
  ```

  ## State Machine

  The connection goes through these states:

  1. `:handshake` - Waiting for HTTP upgrade request
  2. `:open` - Connection established, exchanging frames
  3. `:closed` - Connection terminated

  ## Control Frames

  The following control frames are handled automatically:

  - **Ping**: Automatically responded to with a pong frame
  - **Pong**: Silently acknowledged
  - **Close**: Connection is terminated after sending close response
  """

  use GenServer

  @doc """
  The connection struct containing metadata about a WebSocket connection.

  - `:socket` - The underlying TCP socket
  - `:transport_pid` - The GenServer PID managing this connection
  - `:peer` - Peer address information
  - `:path` - Request path from handshake
  - `:query_params` - Parsed query string parameters
  - `:assigns` - User-assigned data (similar to Phoenix assigns)
  - `:private` - Private data for internal use
  - `:id` - Unique connection identifier
  - `:joined_at` - Timestamp of connection establishment
  """
  @type t :: %__MODULE__{
          socket: port() | nil,
          transport_pid: pid() | nil,
          peer: term() | nil,
          path: String.t(),
          query_params: map(),
          assigns: term() | nil,
          private: term() | nil,
          id: term() | nil,
          joined_at: term() | nil
        }

  defstruct socket: nil,
            transport_pid: nil,
            peer: nil,
            path: "/",
            query_params: %{},
            assigns: nil,
            private: nil,
            id: nil,
            joined_at: nil

  @doc """
  Starts a new WebSocket connection GenServer.

  ## Parameters

  - `opts` - A tuple containing:
    - `client_socket` - The accepted TCP socket
    - `handler_module` - Module implementing `WebSocket.Handler`
    - `peer` - Peer address (currently unused)
    - `headers` - HTTP headers (currently unused)
    - `path` - Request path (currently unused)
    - `query_params` - Query parameters (currently unused)

  ## Returns

  `{:ok, pid}` on success
  """
  def start(opts) do
    GenServer.start(__MODULE__, opts)
  end

  @doc false
  def init({client_socket, handler_module, peer, headers, path, query_params}) do
    :inet.setopts(client_socket, active: :once)

    {:ok,
     %{
       socket: client_socket,
       state: :handshake,
       handler_module: handler_module,
       peer: peer,
       headers: headers,
       path: path,
       query_params: query_params,
       buffer: <<>>
     }}
  end

  @doc """
  Sends a text frame to the WebSocket client.

  ## Parameters

  - `socket` - The connection struct
  - `text` - The text message to send (must be UTF-8 valid)

  ## Example

  ```elixir
  WebSocket.Connection.send_text(socket, "Hello, client!")
  ```
  """
  def send_text(%__MODULE__{transport_pid: pid}, text) do
    GenServer.cast(pid, {:send, :text, text})
  end

  @doc """
  Sends a binary frame to the WebSocket client.

  ## Parameters

  - `socket` - The connection struct
  - `payload` - Binary data to send

  ## Example

  ```elixir
  WebSocket.Connection.send_binary(socket, <<1, 2, 3, 4>>)
  ```
  """
  def send_binary(%__MODULE__{transport_pid: pid}, payload) do
    GenServer.cast(pid, {:send, :binary, payload})
  end

  @doc """
  Closes the WebSocket connection with the default close code (1000).

  ## Parameters

  - `socket` - The connection struct

  ## Example

  ```elixir
  WebSocket.Connection.close(socket)
  ```
  """
  def close(%__MODULE__{transport_pid: pid}) do
    GenServer.cast(pid, {:send, :close, {1000, "Normal Closure"}})
  end

  @doc """
  Closes the WebSocket connection with a custom close code and reason.

  ## Parameters

  - `socket` - The connection struct
  - `{code, payload}` - A tuple containing:
    - `code` - Close code (see RFC 6455 section 7.1.5)
    - `payload` - Close reason string (max 123 bytes)

  ## Common Close Codes

  - 1000 - Normal Closure
  - 1001 - Going Away
  - 1002 - Protocol Error
  - 1003 - Unsupported Data
  - 1008 - Policy Violation
  - 1009 - Message Too Big
  - 1011 - Internal Error

  ## Example

  ```elixir
  WebSocket.Connection.close(socket, {1001, "Server shutting down"})
  ```
  """
  def close(%__MODULE__{transport_pid: pid}, {code, payload}) do
    GenServer.cast(pid, {:send, :close, {code, payload}})
  end

  def handle_cast({:send, :close, {_code, reason} = payload}, state) do
    frame = WebSocket.Frame.encode(:close, payload)
    :gen_tcp.send(state.socket, frame)
    :gen_tcp.close(state.socket)
    {:stop, reason, state}
  end

  def handle_cast({:send, opcode, payload}, state) do
    frame = WebSocket.Frame.encode(opcode, payload)
    :gen_tcp.send(state.socket, frame)
    {:noreply, state}
  end

  def handle_info(
        {:tcp, socket, data},
        state = %{state: :handshake, buffer: buff, handler_module: handler_module}
      ) do
    case WebSocket.Handshake.parse(data, buff) do
      {:ok, handshake, rest} ->
        case WebSocket.Handshake.accept_response(handshake) do
          {:ok, response} ->
            connection = %__MODULE__{socket: socket, transport_pid: self()}
            {:ok, handler_state} = handler_module.init(connection, %{})
            :gen_tcp.send(socket, response)
            :inet.setopts(socket, active: :once)

            {:noreply,
             %{
               state
               | state: :open,
                 buffer: rest,
                 connection: connection,
                 handler_state: handler_state
             }}

          {:error, reason, response} ->
            :gen_tcp.send(socket, response)
            :gen_tcp.close(socket)
            {:stop, reason, state}
        end

      {:more, new_buffer} ->
        :inet.setopts(socket, active: :once)
        {:noreply, %{state | buffer: new_buffer}}

      {:error, reason} ->
        {_, _, response} = WebSocket.Handshake.reject(reason)
        :gen_tcp.send(socket, response)
        :gen_tcp.close(socket)
        {:stop, reason, state}
    end
  end

  def handle_info(
        {:tcp, socket, data},
        %{
          state: :open,
          buffer: buffer,
          handler_module: handler_module,
          connection: connection,
          handler_state: handler_state
        } =
          state
      ) do
    case WebSocket.Frame.parse(data, buffer) do
      {:ok, frames, rest} ->
        new_handler_state =
          frames
          |> Enum.reduce_while(
            [],
            &handle_raw_frame(&1, &2, connection, handler_module, handler_state)
          )
          |> Enum.reduce_while(handler_state, fn frame, current_state ->
            handle_frame(
              frame,
              handler_module,
              connection,
              current_state
            )
          end)

        :inet.setopts(socket, active: :once)
        {:noreply, %{state | buffer: rest, handler_state: new_handler_state}}

      {:more, new_buffer} ->
        :inet.setopts(socket, active: :once)
        {:noreply, %{state | buffer: new_buffer}}

      {:error, reason} ->
        :gen_tcp.send(socket, WebSocket.Frame.encode(:close, {1002, "Protocol error"}))
        :gen_tcp.close(socket)
        {:stop, reason, state}
    end
  end

  def handle_info(
        {:tcp_closed, _socket},
        %{handler_module: handler_module, connection: connection, handler_state: handler_state} =
          state
      ) do
    handler_module.terminate(connection, {1000, "Normal Closure"}, handler_state)
    {:stop, :normal, state}
  end

  def handle_info({:tcp_error, _socket, reason}, state) do
    {:stop, {:error, reason}, state}
  end

  defp handle_frame({:text, frame_payload}, handler_module, socket, state) do
    case handler_module.handle_text(socket, frame_payload, state) do
      {:noreply, new_state} ->
        {:cont, new_state}

      {:reply, response_frame, new_state} ->
        send_text(socket, response_frame)
        {:cont, new_state}

      {:close, new_state} ->
        close(socket)
        {:halt, new_state}

      {:close, {code, reason}, new_state} ->
        close(socket, {code, reason})
        {:halt, new_state}
    end
  end

  defp handle_frame({:binary, frame_payload}, handler_module, socket, state) do
    case handler_module.handle_binary(socket, frame_payload, state) do
      {:noreply, new_state} ->
        {:cont, new_state}

      {:reply, response_frame, new_state} ->
        send_binary(socket, response_frame)
        {:cont, new_state}

      {:close, new_state} ->
        close(socket)
        {:halt, new_state}

      {:close, {code, reason}, new_state} ->
        close(socket, {code, reason})
        {:halt, new_state}
    end
  end

  defp handle_raw_frame(%{opcode: :ping, data: data}, acc, connection, _, _) do
    :gen_tcp.send(connection.socket, WebSocket.Frame.encode(:pong, data))
    {:cont, acc}
  end

  defp handle_raw_frame(
         %{opcode: :close, code: code},
         acc,
         connection,
         handler_module,
         handler_state
       ) do
    :gen_tcp.send(connection.socket, WebSocket.Frame.encode(:close, {code, ""}))
    :gen_tcp.close(connection.socket)
    handler_module.terminate(connection, {code, ""}, handler_state)
    {:halt, acc}
  end

  defp handle_raw_frame(%{opcode: :pong}, acc, _, _, _) do
    {:cont, acc}
  end

  defp handle_raw_frame(%{fin?: true, opcode: :binary, data: data}, acc, _, _, _) do
    {:cont, [{:binary, data} | acc]}
  end

  defp handle_raw_frame(%{fin?: true, opcode: :text, data: data}, acc, _, _, _) do
    # TODO: check for utf-8 validity
    {:cont, [{:text, data} | acc]}
  end

  defp handle_raw_frame(%{fin?: false, opcode: :binary, data: data}, acc, _, _, _) do
    {:cont, [{:binary, data} | acc]}
  end

  defp handle_raw_frame(%{fin?: false, opcode: :text, data: data}, acc, _, _, _) do
    {:cont, [{:text, data} | acc]}
  end

  defp handle_raw_frame(%{opcode: :continuation, data: data}, [{opcode, head} | rest], _, _, _) do
    {:cont, [{opcode, head <> data} | rest]}
  end
end
