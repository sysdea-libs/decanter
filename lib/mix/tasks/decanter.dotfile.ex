defmodule Mix.Tasks.Decanter.Dotfile.R do
  use Decanter

  plug :serve

  def gen_dotfile do
    generate_dot_file(@nodes)
  end
end

defmodule Mix.Tasks.Decanter.Dotfile do
  use Mix.Task

  @shortdoc "Create the dotfile for the default decision tree"

  def run(_args) do
    IO.puts Mix.Tasks.Decanter.Dotfile.R.gen_dotfile
  end
end
