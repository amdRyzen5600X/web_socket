defmodule WebSocket do
  @moduledoc """
  Documentation for `WebSocket`.
  """

  @doc """
  Hello world.

  ## Examples

      iex> WebSocket.hello()
      :world

  """
  def hello do
    :world
    hi()
  end

  def hi do
    pu()
    :world
  end

  defp pu do
    :pupu
  end
end

