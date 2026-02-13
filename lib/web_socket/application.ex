defmodule WebSocket.Application do
  use Application

  def start(_start_type, _opts) do
    children = [
      {Task.Supervisor, name: WebSocket.TaskSupervisor}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
