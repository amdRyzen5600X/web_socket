defmodule WebSocket.Frame do
  alias WebSocket.Frame

  @frame_max_size 2 ** 64

  @opcode_variants [0, 1, 2, 8, 9, 10]

  @opcode_variants_atoms [
    :continuation,
    :text,
    :binary,
    :close,
    :ping,
    :pong
  ]

  @opcode %{
    0 => :continuation,
    1 => :text,
    2 => :binary,
    8 => :close,
    9 => :ping,
    10 => :pong
  }

  defstruct fin?: false,
            opcode: :ping,
            code: nil,
            masked: false,
            len: 0,
            masking_key: nil,
            data: <<>>

  def parse(data, buffer) do
    parse_frame(buffer <> data)
  end

  defp parse_frame(input, frames \\ [])

  defp parse_frame(input, frames) when byte_size(input) >= 2 do
    case do_parse_frame(input, frames) do
      {:incomplete, _} -> {:more, input}
      {:error, _} when frames != [] -> {:ok, Enum.reverse(frames), input}
      {:error, reason} -> {:error, reason}
      result -> result
    end
  end

  defp parse_frame(input, frames) when frames != [] do
    {:ok, Enum.reverse(frames), input}
  end

  defp parse_frame(input, _) do
    {:more, input}
  end

  defp do_parse_frame(
         <<fin::1, reserved::3, opcode::4, mask?::1, payload_len::7, rest::binary>>,
         frames
       )
       when reserved == 0 and opcode in @opcode_variants do
    case read_payload_len(payload_len, rest) do
      {:ok, len, rest} ->
        case read_masking_key(mask?, rest) do
          {:ok, masking_key, rest} ->
            required_bytes = len

            if byte_size(rest) < required_bytes do
              {:incomplete, nil}
            else
              <<payload::binary-size(len), rest::binary>> = rest
              unmasked_payload = unmask_payload(payload, masking_key)
              opcode = Map.get(@opcode, opcode, opcode)

              {code, unmasked_payload} =
                case opcode do
                  :close when byte_size(unmasked_payload) >= 2 ->
                    <<code::16, unmasked_payload::binary>> = unmasked_payload
                    {code, unmasked_payload}

                  :close ->
                    {nil, unmasked_payload}

                  _ ->
                    {nil, unmasked_payload}
                end

              frame = %Frame{
                fin?: fin == 1,
                opcode: opcode,
                masked: mask? == 1,
                len: len,
                code: code,
                masking_key: masking_key,
                data: unmasked_payload
              }

              frames = [frame | frames]

              parse_frame(rest, frames)
            end

          :incomplete ->
            {:incomplete, nil}
        end

      :incomplete ->
        {:incomplete, nil}
    end
  end

  defp do_parse_frame(
         <<_::1, reserved::3, opcode::4, _::binary>>,
         _
       )
       when reserved == 0 and opcode not in @opcode_variants do
    {:error, :invalid_opcode}
  end

  defp do_parse_frame(input, _) do
    {:error, :use_of_reserved}
  end

  defp read_payload_len(126, <<len::16, rest::binary>>), do: {:ok, len, rest}
  defp read_payload_len(127, <<len::64, rest::binary>>), do: {:ok, len, rest}
  defp read_payload_len(len, rest) when len <= 125, do: {:ok, len, rest}
  defp read_payload_len(_, _), do: :incomplete

  defp read_masking_key(1, <<k1, k2, k3, k4, rest::binary>>), do: {:ok, [k1, k2, k3, k4], rest}
  defp read_masking_key(0, rest), do: {:ok, nil, rest}
  defp read_masking_key(_, _), do: :incomplete

  defp unmask_payload(<<>>, _masking_key), do: <<>>
  defp unmask_payload(payload, nil), do: payload

  defp unmask_payload(payload, masking_key) do
    unmask_binary(payload, masking_key, 0, [])
  end

  defp unmask_binary(<<byte, rest::binary>>, masking_key, index, acc) do
    mask_byte = Enum.at(masking_key, rem(index, 4))
    unmask_binary(rest, masking_key, index + 1, [Bitwise.bxor(byte, mask_byte) | acc])
  end

  defp unmask_binary(<<>>, _, _, acc) do
    :erlang.iolist_to_binary(Enum.reverse(acc))
  end

  def encode(:close = opcode, {code, payload}) when byte_size(payload) <= 125 - 2 do
    [encode_header(opcode), <<byte_size(payload) + 2::7, code::16, payload::binary>>]
    |> :erlang.list_to_bitstring()
  end

  def encode(opcode, payload)
      when byte_size(payload) <= 125 and opcode in @opcode_variants_atoms do
    [encode_header(opcode), <<byte_size(payload)::7, payload::binary>>]
    |> :erlang.list_to_bitstring()
  end

  def encode(:close = opcode, {code, payload}) when byte_size(payload) <= 65535 - 2 do
    [encode_header(opcode), <<126::7, byte_size(payload) + 2::16, code::16, payload::binary>>]
    |> :erlang.list_to_bitstring()
  end

  def encode(opcode, payload)
      when byte_size(payload) <= 65535 and opcode in @opcode_variants_atoms do
    [encode_header(opcode), <<126::7, byte_size(payload)::16, payload::binary>>]
    |> :erlang.list_to_bitstring()
  end

  def encode(:close = opcode, {code, payload}) when byte_size(payload) <= @frame_max_size - 3 do
    [encode_header(opcode), <<127::7, byte_size(payload) + 2::64, code::16, payload::binary>>]
    |> :erlang.list_to_bitstring()
  end

  def encode(opcode, payload)
      when byte_size(payload) <= @frame_max_size - 1 and opcode in @opcode_variants_atoms do
    [encode_header(opcode), <<127::7, byte_size(payload)::64, payload::binary>>]
    |> :erlang.list_to_bitstring()
  end

  defp encode_header(:pong) do
    <<1::1, 0::3, 10::4, 0::1>>
  end

  defp encode_header(:ping) do
    <<1::1, 0::3, 9::4, 0::1>>
  end

  defp encode_header(:close) do
    <<1::1, 0::3, 8::4, 0::1>>
  end

  defp encode_header(:binary) do
    <<1::1, 0::3, 2::4, 0::1>>
  end

  defp encode_header(:text) do
    <<1::1, 0::3, 1::4, 0::1>>
  end

  defp encode_header(:continuation) do
    <<1::1, 0::3, 0::4, 0::1>>
  end
end
