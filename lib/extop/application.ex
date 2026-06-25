defmodule Extop.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      if Application.get_env(:extop, :start_tui, false), do: [Extop.TUI], else: []

    opts = [strategy: :one_for_one, name: Extop.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
