defmodule WebSocket.MixProject do
  use Mix.Project

  def project do
    [
      app: :web_socket,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp docs do
    [
      name: "WebSocket",
      source_url: "https://github.com/yourusername/web_socket",
      homepage_url: "https://github.com/yourusername/web_socket",
      main: "WebSocket",
      extras: ["README.md"],
      groups_for_modules: [
        Core: [
          WebSocket,
          WebSocket.Listener,
          WebSocket.Connection
        ],
        Protocol: [
          WebSocket.Handshake,
          WebSocket.Frame
        ],
        Behaviours: [
          WebSocket.Handler
        ]
      ],
      groups_for_extras: [
        "Getting Started": ["guides/getting_started.md"],
        "Advanced Usage": ["guides/advanced_usage.md"]
      ]
    ]
  end
end
