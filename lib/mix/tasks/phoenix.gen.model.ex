defmodule Mix.Tasks.Phoenix.Gen.Model do
  use Mix.Task

  @shortdoc "Generates an Ecto model"

  @moduledoc """
  Generates an Ecto model in your Phoenix application.

      mix phoenix.gen.model User users name:string age:integer

  The first argument is the module name followed by its plural
  name (used for the schema).

  The generated model will contain:

    * a model in web/models
    * a migration file for the repository

  The generated migration can be skipped with `--no-migration`.

  ## Attributes

  The resource fields are given using `name:type` syntax
  where type are the types supported by Ecto. Ommitting
  the type makes it default to `:string`:

      mix phoenix.gen.model User users name age:integer

  The generator also supports `belongs_to` associations
  via references:

      mix phoenix.gen.model Post posts title user_id:references:users

  This will result in a migration with an `:integer` column
  of `:user_id` and create an index. It will also generate
  the appropriate `belongs_to` entry in the model's schema.

  Furthermore an array type can also be given if it is
  supported by your database, although it requires the
  type of the underlying array element to be given too:

      mix phoenix.gen.model User users nicknames:array:string

  ## Namespaced resources

  Resources can be namespaced, for such, it is just necessary
  to namespace the first argument of the generator:

      mix phoenix.gen.model Admin.User users name:string age:integer

  ## binary_id

  Generated migration can use `binary_id` for model's primary key and it's
  references with option `--binary-id`.

  This option assumes the project was generated with the `--binary-id` option,
  that sets up models to use `binary_id` by default. If that's not the case
  you can still set all your models to use `binary_id` by default, by adding
  following to your `model` function in `web/web.ex`option or by adding
  following to the generated model before the `schema` declaration:

      @primary_key {:id, :binary_id, autogenerate: true}
      @foreign_key_type :binary_id

  ## Default options

  This generator uses default options provided in the `:generators` configuration
  of the `:phoenix` application. You can override those options providing
  corresponding switches, e.g. `--no-binary-id` to use normal ids despite
  the default configuration or `--migration` to force generation of the migration.

  """
  def run(args) do
    switches = [migration: :boolean, binary_id: :boolean, instructions: :string]

    {opts, parsed, _} = OptionParser.parse(args, switches: switches)
    [singular, plural | attrs] = validate_args!(parsed)

    default_opts = Application.get_env(:phoenix, :generators, [])
    opts = Keyword.merge(default_opts, opts)

    attrs     = Mix.Phoenix.attrs(attrs)
    binding   = Mix.Phoenix.inflect(singular)
    params    = Mix.Phoenix.params(attrs)
    path      = binding[:path]
    migration = String.replace(path, "/", "_")

    Mix.Phoenix.check_module_name_availability!(binding[:module])

    {assocs, attrs} = partition_attrs_and_assocs(attrs)

    binding = binding ++
              [attrs: attrs, plural: plural, types: types(attrs),
               assocs: assocs(assocs), indexes: indexes(plural, assocs),
               defaults: defaults(attrs), params: params,
               binary_id: opts[:binary_id]]

    files = [
      {:eex, "model.ex",       "web/models/#{path}.ex"},
      {:eex, "model_test.exs", "test/models/#{path}_test.exs"},
    ]

    if opts[:migration] != false do
      files =
        [{:eex, "migration.exs", "priv/repo/migrations/#{timestamp()}_create_#{migration}.exs"}|files]
    end

    Mix.Phoenix.copy_from paths(), "priv/templates/phoenix.gen.model", "", binding, files

    # Print any extra instruction given by parent generators
    Mix.shell.info opts[:instructions] || ""

    if opts[:migration] != false do
      Mix.shell.info """
      Remeber to update your repository by running migrations:

          $ mix ecto.migrate
      """
    end
  end

  defp validate_args!([_, plural | _] = args) do
    if String.contains?(plural, ":") do
      raise_with_help
    else
      args
    end
  end

  defp validate_args!(_) do
    raise_with_help
  end

  defp raise_with_help do
    Mix.raise """
    mix phoenix.gen.model expects both singular and plural names
    of the generated resource followed by any number of attributes:

        mix phoenix.gen.model User users name:string
    """
  end

  defp partition_attrs_and_assocs(attrs) do
    Enum.partition attrs, fn
      {_, {:references, _}} ->
        true
      {key, :references} ->
        Mix.raise """
        Phoenix generators expect the table to be given to #{key}:references.
        For example:

            mix phoenix.gen.model Comment comments body:text post_id:references:posts
        """
      _ ->
        false
    end
  end

  defp assocs(assocs) do
    Enum.map assocs, fn {key_id, {:references, source}} ->
      key   = String.replace(Atom.to_string(key_id), "_id", "")
      assoc = Mix.Phoenix.inflect key
      {String.to_atom(key), key_id, assoc[:module], source}
    end
  end

  defp indexes(plural, assocs) do
    Enum.map assocs, fn {key, _} ->
      "create index(:#{plural}, [:#{key}])"
    end
  end

  defp timestamp do
    {{y, m, d}, {hh, mm, ss}} = :calendar.universal_time()
    "#{y}#{pad(m)}#{pad(d)}#{pad(hh)}#{pad(mm)}#{pad(ss)}"
  end

  defp pad(i) when i < 10, do: << ?0, ?0 + i >>
  defp pad(i), do: to_string(i)

  defp types(attrs) do
    Enum.into attrs, %{}, fn
      {k, {c, v}} -> {k, {c, value_to_type(v)}}
      {k, v}      -> {k, value_to_type(v)}
    end
  end

  defp defaults(attrs) do
    Enum.into attrs, %{}, fn
      {k, :boolean}  -> {k, ", default: false"}
      {k, _}         -> {k, ""}
    end
  end

  defp value_to_type(:text), do: :string
  defp value_to_type(:uuid), do: Ecto.UUID
  defp value_to_type(:date), do: Ecto.Date
  defp value_to_type(:time), do: Ecto.Time
  defp value_to_type(:datetime), do: Ecto.DateTime
  defp value_to_type(v) do
    if Code.ensure_loaded?(Ecto.Type) and not Ecto.Type.primitive?(v) do
      Mix.raise "Unknown type `#{v}` given to generator"
    else
      v
    end
  end

  defp paths do
    [".", :phoenix]
  end
end
