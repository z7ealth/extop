defmodule Extop.MixProject do
  use Mix.Project

  def project do
    [
      app: :extop,
      version: "0.1.0",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      releases: releases()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Extop.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ex_ratatui, "~> 0.11"}
    ]
  end

  defp aliases do
    [
      run: "run --no-halt",
      test: "test --no-start"
    ]
  end

  defp releases do
    [
      extop: [
        include_executables_for: [:unix],
        steps: [:assemble, &default_start_command/1]
      ]
    ]
  end

  defp default_start_command(%Mix.Release{path: path} = release) do
    bin = Path.join(path, "bin/extop")

    patched =
      bin
      |> File.read!()
      |> String.replace(
        "case $1 in",
        """
        if [ -z "$1" ]; then
          set -- start
        fi

        case $1 in
        """,
        global: false
      )

    File.write!(bin, patched)
    File.chmod!(bin, 0o755)
    release
  end
end
