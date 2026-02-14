defmodule WebSocket.Connection do
  use GenServer

  defstruct socket: nil,
            transport_pid: nil,
            peer: nil,
            path: "/",
            query_params: %{},
            assigns: nil,
            private: nil,
            id: nil,
            joined_at: nil

  def start(opts) do
    GenServer.start(__MODULE__, opts)
  end

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

  def send_text(%__MODULE__{transport_pid: pid}, text) do
    GenServer.cast(pid, {:send, :text, text})
  end

  def send_binary(%__MODULE__{transport_pid: pid}, payload) do
    GenServer.cast(pid, {:send, :binary, payload})
  end

  def close(%__MODULE__{transport_pid: pid}) do
    GenServer.cast(pid, {:send, :close, {1000, "Normal Closure"}})
  end

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
        frames
        |> Enum.reduce_while([], &handle_raw_frame(&1, &2, socket))
        |> Enum.reduce_while(state, fn frame, current_state ->
          handle_frame(
            frame,
            handler_module,
            current_state.connection,
            current_state.handler_state
          )
        end)

        :inet.setopts(socket, active: :once)
        {:noreply, %{state | buffer: rest}}

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

  defp handle_raw_frame(%{opcode: :ping, data: data}, acc, socket) do
    :gen_tcp.send(socket, WebSocket.Frame.encode(:pong, data))
    {:cont, acc}
  end

  defp handle_raw_frame(%{opcode: :close, code: code}, acc, socket) do
    :gen_tcp.send(socket, WebSocket.Frame.encode(:close, {code, ""}))
    :gen_tcp.close(socket)
    {:halt, acc}
  end

  defp handle_raw_frame(%{opcode: :pong}, acc, _) do
    {:cont, acc}
  end

  defp handle_raw_frame(%{fin?: true, opcode: :binary, data: data}, acc, _) do
    {:cont, [{:binary, data} | acc]}
  end

  defp handle_raw_frame(%{fin?: true, opcode: :text, data: data}, acc, _) do
    # TODO: check for utf-8 validity
    {:cont, [{:text, data} | acc]}
  end

  defp handle_raw_frame(%{fin?: false, opcode: :binary, data: data}, acc, _) do
    {:cont, [{:binary, data} | acc]}
  end

  defp handle_raw_frame(%{fin?: false, opcode: :text, data: data}, acc, _) do
    {:cont, [{:text, data} | acc]}
  end

  defp handle_raw_frame(%{opcode: :continuation, data: data}, [{opcode, head} | rest], _) do
    {:cont, [{opcode, head <> data} | rest]}
  end
end
