defmodule WebSocket.FrameTest do
  use ExUnit.Case
  doctest WebSocket.Frame

  alias WebSocket.Frame

  describe "parse/2" do
    test "parses unmasked text frame" do
      frame = <<0x81::8, 0x05::8, "Hello">>

      assert {:ok, frames, ""} = Frame.parse(frame, <<>>)
      assert length(frames) == 1

      [f] = frames
      assert f.fin? == true
      assert f.opcode == :text
      assert f.masked == false
      assert f.len == 5
      assert f.data == "Hello"
    end

    test "parses unmasked binary frame" do
      data = <<1, 2, 3, 4, 5>>
      frame = <<0x82::8, 0x05::8, data::binary>>

      assert {:ok, frames, ""} = Frame.parse(frame, <<>>)
      assert length(frames) == 1

      [f] = frames
      assert f.fin? == true
      assert f.opcode == :binary
      assert f.masked == false
      assert f.len == 5
      assert f.data == data
    end

    test "parses masked text frame (from client)" do
      masking_key = [0x37, 0xFA, 0x21, 0x3D]
      payload = "Hello"
      masked_payload = mask_payload(payload, masking_key)

      frame =
        <<0x81::8, 0x85::8>> <> :binary.list_to_bin(masking_key) <> masked_payload

      assert {:ok, frames, ""} = Frame.parse(frame, <<>>)
      assert length(frames) == 1

      [f] = frames
      assert f.fin? == true
      assert f.opcode == :text
      assert f.masked == true
      assert f.masking_key == masking_key
      assert f.data == "Hello"
    end

    test "parses ping frame" do
      frame = <<0x89::8, 0x05::8, "Ping!">>

      assert {:ok, frames, ""} = Frame.parse(frame, <<>>)
      assert length(frames) == 1

      [f] = frames
      assert f.opcode == :ping
      assert f.fin? == true
      assert f.data == "Ping!"
    end

    test "parses empty ping frame" do
      frame = <<0x89::8, 0x00::8>>

      assert {:ok, frames, ""} = Frame.parse(frame, <<>>)
      assert length(frames) == 1

      [f] = frames
      assert f.opcode == :ping
      assert f.fin? == true
      assert f.data == ""
    end

    test "parses pong frame" do
      frame = <<0x8A::8, 0x05::8, "Pong!">>

      assert {:ok, frames, ""} = Frame.parse(frame, <<>>)
      assert length(frames) == 1

      [f] = frames
      assert f.opcode == :pong
      assert f.fin? == true
      assert f.data == "Pong!"
    end

    test "parses close frame with code and reason" do
      frame = <<0x88::8, 0x08::8, 1000::16, "Normal">>

      assert {:ok, frames, ""} = Frame.parse(frame, <<>>)
      assert length(frames) == 1

      [f] = frames
      assert f.opcode == :close
      assert f.code == 1000
      assert f.data == "Normal"
    end

    test "parses close frame with only code" do
      frame = <<0x88::8, 0x02::8, 1000::16>>

      assert {:ok, frames, ""} = Frame.parse(frame, <<>>)
      assert length(frames) == 1

      [f] = frames
      assert f.opcode == :close
      assert f.code == 1000
      assert f.data == ""
    end

    test "parses close frame with no payload" do
      frame = <<0x88::8, 0x00::8>>

      assert {:ok, frames, ""} = Frame.parse(frame, <<>>)
      assert length(frames) == 1

      [f] = frames
      assert f.opcode == :close
      assert f.code == nil
      assert f.data == ""
    end

    test "parses frame with 16-bit extended payload length" do
      payload = :binary.copy(<<"x">>, 300)
      len = byte_size(payload)
      frame = <<0x82::8, 126::8, len::16, payload::binary>>

      assert {:ok, frames, ""} = Frame.parse(frame, <<>>)
      assert length(frames) == 1

      [f] = frames
      assert f.opcode == :binary
      assert f.len == 300
      assert f.data == payload
    end

    test "parses frame with 64-bit extended payload length" do
      payload = :binary.copy(<<"x">>, 70000)
      len = byte_size(payload)
      frame = <<0x82::8, 127::8, len::64, payload::binary>>

      assert {:ok, frames, ""} = Frame.parse(frame, <<>>)
      assert length(frames) == 1

      [f] = frames
      assert f.opcode == :binary
      assert f.len == 70000
      assert f.data == payload
    end

    test "parses masked frame with 16-bit extended payload length" do
      payload = :binary.copy(<<"x">>, 300)
      len = byte_size(payload)
      masking_key = [0x12, 0x34, 0x56, 0x78]
      masked_payload = mask_payload(payload, masking_key)

      frame =
        <<0x82::8, 0xFE::8, len::16>> <> :binary.list_to_bin(masking_key) <> masked_payload

      assert {:ok, frames, ""} = Frame.parse(frame, <<>>)
      assert length(frames) == 1

      [f] = frames
      assert f.opcode == :binary
      assert f.masked == true
      assert f.len == 300
      assert f.data == payload
    end

    test "parses multiple frames in sequence" do
      frame1 = <<0x81::8, 0x05::8, "Hello">>
      frame2 = <<0x81::8, 0x06::8, "World!">>

      combined = frame1 <> frame2

      assert {:ok, frames, ""} = Frame.parse(combined, <<>>)
      assert length(frames) == 2

      [f1, f2] = frames
      assert f1.data == "Hello"
      assert f2.data == "World!"
    end

    test "returns :more for incomplete frame header" do
      incomplete = <<0x81::8>>

      assert {:more, buffer} = Frame.parse(incomplete, <<>>)
      assert buffer == incomplete
    end

    test "returns :more for incomplete extended payload length (16-bit)" do
      incomplete = <<0x82::8, 126::8, 0x01::8>>

      assert {:more, _} = Frame.parse(incomplete, <<>>)
    end

    test "returns :more for incomplete extended payload length (64-bit)" do
      incomplete = <<0x82::8, 127::8, 0x01::8, 0x00::8, 0x00::8, 0x00::8>>

      assert {:more, _} = Frame.parse(incomplete, <<>>)
    end

    test "returns :more for incomplete masking key" do
      incomplete = <<0x82::8, 0x80::8, 0x05::8, 0x01::8>>

      assert {:more, _} = Frame.parse(incomplete, <<>>)
    end

    test "returns :more for incomplete payload" do
      incomplete = <<0x82::8, 0x05::8, "Hel">>

      assert {:more, _} = Frame.parse(incomplete, <<>>)
    end

    test "returns :more for partial frame with buffer" do
      buffer = <<0x82::8>>
      new_data = <<0x05::8, "Hel">>

      assert {:more, _} = Frame.parse(new_data, buffer)
    end

    test "returns :more when incomplete data arrives in multiple chunks" do
      buffer = <<0x82::8, 0x05::8, "Hel">>
      new_data = "lo"

      assert {:ok, frames, ""} = Frame.parse(new_data, buffer)
      assert length(frames) == 1
      assert hd(frames).data == "Hello"
    end

    test "returns error for invalid opcode" do
      frame = <<0x83::8, 0x00::8>>

      assert {:error, :invalid_opcode} = Frame.parse(frame, <<>>)
    end

    test "returns error for reserved bits set" do
      frame = <<0x9F::8, 0x00::8>>

      assert {:error, :use_of_reserved} = Frame.parse(frame, <<>>)
    end

    test "parses frame and returns remaining data" do
      frame = <<0x81::8, 0x05::8, "Hello">>
      extra = "extra data"

      combined = frame <> extra

      assert {:ok, frames, ^extra} = Frame.parse(combined, <<>>)
      assert length(frames) == 1
    end

    test "parses continuation frame" do
      frame = <<0x80::8, 0x05::8, "World">>

      assert {:ok, frames, ""} = Frame.parse(frame, <<>>)
      assert length(frames) == 1

      [f] = frames
      assert f.fin? == true
      assert f.opcode == :continuation
      assert f.data == "World"
    end

    test "parses FIN=0 continuation frame (non-final fragment)" do
      frame = <<0x00::8, 0x05::8, "Hello">>

      assert {:ok, frames, ""} = Frame.parse(frame, <<>>)
      assert length(frames) == 1

      [f] = frames
      assert f.fin? == false
      assert f.opcode == :continuation
    end

    test "parses initial text frame with FIN=0" do
      frame = <<0x01::8, 0x05::8, "Hello">>

      assert {:ok, frames, ""} = Frame.parse(frame, <<>>)
      assert length(frames) == 1

      [f] = frames
      assert f.fin? == false
      assert f.opcode == :text
      assert f.data == "Hello"
    end
  end

  describe "encode/2" do
    test "encodes text frame" do
      assert <<0x81::8, 0x05::8, "Hello">> = Frame.encode(:text, "Hello")
    end

    test "encodes binary frame" do
      data = <<1, 2, 3, 4, 5>>
      assert <<0x82::8, 0x05::8, ^data::binary>> = Frame.encode(:binary, data)
    end

    test "encodes ping frame" do
      assert <<0x89::8, 0x05::8, "Ping!">> = Frame.encode(:ping, "Ping!")
    end

    test "encodes empty ping frame" do
      assert <<0x89::8, 0x00::8>> = Frame.encode(:ping, "")
    end

    test "encodes pong frame" do
      assert <<0x8A::8, 0x05::8, "Pong!">> = Frame.encode(:pong, "Pong!")
    end

    test "encodes close frame with code and reason" do
      encoded = Frame.encode(:close, {1000, "Normal"})

      assert <<0x88::8, 0x08::8, 1000::16, "Normal">> = encoded
    end

    test "encodes close frame with code only" do
      encoded = Frame.encode(:close, {1000, ""})

      assert <<0x88::8, 0x02::8, 1000::16>> = encoded
    end

    test "encodes text frame with 16-bit extended length" do
      payload = :binary.copy(<<"x">>, 300)

      encoded = Frame.encode(:text, payload)

      assert <<0x81::8, 126::8, 300::16, _::binary>> = encoded
      assert byte_size(encoded) == 2 + 2 + 300
    end

    test "encodes binary frame with 16-bit extended length" do
      payload = :binary.copy(<<"y">>, 50000)

      encoded = Frame.encode(:binary, payload)

      assert <<0x82::8, 126::8, 50000::16, _::binary>> = encoded
      assert byte_size(encoded) == 2 + 2 + 50000
    end

    test "encodes text frame with 64-bit extended length" do
      payload = :binary.copy(<<"z">>, 70000)

      encoded = Frame.encode(:text, payload)

      assert <<0x81::8, 127::8, 70000::64, _::binary>> = encoded
      assert byte_size(encoded) == 2 + 8 + 70000
    end

    test "encodes continuation frame" do
      assert <<0x80::8, 0x05::8, "Hello">> = Frame.encode(:continuation, "Hello")
    end

    test "encodes close frame with different codes" do
      assert <<0x88::8, 0x02::8, 1000::16>> = Frame.encode(:close, {1000, ""})
      assert <<0x88::8, 0x02::8, 1001::16>> = Frame.encode(:close, {1001, ""})
      assert <<0x88::8, 0x02::8, 1002::16>> = Frame.encode(:close, {1002, ""})
      assert <<0x88::8, 0x03::8, 1003::16, "x">> = Frame.encode(:close, {1003, "x"})
    end
  end

  describe "roundtrip encoding/decoding" do
    test "roundtrip text frame" do
      original = "Hello, WebSocket!"

      encoded = Frame.encode(:text, original)
      {:ok, frames, ""} = Frame.parse(encoded, <<>>)

      assert length(frames) == 1
      assert hd(frames).data == original
    end

    test "roundtrip binary frame" do
      original = <<1, 2, 3, 4, 5, 6, 7, 8>>

      encoded = Frame.encode(:binary, original)
      {:ok, frames, ""} = Frame.parse(encoded, <<>>)

      assert length(frames) == 1
      assert hd(frames).data == original
    end

    test "roundtrip ping frame" do
      original = "Keepalive"

      encoded = Frame.encode(:ping, original)
      {:ok, frames, ""} = Frame.parse(encoded, <<>>)

      assert length(frames) == 1
      assert hd(frames).data == original
    end

    test "roundtrip pong frame" do
      original = "Pong response"

      encoded = Frame.encode(:pong, original)
      {:ok, frames, ""} = Frame.parse(encoded, <<>>)

      assert length(frames) == 1
      assert hd(frames).data == original
    end

    test "roundtrip close frame" do
      original_code = 1000
      original_reason = "Normal closure"

      encoded = Frame.encode(:close, {original_code, original_reason})
      {:ok, frames, ""} = Frame.parse(encoded, <<>>)

      assert length(frames) == 1
      assert hd(frames).code == original_code
      assert hd(frames).data == original_reason
    end

    test "roundtrip large payload" do
      original = :binary.copy(<<"Large payload ">>, 1000)

      encoded = Frame.encode(:text, original)
      {:ok, frames, ""} = Frame.parse(encoded, <<>>)

      assert length(frames) == 1
      assert hd(frames).data == original
    end
  end

  describe "fragmentation - THESE TESTS SHOULD FAIL" do
    test "parses fragmented text message (3 fragments)" do
      fragment1 = <<0x01::8, 0x05::8, "Hello">>
      fragment2 = <<0x00::8, 0x01::8, " ">>
      fragment3 = <<0x80::8, 0x06::8, "World!">>

      combined = fragment1 <> fragment2 <> fragment3

      assert {:ok, frames, ""} = Frame.parse(combined, <<>>)

      assert length(frames) == 3
      assert hd(frames).opcode == :text
      assert Enum.at(frames, 1).opcode == :continuation
      assert List.last(frames).opcode == :continuation

      assert List.last(frames).fin? == true
    end

    test "parses fragmented binary message (2 fragments)" do
      fragment1 = <<0x02::8, 0x03::8, <<1, 2, 3>>::binary>>
      fragment2 = <<0x80::8, 0x03::8, <<4, 5, 6>>::binary>>

      combined = fragment1 <> fragment2

      assert {:ok, frames, ""} = Frame.parse(combined, <<>>)

      assert length(frames) == 2
      assert hd(frames).opcode == :binary
      assert List.last(frames).fin? == true
    end

    test "parses fragmented message with incomplete data" do
      fragment1 = <<0x01::8, 0x05::8, "Hello">>
      fragment2 = <<0x80::8, 0x06::8, "World!">>

      combined = fragment1 <> fragment2

      {:ok, frames, ""} = Frame.parse(combined, <<>>)

      assert length(frames) == 2

      f1 = Enum.at(frames, 0)
      f2 = Enum.at(frames, 1)

      assert f1.opcode == :text
      assert f1.fin? == false
      assert f1.data == "Hello"

      assert f2.opcode == :continuation
      assert f2.fin? == true
      assert f2.data == "World!"
    end

    test "NOTE: Current implementation returns individual frames, not reassembled message" do
      fragment1 = <<0x01::8, 0x05::8, "Part1">>
      fragment2 = <<0x80::8, 0x05::8, "Part2">>

      combined = fragment1 <> fragment2

      {:ok, frames, ""} = Frame.parse(combined, <<>>)

      assert length(frames) == 2

      assert hd(frames).data == "Part1"
      assert List.last(frames).data == "Part2"

      assert hd(frames).fin? == false
      assert List.last(frames).fin? == true
    end
  end

  describe "edge cases" do
    test "handles maximum 16-bit payload length" do
      payload = :binary.copy(<<"x">>, 65535)

      encoded = Frame.encode(:binary, payload)
      {:ok, frames, ""} = Frame.parse(encoded, <<>>)

      assert length(frames) == 1
      assert hd(frames).len == 65535
      assert hd(frames).data == payload
    end

    test "handles payload one byte over 16-bit limit" do
      payload = :binary.copy(<<"y">>, 65536)

      encoded = Frame.encode(:binary, payload)
      {:ok, frames, ""} = Frame.parse(encoded, <<>>)

      assert length(frames) == 1
      assert hd(frames).len == 65536
    end

    test "handles empty payload" do
      assert {:ok, frames, ""} = Frame.parse(<<0x81::8, 0x00::8>>, <<>>)
      assert length(frames) == 1
      assert hd(frames).data == ""
    end

    test "handles single byte payload" do
      assert {:ok, frames, ""} = Frame.parse(<<0x81::8, 0x01::8, "a">>, <<>>)
      assert length(frames) == 1
      assert hd(frames).data == "a"
    end

    test "handles maximum small payload (125 bytes)" do
      payload = :binary.copy(<<"z">>, 125)

      encoded = Frame.encode(:text, payload)
      {:ok, frames, ""} = Frame.parse(encoded, <<>>)

      assert length(frames) == 1
      assert hd(frames).len == 125
    end
  end

  defp mask_payload(payload, masking_key) do
    payload
    |> :binary.bin_to_list()
    |> Enum.with_index()
    |> Enum.map(fn {byte, index} ->
      mask_byte = Enum.at(masking_key, rem(index, 4))
      Bitwise.bxor(byte, mask_byte)
    end)
    |> :binary.list_to_bin()
  end
end
