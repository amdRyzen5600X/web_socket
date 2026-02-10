defmodule WebSocket.HandshakeTest do
  use ExUnit.Case
  doctest WebSocket.Handshake

  alias WebSocket.Handshake

  describe "parse/2" do
    test "parses a valid handshake request" do
      request =
        "GET /chat HTTP/1.1\r\n" <>
          "Host: localhost:8080\r\n" <>
          "Upgrade: websocket\r\n" <>
          "Connection: Upgrade\r\n" <>
          "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n" <>
          "Sec-WebSocket-Version: 13\r\n" <>
          "\r\n"

      assert {:ok, handshake, ""} = Handshake.parse(request, <<>>)
      assert handshake["path"] == ["/chat"]
      assert handshake["host"] == ["localhost:8080"]
      assert handshake["upgrade"] == ["websocket"]
      assert handshake["connection"] == ["Upgrade"]
      assert handshake["sec-websocket-key"] == ["dGhlIHNhbXBsZSBub25jZQ=="]
      assert handshake["sec-websocket-version"] == ["13"]
    end

    test "parses with multiple upgrade header values" do
      request =
        "GET /chat HTTP/1.1\r\n" <>
          "Host: localhost:8080\r\n" <>
          "Upgrade: http/1.1, websocket\r\n" <>
          "Connection: Upgrade\r\n" <>
          "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n" <>
          "Sec-WebSocket-Version: 13\r\n" <>
          "\r\n"

      assert {:ok, handshake, ""} = Handshake.parse(request, <<>>)
      assert handshake["upgrade"] == ["http/1.1", "websocket"]
    end

    test "parses with multiple connection header values" do
      request =
        "GET /chat HTTP/1.1\r\n" <>
          "Host: localhost:8080\r\n" <>
          "Upgrade: websocket\r\n" <>
          "Connection: keep-alive, Upgrade\r\n" <>
          "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n" <>
          "Sec-WebSocket-Version: 13\r\n" <>
          "\r\n"

      assert {:ok, handshake, ""} = Handshake.parse(request, <<>>)
      assert handshake["connection"] == ["keep-alive", "Upgrade"]
    end

    test "returns :more for incomplete request line" do
      incomplete = "GET /chat"
      assert {:more, _} = Handshake.parse(incomplete, <<>>)
    end

    test "returns :more for incomplete headers" do
      incomplete =
        "GET /chat HTTP/1.1\r\n" <>
          "Host: localhost:8080\r\n" <>
          "Upgrade: websocket\r\n"

      assert {:more, _} = Handshake.parse(incomplete, <<>>)
    end

    test "returns :more for request without final CRLF" do
      incomplete =
        "GET /chat HTTP/1.1\r\n" <>
          "Host: localhost:8080\r\n" <>
          "Upgrade: websocket\r\n" <>
          "Connection: Upgrade\r\n" <>
          "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n" <>
          "Sec-WebSocket-Version: 13"

      assert {:more, _} = Handshake.parse(incomplete, <<>>)
    end

    test "returns :more for partial data with existing buffer" do
      buffer = "GET /chat HTTP/1.1\r\n"
      new_data = "Host: localhost:8080\r\nUpgrade: websocket\r\n"
      assert {:more, _} = Handshake.parse(new_data, buffer)
    end

    test "returns error for non-GET method" do
      request =
        "POST /chat HTTP/1.1\r\n" <>
          "\r\n"

      assert {:error, :invalid_method} = Handshake.parse(request, <<>>)
    end

    test "returns error for invalid path (no leading slash)" do
      request =
        "GET chat HTTP/1.1\r\n" <>
          "\r\n"

      assert {:error, :invalid_path} = Handshake.parse(request, <<>>)
    end

    test "returns error for invalid HTTP version" do
      request =
        "GET /chat HTTP/1.0\r\n" <>
          "\r\n"

      assert {:error, :invalid_http_version} = Handshake.parse(request, <<>>)
    end

    test "returns error for malformed header" do
      request =
        "GET /chat HTTP/1.1\r\n" <>
          "InvalidHeader\r\n" <>
          "\r\n"

      assert {:error, :invalid_header_syntax} = Handshake.parse(request, <<>>)
    end

    test "parses complex path" do
      request =
        "GET /ws/chat?room=general HTTP/1.1\r\n" <>
          "Host: localhost:8080\r\n" <>
          "Upgrade: websocket\r\n" <>
          "Connection: Upgrade\r\n" <>
          "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n" <>
          "Sec-WebSocket-Version: 13\r\n" <>
          "\r\n"

      assert {:ok, handshake, ""} = Handshake.parse(request, <<>>)
      assert handshake["path"] == ["/ws/chat?room=general"]
    end

    test "parses with additional headers" do
      request =
        "GET /chat HTTP/1.1\r\n" <>
          "Host: localhost:8080\r\n" <>
          "Upgrade: websocket\r\n" <>
          "Connection: Upgrade\r\n" <>
          "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n" <>
          "Sec-WebSocket-Version: 13\r\n" <>
          "Origin: http://localhost:3000\r\n" <>
          "Sec-WebSocket-Protocol: chat, superchat\r\n" <>
          "\r\n"

      assert {:ok, handshake, ""} = Handshake.parse(request, <<>>)
      assert handshake["origin"] == ["http://localhost:3000"]
      assert handshake["sec-websocket-protocol"] == ["chat", "superchat"]
    end
  end

  describe "accept_response/1" do
    test "accepts valid handshake" do
      handshake = %{
        "path" => ["/chat"],
        "upgrade" => ["websocket"],
        "connection" => ["Upgrade"],
        "sec-websocket-key" => ["dGhlIHNhbXBsZSBub25jZQ=="],
        "sec-websocket-version" => ["13"]
      }

      assert {:ok, response} = Handshake.accept_response(handshake)
      assert response =~ "HTTP/1.1 101 Switching Protocols"
      assert response =~ "Upgrade: websocket"
      assert response =~ "Connection: Upgrade"
      assert response =~ "Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo="
      assert response =~ "\r\n\r\n"
    end

    test "accepts handshake with multiple upgrade values" do
      handshake = %{
        "path" => ["/chat"],
        "upgrade" => ["http/1.1", "websocket"],
        "connection" => ["Upgrade"],
        "sec-websocket-key" => ["dGhlIHNhbXBsZSBub25jZQ=="],
        "sec-websocket-version" => ["13"]
      }

      assert {:ok, response} = Handshake.accept_response(handshake)
      assert response =~ "HTTP/1.1 101 Switching Protocols"
    end

    test "accepts handshake with multiple connection values" do
      handshake = %{
        "path" => ["/chat"],
        "upgrade" => ["websocket"],
        "connection" => ["keep-alive", "Upgrade"],
        "sec-websocket-key" => ["dGhlIHNhbXBsZSBub25jZQ=="],
        "sec-websocket-version" => ["13"]
      }

      assert {:ok, response} = Handshake.accept_response(handshake)
      assert response =~ "HTTP/1.1 101 Switching Protocols"
    end

    test "rejects missing upgrade header" do
      handshake = %{
        "path" => ["/chat"],
        "connection" => ["Upgrade"],
        "sec-websocket-key" => ["dGhlIHNhbXBsZSBub25jZQ=="],
        "sec-websocket-version" => ["13"]
      }

      assert {:error, :invalid_header_not_enough, response} = Handshake.accept_response(handshake)
      assert response =~ "HTTP/1.1 400 Bad Request"
    end

    test "rejects invalid upgrade header value" do
      handshake = %{
        "path" => ["/chat"],
        "upgrade" => ["not-websocket"],
        "connection" => ["Upgrade"],
        "sec-websocket-key" => ["dGhlIHNhbXBsZSBub25jZQ=="],
        "sec-websocket-version" => ["13"]
      }

      assert {:error, :invalid_header_upgrade, response} = Handshake.accept_response(handshake)
      assert response =~ "HTTP/1.1 400 Bad Request"
    end

    test "rejects missing connection header" do
      handshake = %{
        "path" => ["/chat"],
        "upgrade" => ["websocket"],
        "sec-websocket-key" => ["dGhlIHNhbXBsZSBub25jZQ=="],
        "sec-websocket-version" => ["13"]
      }

      assert {:error, :invalid_header_not_enough, response} = Handshake.accept_response(handshake)
      assert response =~ "HTTP/1.1 400 Bad Request"
    end

    test "rejects invalid connection header value" do
      handshake = %{
        "path" => ["/chat"],
        "upgrade" => ["websocket"],
        "connection" => ["keep-alive"],
        "sec-websocket-key" => ["dGhlIHNhbXBsZSBub25jZQ=="],
        "sec-websocket-version" => ["13"]
      }

      assert {:error, :invalid_header_connection, response} = Handshake.accept_response(handshake)
      assert response =~ "HTTP/1.1 400 Bad Request"
    end

    test "rejects missing sec-websocket-key" do
      handshake = %{
        "path" => ["/chat"],
        "upgrade" => ["websocket"],
        "connection" => ["Upgrade"],
        "sec-websocket-version" => ["13"]
      }

      assert {:error, :invalid_header_not_enough, response} = Handshake.accept_response(handshake)
      assert response =~ "HTTP/1.1 400 Bad Request"
    end

    test "rejects missing sec-websocket-version" do
      handshake = %{
        "path" => ["/chat"],
        "upgrade" => ["websocket"],
        "connection" => ["Upgrade"],
        "sec-websocket-key" => ["dGhlIHNhbXBsZSBub25jZQ=="]
      }

      assert {:error, :invalid_header_not_enough, response} = Handshake.accept_response(handshake)
      assert response =~ "HTTP/1.1 400 Bad Request"
    end

    test "rejects invalid sec-websocket-version" do
      handshake = %{
        "path" => ["/chat"],
        "upgrade" => ["websocket"],
        "connection" => ["Upgrade"],
        "sec-websocket-key" => ["dGhlIHNhbXBsZSBub25jZQ=="],
        "sec-websocket-version" => ["8"]
      }

      assert {:error, :invalid_header_sec_ws_version, response} =
               Handshake.accept_response(handshake)

      assert response =~ "HTTP/1.1 400 Bad Request"
    end
  end

  describe "reject/1" do
    test "rejects invalid path with 404" do
      assert {:error, :invalid_path, response} = Handshake.reject(:invalid_path)
      assert response =~ "HTTP/1.1 404 Not Found"
    end

    test "rejects other errors with 400" do
      assert {:error, :invalid_method, response} = Handshake.reject(:invalid_method)
      assert response =~ "HTTP/1.1 400 Bad Request"
    end
  end
end
