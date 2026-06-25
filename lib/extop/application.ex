defmodule Extop.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [Extop.TUI]
    opts = [strategy: :one_for_one, name: Extop.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
