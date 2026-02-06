defmodule WebSocket.Frame do
  use Bitwise
  @fin_bit 128
  @opcode_bit 15
  @reserved_bit 112

  defstruct fin?: false, opcode: :ping, masked: false, len: 0, masking_key: nil, data: <<>>

  def parse(data, buff) do
    new_buffer = buff <> data
  end

  defp parse_single_frame(input, frames \\ []) do
    <<first_byte, rest::binary>> = input
    fin? = first_byte &&& @fin_bit
    opcode = first_byte &&& @opcode_bit
    reserved = first_byte &&& @reserved_bit
  end
end
