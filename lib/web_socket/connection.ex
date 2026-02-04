defmodule WebSocket.Connection do
  use GenServer

  def start_link(client_socket) do
    GenServer.start_link(__MODULE__, client_socket)
  end

  def init(client_socket) do
    :inet.setopts(client_socket, active: :once)
    {:ok, %{socket: client_socket, state: :handshake, buffer: <<>>}}
  end

  def handle_info({:tcp, socket, data}, state = %{state: :handshake, buffer: buff}) do
    # TODO: parse the (maybe partialy) recieved message from client
    case WebSocket.Handshake.parse(data, buff) do
      {:ok, handshake, rest} ->
        # TODO: prepare the response for the client
        :gen_tcp.send(socket, WebSocket.Handshake.accept_response(handshake))
        :inet.setopts(socket, active: :once)
        {:noreply, %{state | state: :open, buffer: rest}}

      {:more, new_buffer} ->
        :inet.setopts(socket, active: :once)
        {:noreply, %{state | buffer: new_buffer}}

      {:error, reason} ->
        :gen_tcp.close(socket)
        {:stop, reason, state}
    end
  end

  # Handle TCP messages in open state
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

  # Handle connection close
  def handle_info({:tcp_closed, _socket}, state) do
    {:stop, :normal, state}
  end

  # Handle connection errors
  def handle_info({:tcp_error, _socket, reason}, state) do
    {:stop, {:error, reason}, state}
  end

  defp handle_frame(%{opcode: :ping, payload: payload}, socket) do
    :gen_tcp.send(socket, WebSocket.Frame.encode(:pong, payload))
  end

  defp handle_frame(%{opcode: :close, code: code, reason: reason}, socket) do
    send_close(socket, code, reason)
  end

  defp handle_frame(%{opcode: :text, payload: payload}, _socket) do
    # Handle text message - you can send to a user process or callback
    IO.puts("Received: #{payload}")
  end

  defp handle_frame(%{opcode: :binary, payload: payload}, _socket) do
    # Handle binary message
    IO.puts("Received binary: #{byte_size(payload)} bytes")
  end

  defp send_close(socket, code, reason) do
    :gen_tcp.send(socket, WebSocket.Frame.encode(:close, code, reason))
    :gen_tcp.close(socket)
  end
end
