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

  def handle_info({:tcp, socket, data}, %{state: :open, buffer: buffer} = state) do
    case WebSocket.Frame.parse(data, buffer) do
      {:ok, frames, rest} ->
        Enum.reduce_while(frames, [], &handle_frame(&1, &2, socket))

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

  def handle_info({:tcp_closed, _socket}, state) do
    {:stop, :normal, state}
  end

  def handle_info({:tcp_error, _socket, reason}, state) do
    {:stop, {:error, reason}, state}
  end

  defp handle_frame(%{opcode: :ping, data: data}, acc, socket) do
    :gen_tcp.send(socket, WebSocket.Frame.encode(:pong, data))
    {:cont, acc}
  end

  defp handle_frame(%{opcode: :close, code: code}, acc, socket) do
    :gen_tcp.send(socket, WebSocket.Frame.encode(:close, {code, ""}))
    :gen_tcp.close(socket)
    {:halt, acc}
  end

  defp handle_frame(%{opcode: :pong}, acc, _) do
    {:cont, acc}
  end

  defp handle_frame(%{fin?: true, opcode: :binary, data: data}, acc, _) do
    {:cont, [data | acc]}
  end

  defp handle_frame(%{fin?: true, opcode: :text, data: data}, acc, _) do
    # TODO: check for utf-8 validity
    {:cont, [data | acc]}
  end

  defp handle_frame(%{fin?: false, opcode: :binary, data: data}, acc, _) do
    {:cont, [data | acc]}
  end

  defp handle_frame(%{fin?: false, opcode: :text, data: data}, acc, _) do
    {:cont, [data | acc]}
  end

  defp handle_frame(%{opcode: :continuation, data: data}, [head | rest], _) do
    {:cont, [head <> data | rest]}
  end
end
