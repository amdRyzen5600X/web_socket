defmodule WebSocketTest do
  use ExUnit.Case
  doctest WebSocket

  describe "integration tests" do
    test "handshake followed by text frame exchange" do
      handshake =
        "GET /chat HTTP/1.1\r\n" <>
          "Host: localhost:8080\r\n" <>
          "Upgrade: websocket\r\n" <>
          "Connection: Upgrade\r\n" <>
          "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n" <>
          "Sec-WebSocket-Version: 13\r\n" <>
          "\r\n"

      assert {:ok, handshake_data, ""} = WebSocket.Handshake.parse(handshake, <<>>)
      assert {:ok, response} = WebSocket.Handshake.accept_response(handshake_data)
      assert response =~ "HTTP/1.1 101 Switching Protocols"
    end

    test "encoding and decoding a ping-pong exchange" do
      ping_data = "Are you there?"

      ping_frame = WebSocket.Frame.encode(:ping, ping_data)
      {:ok, [parsed_ping], ""} = WebSocket.Frame.parse(ping_frame, <<>>)

      assert parsed_ping.opcode == :ping
      assert parsed_ping.data == ping_data

      pong_frame = WebSocket.Frame.encode(:pong, ping_data)
      {:ok, [parsed_pong], ""} = WebSocket.Frame.parse(pong_frame, <<>>)

      assert parsed_pong.opcode == :pong
      assert parsed_pong.data == ping_data
    end

    test "encoding and decoding a close handshake" do
      close_code = 1000
      close_reason = "Normal closure"

      close_frame = WebSocket.Frame.encode(:close, {close_code, close_reason})
      {:ok, [parsed_close], ""} = WebSocket.Frame.parse(close_frame, <<>>)

      assert parsed_close.opcode == :close
      assert parsed_close.code == close_code
      assert parsed_close.data == close_reason
    end

    test "multiple frames in sequence" do
      frame1 = WebSocket.Frame.encode(:text, "Hello")
      frame2 = WebSocket.Frame.encode(:text, "World")

      combined = frame1 <> frame2
      {:ok, frames, ""} = WebSocket.Frame.parse(combined, <<>>)

      assert length(frames) == 2
      assert Enum.at(frames, 0).data == "Hello"
      assert Enum.at(frames, 1).data == "World"
    end

    test "large payload handling" do
      large_payload = :binary.copy(<<"x">>, 50000)

      encoded = WebSocket.Frame.encode(:binary, large_payload)
      {:ok, [parsed], ""} = WebSocket.Frame.parse(encoded, <<>>)

      assert parsed.opcode == :binary
      assert parsed.len == 50000
      assert parsed.data == large_payload
    end

    test "masked frame from client perspective" do
      payload = "Client message"
      masking_key = [0x12, 0x34, 0x56, 0x78]

      masked_payload =
        payload
        |> :binary.bin_to_list()
        |> Enum.with_index()
        |> Enum.map(fn {byte, index} ->
          mask_byte = Enum.at(masking_key, rem(index, 4))
          Bitwise.bxor(byte, mask_byte)
        end)
        |> :binary.list_to_bin()

      frame =
        <<0x81::8, 0x8E::8>> <> :binary.list_to_bin(masking_key) <> masked_payload

      {:ok, [parsed], ""} = WebSocket.Frame.parse(frame, <<>>)

      assert parsed.opcode == :text
      assert parsed.masked == true
      assert parsed.masking_key == masking_key
      assert parsed.data == payload
    end
  end
end
