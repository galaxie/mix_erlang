defmodule Mix.Tasks.Ct do
  use Mix.Task

  @preferred_cli_env :test

  @options [
    suite: [:string, :keep],
    dir: [:string, :keep],
    sys_config: [:string, :keep],
    cover: :boolean
  ]

  @cover [tool: Mix.Tasks.Test.Cover, output: "cover"]

  def run(args) do
    {opts, _, _} = OptionParser.parse(args, strict: @options, aliases: [c: :cover])
    project = Mix.Project.config()

    unless System.get_env("MIX_ENV") || Mix.env() == :test do
      Mix.raise(
        "\"mix ct\" is running in the \"#{Mix.env()}\" environment. " <>
          "If you are running tests alongside another task, please set MIX_ENV"
      )
    end

    :ok = Mix.Erlang.load_configs(Keyword.get_values(opts, :sys_config))

    Mix.Task.run(:compile)
    Mix.Task.run(:loadpaths)

    options =
      project
      |> Keyword.get(:ct_options, [])
      |> Keyword.put(:auto_compile, false)
      |> Keyword.put_new(:dirs, ["test"])
      |> Keyword.put_new(:logdir, 'log/ct')
      |> set_args(:suite, opts)
      |> Keyword.update!(:dirs, &(&1 ++ Keyword.get_values(opts, :dir)))

    File.mkdir_p!(options[:logdir])

    {:ok, ebin} = compile_tests(options)

    cover =
      if opts[:cover] do
        compile_path = Mix.Project.compile_path(project)
        cover = Keyword.merge(@cover, project[:test_coverage] || [])
        cover[:tool].start(compile_path, cover)
      end

    case :ct.run_test(Keyword.put(options, :dir, [ebin])) do
      {_, 0, _} ->
        cover && cover.()
        :ok

      {_, n, _} when n > 0 ->
        Mix.raise("Common test suite failed")

      {:error, reason} ->
        Mix.raise("Failed to run common test with reason: #{inspect(reason, pretty: true)}")
    end
  end

  defp set_args(options, key, args), do: set_args(options, key, args, key)

  defp set_args(options, okey, args, akey) do
    case Keyword.get_values(args, akey) do
      [] -> options
      values when is_list(values) -> Keyword.put(options, okey, Enum.map(values, &to_charlist/1))
    end
  end

  defp compile_tests(options) do
    dirs = Keyword.fetch!(options, :dirs)

    ebin = Path.join(Mix.Project.app_path(), "common_test") |> to_charlist()

    erlc_opts = [:report, outdir: ebin] ++ Mix.Project.config()[:erlc_options]

    File.mkdir_p!(ebin)

    for path <- dirs,
        file <- Path.wildcard("#{path}/**/*_SUITE.erl") do
      {:ok, _} = :compile.file(String.to_charlist(file), erlc_opts)
    end

    {:ok, ebin}
  end
end
