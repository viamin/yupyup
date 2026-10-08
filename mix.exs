defmodule YupYup.MixProject do
  use Mix.Project

  def project do
    [
      app: :yup_yup,
      version: "0.1.0",
      elixir: "~> 1.20",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      escript: [main_module: Yup.CLI, name: "yup"]
    ]
  end

  # Test-support modules (the OAuth event mapper) compile only under :test;
  # the escript and the library never see them.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    []
  end
end
