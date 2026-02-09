defmodule WebSocket.Frame do
  alias WebSocket.Frame

  @opcode_variants [
    0,
    1,
    2,
    8,
    9,
    10
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
      result -> result
    end
  end

  defp parse_frame(_, frames) when frames != [] do
    {:ok, Enum.reverse(frames), <<>>}
  end

  defp parse_frame(_, _) do
    :more
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
                  :close ->
                    <<code::16, unmasked_payload::binary>> = unmasked_payload
                    {code, unmasked_payload}

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

              if fin == 0 do
                do_parse_frame(rest, frames)
              else
                {:ok, Enum.reverse(frames), rest}
              end
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

  defp do_parse_frame(_, _) do
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

  def encode(:pong, payload) when byte_size(payload) <= 125 do
    <<1::1, 0::3, 10::4, 0::1, byte_size(payload)::7, payload::binary>>
  end

  def encode(:close, {code, payload}) when byte_size(payload) <= 123 do
    <<1::1, 0::3, 8::4, 0::1, byte_size(payload) + 2::7, code::2, payload::binary>>
  end
end
