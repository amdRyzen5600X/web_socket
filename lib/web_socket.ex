defmodule WebSocket do
  @moduledoc """
  Documentation for `WebSocket`.
  """

  def accept(port) do
    {:ok, socket} =
      :gen_tcp.listen(port, [:binary, packet: :line, active: false, reuseaddr: true])

    IO.puts("Accepting connections on port #{port}")
    loop_acceptor(socket)
  end

  defp loop_acceptor(socket) do
    {:ok, client} = :gen_tcp.accept(socket)
    serve(client)
    loop_acceptor(socket)
  end

  defp serve(socket) do
    {:ok, request_line} = :gen_tcp.recv(socket, 0)
    {:ok, path} = parse_request_line(request_line)
    IO.puts(path)

    headers = parse_headers(socket)
    IO.inspect(headers)

    res = validate_headers(headers)
    IO.inspect(res)

    key = Map.get(headers, "sec-websocket-key")
    accept_key = generate_accept_key(key)

    send_response(socket, accept_key)

    serve(socket)
  end

  defp parse_request_line(input) do
    [method, path, version] = String.split(input, " ")

    if method != "GET" || version != "HTTP/1.1" do
      {:error, :invalid_method}
    end

    {:ok, path}
  end

  defp parse_headers(socket, headers \\ %{}) do
    {:ok, input} = :gen_tcp.recv(socket, 0)

    case String.trim_trailing(input) do
      "" ->
        headers

      header ->
        [name, value] = String.split(header, ":", parts: 2)
        value = value |> String.trim_leading()
        name = name |> String.downcase()
        parse_headers(socket, Map.put(headers, name, value))
    end
  end

  defp validate_headers(%{
         "upgrade" => "websocket",
         "connection" => "Upgrade",
         "sec-websocket-key" => _,
         "sec-websocket-version" => "13"
       }) do
    :ok
  end

  defp validate_headers(_) do
    {:error, :invalid_headers}
  end

  defp generate_accept_key(key) do
    Base.encode64(:crypto.hash(:sha, key <> "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"))
  end

  defp send_response(socket, accept_key) do
    response =
      "HTTP/1.1 101 Switching Protocols\r\n" <>
        "Upgrade: websocket\r\n" <>
        "Connection: Upgrade\r\n" <>
        "Sec-WebSocket-Accept: " <> accept_key <> "\r\n\r\n"

    IO.inspect(response)

    :gen_tcp.send(
      socket,
      response
    )
  end
end
