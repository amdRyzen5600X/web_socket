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

    headers_list = Map.to_list(headers)
    res = validate_headers(headers_list)
    IO.inspect(res)

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
        value = value |> String.trim_leading() |> String.downcase()
        name = name |> String.downcase()
        parse_headers(socket, Map.put(headers, name, value))
    end
  end

  defp validate_headers([header | rest]) do
    valid? =
      case header do
        {"connection", value} -> if value == "upgrade", do: true, else: false
        {"sec-websocket-version", value} -> if value == "13", do: true, else: false
        {"upgrade", value} -> if value == "websocket", do: true, else: false
        {"sec-websocket-key", _} -> true
        _ -> true
      end

    if valid? do
      validate_headers(rest)
    else
      :invalid
    end
  end

  defp validate_headers([]) do
    :ok
  end
end
