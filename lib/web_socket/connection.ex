defmodule WebSocket.Connection do
  use GenServer

  def start(client_socket) do
    GenServer.start(__MODULE__, client_socket)
  end

  def init(client_socket) do
    :inet.setopts(client_socket, active: :once)
    {:ok, %{socket: client_socket, state: :handshake, buffer: <<>>}}
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
        Enum.each(frames, &handle_frame(&1, socket))
        :inet.setopts(socket, active: :once)
        {:noreply, %{state | buffer: rest}}

      {:more, new_buffer} ->
        :inet.setopts(socket, active: :once)
        {:noreply, %{state | buffer: new_buffer}}

      {:error, reason} ->
        send_close(socket, 1002, "Protocol error")
        {:stop, reason, state}
    end
  end

  def handle_info({:tcp_closed, _socket}, state) do
    {:stop, :normal, state}
  end

  def handle_info({:tcp_error, _socket, reason}, state) do
    {:stop, {:error, reason}, state}
  end

  defp handle_frame(%{opcode: :ping, data: payload}, socket) do
    :gen_tcp.send(socket, WebSocket.Frame.encode(:pong, payload))
  end

  defp handle_frame(%{opcode: :close, code: code, data: reason}, socket) do
    send_close(socket, code, reason)
  end

  defp handle_frame(%{opcode: opcode, data: payload}, _socket) when opcode in [:text, :binary] do
    IO.puts("Received: #{payload}")
  end

  defp send_close(socket, code, reason) do
    :gen_tcp.send(socket, WebSocket.Frame.encode(:close, {code, reason}))
    :gen_tcp.close(socket)
  end
end
