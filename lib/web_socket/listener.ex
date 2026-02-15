defmodule WebSocket.Listener do
  @moduledoc """
  GenServer that listens for incoming TCP connections and spawns WebSocket connections.

  The listener opens a TCP socket on the specified port and accepts incoming
  connections. For each accepted connection, it spawns a new `WebSocket.Connection`
  GenServer process to handle the WebSocket protocol.

  ## Usage

  Start the listener in your application supervisor:

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

  ## Parameters

  - `port` - TCP port number to listen on
  - `handler_module` - Module implementing `WebSocket.Handler` behaviour

  ## Supervisor Tree

  ```
  WebSocket.Listener (named process)
  └── WebSocket.Connection (dynamic, one per client)
      └── Handler Module
  ```
  """

  use GenServer

  @doc """
  Starts the WebSocket listener GenServer.

  ## Parameters

  - `opts` - A tuple containing:
    - `port` - TCP port number
    - `handler_module` - Module implementing `WebSocket.Handler`

  ## Returns

  `{:ok, pid}` on success
  `{:error, reason}` on failure

  ## Example

  ```elixir
  {:ok, pid} = WebSocket.Listener.start_link({8080, MyHandler})
  ```
  """
  def start_link(opts) do
    GenServer.start(__MODULE__, opts, name: __MODULE__)
  end

  @doc false
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
