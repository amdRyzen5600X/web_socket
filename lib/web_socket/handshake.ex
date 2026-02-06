# TODO: envoke a user provided before_connection(headers) callback before accepting the connection
defmodule WebSocket.Handshake do
  def parse(data, buff) do
    data_to_parse = buff <> data

    case parse_request_line(data_to_parse) do
      :more ->
        {:more, data_to_parse}

      {:error, reason} ->
        {:error, reason}

      ok ->
        ok
    end
  end

  defp parse_request_line(input) do
    case String.split(input, " ", parts: 2) do
      ["GET", rest] when rest != [] ->
        parse_path(rest)

      [_, _] ->
        {:error, :invalid_method}

      [_] ->
        :more
    end
  end

  defp parse_path(input) do
    case String.split(input, " ", parts: 2) do
      ["/" <> _ = path, rest] when rest != [] ->
        handshake = Map.put(%{}, "path", [path])
        parse_http(rest, handshake)

      ["/" <> _, _] ->
        {:error, :invalid_path}

      ["/" <> _] ->
        :more

      [_] ->
        {:error, :invalid_path}
    end
  end

  defp parse_http(input, handshake) do
    case String.split(input, "\r\n", parts: 2) do
      ["HTTP/1.1", rest] when rest != [] ->
        parse_headers(rest, handshake)

      [_, _] ->
        {:error, :invalid_http_version}

      [_] ->
        :more
    end
  end

  defp parse_headers(input, handshake) do
    case String.split(input, "\r\n", parts: 2) do
      ["", rest] ->
        {:ok, handshake, rest}

      [header, rest] when rest != [] ->
        case parse_header(header) do
          {:ok, key, value} ->
            {_, handshake} =
              handshake
              |> Map.get_and_update(key, fn v ->
                new =
                  if v != nil do
                    List.insert_at(v, -1, value)
                  else
                    [value]
                  end

                {v, new}
              end)

            parse_headers(rest, handshake)

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp parse_header(header_line) do
    case String.split(header_line, ":", parts: 2) do
      [key, value] ->
        key = String.downcase(key)
        value = String.trim(value)
        {:ok, key, value}

      _ ->
        {:error, :invalid_header_syntax}
    end
  end

  # TODO: parse the "path" value from the map, end ensure the validity of the value
  def accept_response(handshake) do
    validate_result = validate(handshake)

    case validate_result do
      {:ok, handshake} ->
        accept(handshake)

      {:error, reason} ->
        reject(reason)
    end
  end

  defp validate(%{"upgrade" => [head | tail]} = handshake) when tail != [] do
    if head |> String.downcase() != "websocket" do
      handshake
      |> Map.put("upgrade", tail)
      |> validate()
    else
      handshake
      |> Map.put("upgrade", :ok)

      validate(handshake)
    end
  end

  defp validate(%{"upgrade" => [head | _]} = handshake) do
    if head |> String.downcase() == "websocket" do
      handshake
      |> Map.put("upgrade", :ok)
      |> validate()
    else
      {:error, :invalid_header_upgrade}
    end
  end

  defp validate(%{"connection" => [head | tail]} = handshake) when tail != [] do
    if head |> String.downcase() != "upgrade" do
      handshake
      |> Map.put("connection", tail)
      |> validate()
    else
      handshake
      |> Map.put("connection", :ok)

      validate(handshake)
    end
  end

  defp validate(%{"connection" => [head | _]} = handshake) do
    if head |> String.downcase() == "upgrade" do
      handshake
      |> Map.put("connection", :ok)
      |> validate()
    else
      {:error, :invalid_header_connection}
    end
  end

  defp validate(%{"sec-websocket-key" => [head | _]} = handshake) when head != [] do
    handshake
    |> Map.put("sec-elixir-custom-key", [head])
    |> Map.put("sec-websocket-key", :ok)
    |> validate()
  end

  defp validate(%{"sec-websocket-key" => [_]}) do
    {:error, :invalid_header_sec_ws_key}
  end

  defp validate(%{"sec-websocket-version" => ["13"]} = handshake) do
    handshake
    |> Map.put("sec-websocket-version", :ok)
    |> validation_accept()
  end

  defp validate(%{"sec-websocket-version" => [_]}) do
    {:error, :invalid_header_sec_ws_version}
  end

  defp validate(_) do
    {:error, :invalid_header_not_enouth}
  end

  defp validation_accept(
         %{
           "upgrade" => :ok,
           "connection" => :ok,
           "sec-websocket-key" => :ok,
           "sec-websocket-version" => :ok
         } = handshake
       ) do
    {:ok, handshake}
  end

  defp validation_accept(_) do
    {:error, :invalid_header_not_enouth}
  end

  defp accept(handshake) do
    [key] = handshake |> Map.get("sec-elixir-custom-key")
    accept_key = generate_accept_key(key)

    response =
      "HTTP/1.1 101 Switching Protocols\r\n" <>
        "Upgrade: websocket\r\n" <>
        "Connection: Upgrade\r\n" <>
        "Sec-WebSocket-Accept: " <>
        accept_key <>
        "\r\n" <>
        "\r\n"

    {:ok, response}
  end

  def reject(:invalid_path) do
    response =
      "HTTP/1.1 404 Not Found\r\n" <>
        "\r\n"

    {:error, :invalid_path, response}
  end

  def reject(reason) do
    response =
      "HTTP/1.1 400 Bad Request\r\n" <>
        "\r\n"

    {:error, reason, response}
  end

  defp generate_accept_key(key) do
    :crypto.hash(:sha, key <> "258EAFA5-E914-47DA-95CA-C5AB0DC85B11")
    |> Base.encode64()
  end
end
