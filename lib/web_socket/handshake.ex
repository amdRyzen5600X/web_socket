defmodule WebSocket.Handshake do
  @moduledoc """
  HTTP WebSocket handshake parser and validator.

  This module handles the HTTP upgrade request from the client, validates
  required headers, and generates the appropriate response.

  ## Handshake Process

  1. Parse HTTP request line (GET /path HTTP/1.1)
  2. Parse HTTP headers
  3. Validate required WebSocket headers:
     - `Upgrade: websocket`
     - `Connection: Upgrade`
     - `Sec-WebSocket-Key: <base64>`
     - `Sec-WebSocket-Version: 13`
  4. Generate response with `Sec-WebSocket-Accept` header

  ## Example

  ```elixir
  handshake_request = "GET /chat HTTP/1.1\\r\\n" <>
    "Host: localhost:8080\\r\\n" <>
    "Upgrade: websocket\\r\\n" <>
    "Connection: Upgrade\\r\\n" <>
    "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\\r\\n" <>
    "Sec-WebSocket-Version: 13\\r\\n" <>
    "\\r\\n"

  case WebSocket.Handshake.parse(handshake_request, <<>>) do
    {:ok, handshake_data, ""} ->
      {:ok, response} = WebSocket.Handshake.accept_response(handshake_data)
      # Send response to client

    {:error, reason} ->
      # Handle error
  end
  ```
  """

  @doc """
  Parses an HTTP WebSocket handshake request.

  ## Parameters

  - `data` - Incoming TCP data
  - `buff` - Previously buffered data

  ## Returns

  - `{:ok, handshake, rest}` - Successfully parsed handshake with remaining data
  - `{:more, buffer}` - Incomplete request, data buffered
  - `{:error, reason}` - Invalid request

  ## Example

  ```elixir
  {:ok, handshake, ""} = WebSocket.Handshake.parse(request, <<>>)
  handshake["path"] #=> ["/chat"]
  handshake["host"] #=> ["localhost:8080"]
  ```
  """
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
      ["GET", rest] ->
        parse_path(rest)

      [_, _] ->
        {:error, :invalid_method}

      [_] ->
        :more
    end
  end

  defp parse_path(input) do
    case String.split(input, " ", parts: 2) do
      ["/" <> _ = path, rest] ->
        handshake = Map.put(%{}, "path", [path])
        parse_http(rest, handshake)

      ["/" <> _] ->
        :more

      [_, _] ->
        {:error, :invalid_path}

      [_] ->
        :more
    end
  end

  defp parse_http(input, handshake) do
    case String.split(input, "\r\n", parts: 2) do
      ["HTTP/1.1", rest] ->
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

      [header, rest] ->
        case parse_header(header) do
          {:ok, key, values} ->
            {_, handshake} =
              handshake
              |> Map.get_and_update(key, fn v ->
                new =
                  if v != nil do
                    v ++ values
                  else
                    values
                  end

                {v, new}
              end)

            parse_headers(rest, handshake)

          {:error, reason} ->
            {:error, reason}
        end

      [_header] ->
        :more

      [] ->
        :more
    end
  end

  defp parse_header(header_line) do
    case String.split(header_line, ":", parts: 2) do
      [key, value] ->
        key = String.downcase(key)
        value = String.trim(value) |> String.split(",") |> Enum.map(&String.trim/1)
        {:ok, key, value}

      _ ->
        {:error, :invalid_header_syntax}
    end
  end

  @doc """
  Validates the handshake and generates an HTTP response.

  ## Parameters

  - `handshake` - Parsed handshake data map

  ## Returns

  - `{:ok, response}` - HTTP 101 response with WebSocket accept key
  - `{:error, reason, response}` - HTTP error response

  ## Example

  ```elixir
  {:ok, response} = WebSocket.Handshake.accept_response(handshake)
  # response: "HTTP/1.1 101 Switching Protocols\\r\\n..."
  ```
  """
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

  defp validate(%{"sec-websocket-key" => [head | _]} = handshake) when head != "" do
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
    {:error, :invalid_header_not_enough}
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
    {:error, :invalid_header_not_enough}
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

  @doc """
  Generates an HTTP error response for failed handshakes.

  ## Parameters

  - `reason` - Atom indicating the failure reason

  ## Returns

  `{:error, reason, response}` - Error tuple with HTTP response

  ## Error Responses

  - `:invalid_path` - HTTP 404 Not Found
  - `:invalid_method` - HTTP 400 Bad Request
  - `:invalid_http_version` - HTTP 400 Bad Request
  - `:invalid_header_upgrade` - HTTP 400 Bad Request
  - `:invalid_header_connection` - HTTP 400 Bad Request
  - `:invalid_header_sec_ws_key` - HTTP 400 Bad Request
  - `:invalid_header_sec_ws_version` - HTTP 400 Bad Request
  - `:invalid_header_not_enough` - HTTP 400 Bad Request
  """
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
