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
  end
end
