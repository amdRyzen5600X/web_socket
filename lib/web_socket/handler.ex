defmodule WebSocket.Handler do
  @callback init(socket :: WebSocket.Connection.t(), opts :: map()) :: {:ok, state :: any()}
  @callback handle_text(socket :: WebSocket.Connection.t(), data :: binary(), state :: any()) ::
              {:noreply, new_state :: any()}
              | {:reply, frame :: bitstring(), new_state :: any()}
              | {:close, new_state :: any()}
              | {:close, {code :: integer(), reason :: binary()}, new_state :: any()}
  @callback handle_binary(socket :: WebSocket.Connection.t(), data :: binary(), state :: any()) ::
              {:noreply, new_state :: any()}
              | {:reply, frame :: bitstring(), new_state :: any()}
              | {:close, new_state :: any()}
              | {:close, {code :: integer(), reason :: binary()}, new_state :: any()}
  @callback terminate(
              socket :: WebSocket.Connection.t(),
              {code :: integer(), reason :: binary()},
              state :: any()
            ) :: term()
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
