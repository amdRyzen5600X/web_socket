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

  def start(client_socket) do
    GenServer.start(__MODULE__, client_socket)
  end

  def init(client_socket) do
    :inet.setopts(client_socket, active: :once)
    {:ok, %{socket: client_socket, state: :handshake, buffer: <<>>}}
  end

  def send_text(socket, text) do
    frame = WebSocket.Frame.encode(:text, text)
    :gen_tcp.send(socket, frame)
  end

  def send_binary(socket, payload) do
    frame = WebSocket.Frame.encode(:binary, payload)
    :gen_tcp.send(socket, frame)
  end

  def send_ping(socket) do
    frame = WebSocket.Frame.encode(:ping, "")
    :gen_tcp.send(socket, frame)
  end

  def send_ping(socket, payload) do
    frame = WebSocket.Frame.encode(:ping, payload)
    :gen_tcp.send(socket, frame)
  end

  def close(socket) do
    frame = WebSocket.Frame.encode(:close, {1000, "Normal Closure"})
    :gen_tcp.send(socket, frame)
  end

  def close(socket, {code, payload}) do
    frame = WebSocket.Frame.encode(:close, {code, payload})
    :gen_tcp.send(socket, frame)
  end

  def handle_info({:tcp, socket, data}, state = %{state: :handshake, buffer: buff}) do
    case WebSocket.Handshake.parse(data, buff) do
      {:ok, handshake, rest} ->
        case WebSocket.Handshake.accept_response(handshake) do
          {:ok, response} ->
            :gen_tcp.send(socket, response)
            :inet.setopts(socket, active: :once)
            {:noreply, %{state | state: :open, buffer: rest}}

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
