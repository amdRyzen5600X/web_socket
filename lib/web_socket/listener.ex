defmodule WebSocket.Listener do
  use GenServer

  def start_link(opts) do
    GenServer.start(__MODULE__, opts, name: __MODULE__)
  end

  def init({port, handler_module}) do
    opts = [:binary, packet: 0, active: true, reuseaddr: true]

    case :gen_tcp.listen(port, opts) do
      {:ok, listen_socket} ->
        send(self(), :accept)
        {:ok, %{listen_socket: listen_socket, port: port, handler_module: handler_module}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  def handle_info(
        :accept,
        state = %{listen_socket: listen_socket, handler_module: handler_module}
      ) do
    case :gen_tcp.accept(listen_socket, 1000) do
      {:ok, client_socket} ->
        {:ok, conn_pid} =
          WebSocket.Connection.start({client_socket, handler_module, nil, nil, nil, nil})

        :gen_tcp.controlling_process(client_socket, conn_pid)
        send(self(), :accept)
        {:noreply, state}

      {:error, :timeout} ->
        send(self(), :accept)
        {:noreply, state}

      {:error, reason} ->
        {:stop, reason, state}
    end
  end
end
