defmodule SymphonyElixir.Config.Schema do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias SymphonyElixir.PathSafety

  @primary_key false

  @type t :: %__MODULE__{}

  defmodule StringOrMap do
    @moduledoc false
    @behaviour Ecto.Type

    @spec type() :: :map
    def type, do: :map

    @spec embed_as(term()) :: :self
    def embed_as(_format), do: :self

    @spec equal?(term(), term()) :: boolean()
    def equal?(left, right), do: left == right

    @spec cast(term()) :: {:ok, String.t() | map()} | :error
    def cast(value) when is_binary(value) or is_map(value), do: {:ok, value}
    def cast(_value), do: :error

    @spec load(term()) :: {:ok, String.t() | map()} | :error
    def load(value) when is_binary(value) or is_map(value), do: {:ok, value}
    def load(_value), do: :error

    @spec dump(term()) :: {:ok, String.t() | map()} | :error
    def dump(value) when is_binary(value) or is_map(value), do: {:ok, value}
    def dump(_value), do: :error
  end

  defmodule Tracker do
    @moduledoc false
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key false

    embedded_schema do
      field(:kind, :string)
      field(:endpoint, :string, default: "https://api.linear.app/graphql")
      field(:api_key, :string)
      field(:project_slug, :string)
      field(:assignee, :string)
      field(:active_states, {:array, :string}, default: ["Todo", "In Progress"])
      field(:terminal_states, {:array, :string}, default: ["Closed", "Cancelled", "Canceled", "Duplicate", "Done"])
    end

    @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
    def changeset(schema, attrs) do
      schema
      |> cast(
        attrs,
        [:kind, :endpoint, :api_key, :project_slug, :assignee, :active_states, :terminal_states],
        empty_values: []
      )
    end
  end

  defmodule Polling do
    @moduledoc false
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key false
    embedded_schema do
      field(:interval_ms, :integer, default: 30_000)
    end

    @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
    def changeset(schema, attrs) do
      schema
      |> cast(attrs, [:interval_ms], empty_values: [])
      |> validate_number(:interval_ms, greater_than: 0)
    end
  end

  defmodule Workspace do
    @moduledoc false
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key false
    embedded_schema do
      field(:root, :string, default: Path.join(System.tmp_dir!(), "symphony_workspaces"))
    end

    @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
    def changeset(schema, attrs) do
      schema
      |> cast(attrs, [:root], empty_values: [])
    end
  end

  defmodule Worker do
    @moduledoc false
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key false
    embedded_schema do
      field(:ssh_hosts, {:array, :string}, default: [])
      field(:max_concurrent_agents_per_host, :integer)
    end

    @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
    def changeset(schema, attrs) do
      schema
      |> cast(attrs, [:ssh_hosts, :max_concurrent_agents_per_host], empty_values: [])
      |> validate_number(:max_concurrent_agents_per_host, greater_than: 0)
    end
  end

  defmodule Agent do
    @moduledoc false
    use Ecto.Schema
    import Ecto.Changeset

    alias SymphonyElixir.Config.Schema

    @primary_key false
    embedded_schema do
      field(:max_concurrent_agents, :integer, default: 10)
      field(:max_turns, :integer, default: 20)
      field(:max_retry_backoff_ms, :integer, default: 300_000)
      field(:max_concurrent_agents_by_state, :map, default: %{})
    end

    @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
    def changeset(schema, attrs) do
      schema
      |> cast(
        attrs,
        [:max_concurrent_agents, :max_turns, :max_retry_backoff_ms, :max_concurrent_agents_by_state],
        empty_values: []
      )
      |> validate_number(:max_concurrent_agents, greater_than: 0)
      |> validate_number(:max_turns, greater_than: 0)
      |> validate_number(:max_retry_backoff_ms, greater_than: 0)
      |> update_change(:max_concurrent_agents_by_state, &Schema.normalize_state_limits/1)
      |> Schema.validate_state_limits(:max_concurrent_agents_by_state)
    end
  end

  defmodule Codex do
    @moduledoc false
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key false
    embedded_schema do
      field(:command, :string, default: "codex app-server")

      field(:approval_policy, StringOrMap,
        default: %{
          "reject" => %{
            "sandbox_approval" => true,
            "rules" => true,
            "mcp_elicitations" => true
          }
        }
      )

      field(:thread_sandbox, :string, default: "workspace-write")
      field(:turn_sandbox_policy, :map)
      field(:turn_timeout_ms, :integer, default: 3_600_000)
      field(:read_timeout_ms, :integer, default: 5_000)
      field(:stall_timeout_ms, :integer, default: 300_000)
    end

    @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
    def changeset(schema, attrs) do
      schema
      |> cast(
        attrs,
        [
          :command,
          :approval_policy,
          :thread_sandbox,
          :turn_sandbox_policy,
          :turn_timeout_ms,
          :read_timeout_ms,
          :stall_timeout_ms
        ],
        empty_values: []
      )
      |> validate_required([:command])
      |> validate_number(:turn_timeout_ms, greater_than: 0)
      |> validate_number(:read_timeout_ms, greater_than: 0)
      |> validate_number(:stall_timeout_ms, greater_than_or_equal_to: 0)
    end
  end

  defmodule ValidationLevel do
    @moduledoc false
    use Ecto.Schema
    import Ecto.Changeset

    alias SymphonyElixir.Config.Schema

    @primary_key false

    @type t :: %__MODULE__{
            name: String.t() | nil,
            description: String.t() | nil,
            command: String.t() | nil,
            unavailable_behavior: String.t() | nil
          }

    embedded_schema do
      field(:name, :string)
      field(:description, :string)
      field(:command, :string)
      field(:unavailable_behavior, :string, default: "manual_handoff")
    end

    @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
    def changeset(schema, attrs) do
      schema
      |> cast(attrs, [:name, :description, :command, :unavailable_behavior], empty_values: [])
      |> update_change(:name, &Schema.normalize_validation_name/1)
      |> update_change(:unavailable_behavior, &Schema.normalize_validation_name/1)
      |> validate_required([:name, :unavailable_behavior])
      |> validate_inclusion(:unavailable_behavior, Schema.supported_validation_unavailable_behaviors(), message: "is unsupported")
    end
  end

  defmodule ValidationEvidenceType do
    @moduledoc false
    use Ecto.Schema
    import Ecto.Changeset

    alias SymphonyElixir.Config.Schema

    @primary_key false

    @type t :: %__MODULE__{
            name: String.t() | nil,
            description: String.t() | nil
          }

    embedded_schema do
      field(:name, :string)
      field(:description, :string)
    end

    @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
    def changeset(schema, attrs) do
      schema
      |> cast(attrs, [:name, :description], empty_values: [])
      |> update_change(:name, &Schema.normalize_validation_name/1)
      |> validate_required([:name])
      |> validate_inclusion(:name, Schema.supported_validation_evidence_types(), message: "is unsupported")
    end
  end

  defmodule ValidationRuleLevel do
    @moduledoc false
    use Ecto.Schema
    import Ecto.Changeset

    alias SymphonyElixir.Config.Schema

    @primary_key false

    @type t :: %__MODULE__{
            name: String.t() | nil,
            evidence_type: String.t() | nil
          }

    embedded_schema do
      field(:name, :string)
      field(:evidence_type, :string, default: "none")
    end

    @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
    def changeset(schema, attrs) do
      schema
      |> cast(attrs, [:name, :evidence_type], empty_values: [])
      |> update_change(:name, &Schema.normalize_validation_name/1)
      |> update_change(:evidence_type, &Schema.normalize_validation_name/1)
      |> validate_required([:name, :evidence_type])
      |> validate_inclusion(:evidence_type, Schema.supported_validation_evidence_types(), message: "is unsupported")
    end
  end

  defmodule ValidationRule do
    @moduledoc false
    use Ecto.Schema
    import Ecto.Changeset

    alias SymphonyElixir.Config.Schema

    @primary_key false

    @type t :: %__MODULE__{
            id: String.t() | nil,
            description: String.t() | nil,
            labels: [String.t()],
            levels: [Schema.ValidationRuleLevel.t()]
          }

    embedded_schema do
      field(:id, :string)
      field(:description, :string)
      field(:labels, {:array, :string}, default: [])

      embeds_many(:levels, Schema.ValidationRuleLevel, on_replace: :delete)
    end

    @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
    def changeset(schema, attrs) do
      schema
      |> cast(attrs, [:id, :description, :labels], empty_values: [])
      |> update_change(:id, &Schema.normalize_validation_name/1)
      |> update_change(:labels, &normalize_labels/1)
      |> validate_required([:id])
      |> validate_change(:labels, &validate_labels/2)
      |> cast_embed(:levels, with: &Schema.ValidationRuleLevel.changeset/2, required: true)
    end

    defp normalize_labels(labels) when is_list(labels) do
      Enum.map(labels, &Schema.normalize_validation_name/1)
    end

    defp normalize_labels(labels), do: labels

    defp validate_labels(:labels, labels) do
      if Enum.any?(labels, &(&1 == "")) do
        [labels: "must not include blank labels"]
      else
        []
      end
    end
  end

  defmodule Validation do
    @moduledoc false
    use Ecto.Schema
    import Ecto.Changeset

    alias SymphonyElixir.Config.Schema

    @primary_key false

    @type t :: %__MODULE__{
            levels: [Schema.ValidationLevel.t()],
            evidence_types: [Schema.ValidationEvidenceType.t()],
            default_rule: Schema.ValidationRule.t() | nil,
            rules: [Schema.ValidationRule.t()]
          }

    embedded_schema do
      embeds_many(:levels, Schema.ValidationLevel, on_replace: :delete)
      embeds_many(:evidence_types, Schema.ValidationEvidenceType, on_replace: :delete)
      embeds_one(:default_rule, Schema.ValidationRule, on_replace: :update)
      embeds_many(:rules, Schema.ValidationRule, on_replace: :delete)
    end

    @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
    def changeset(schema, attrs) do
      schema
      |> cast(attrs, [])
      |> cast_embed(:levels, with: &Schema.ValidationLevel.changeset/2)
      |> cast_embed(:evidence_types, with: &Schema.ValidationEvidenceType.changeset/2)
      |> cast_embed(:default_rule, with: &Schema.ValidationRule.changeset/2)
      |> cast_embed(:rules, with: &Schema.ValidationRule.changeset/2)
    end
  end

  defmodule Hooks do
    @moduledoc false
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key false
    embedded_schema do
      field(:after_create, :string)
      field(:before_run, :string)
      field(:after_run, :string)
      field(:before_remove, :string)
      field(:timeout_ms, :integer, default: 60_000)
    end

    @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
    def changeset(schema, attrs) do
      schema
      |> cast(attrs, [:after_create, :before_run, :after_run, :before_remove, :timeout_ms], empty_values: [])
      |> validate_number(:timeout_ms, greater_than: 0)
    end
  end

  defmodule Observability do
    @moduledoc false
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key false
    embedded_schema do
      field(:dashboard_enabled, :boolean, default: true)
      field(:refresh_ms, :integer, default: 1_000)
      field(:render_interval_ms, :integer, default: 16)
    end

    @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
    def changeset(schema, attrs) do
      schema
      |> cast(attrs, [:dashboard_enabled, :refresh_ms, :render_interval_ms], empty_values: [])
      |> validate_number(:refresh_ms, greater_than: 0)
      |> validate_number(:render_interval_ms, greater_than: 0)
    end
  end

  defmodule Server do
    @moduledoc false
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key false
    embedded_schema do
      field(:port, :integer)
      field(:host, :string, default: "127.0.0.1")
    end

    @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
    def changeset(schema, attrs) do
      schema
      |> cast(attrs, [:port, :host], empty_values: [])
      |> validate_number(:port, greater_than_or_equal_to: 0)
    end
  end

  embedded_schema do
    embeds_one(:tracker, Tracker, on_replace: :update, defaults_to_struct: true)
    embeds_one(:polling, Polling, on_replace: :update, defaults_to_struct: true)
    embeds_one(:workspace, Workspace, on_replace: :update, defaults_to_struct: true)
    embeds_one(:worker, Worker, on_replace: :update, defaults_to_struct: true)
    embeds_one(:agent, Agent, on_replace: :update, defaults_to_struct: true)
    embeds_one(:codex, Codex, on_replace: :update, defaults_to_struct: true)
    embeds_one(:validation, Validation, on_replace: :update)
    embeds_one(:hooks, Hooks, on_replace: :update, defaults_to_struct: true)
    embeds_one(:observability, Observability, on_replace: :update, defaults_to_struct: true)
    embeds_one(:server, Server, on_replace: :update, defaults_to_struct: true)
  end

  @spec parse(map()) :: {:ok, %__MODULE__{}} | {:error, {:invalid_workflow_config, String.t()}}
  def parse(config) when is_map(config) do
    config
    |> normalize_keys()
    |> drop_nil_values()
    |> changeset()
    |> apply_action(:validate)
    |> case do
      {:ok, settings} ->
        finalize_settings(settings)

      {:error, changeset} ->
        {:error, {:invalid_workflow_config, format_errors(changeset)}}
    end
  end

  @spec resolve_turn_sandbox_policy(%__MODULE__{}, Path.t() | nil) :: map()
  def resolve_turn_sandbox_policy(settings, workspace \\ nil) do
    case settings.codex.turn_sandbox_policy do
      %{} = policy ->
        policy

      _ ->
        workspace
        |> default_workspace_root(settings.workspace.root)
        |> expand_local_workspace_root()
        |> default_turn_sandbox_policy()
    end
  end

  @spec resolve_runtime_turn_sandbox_policy(%__MODULE__{}, Path.t() | nil, keyword()) ::
          {:ok, map()} | {:error, term()}
  def resolve_runtime_turn_sandbox_policy(settings, workspace \\ nil, opts \\ []) do
    case settings.codex.turn_sandbox_policy do
      %{} = policy ->
        {:ok, policy}

      _ ->
        workspace
        |> default_workspace_root(settings.workspace.root)
        |> default_runtime_turn_sandbox_policy(opts)
    end
  end

  @spec normalize_issue_state(String.t()) :: String.t()
  def normalize_issue_state(state_name) when is_binary(state_name) do
    String.downcase(state_name)
  end

  @doc false
  @spec supported_validation_evidence_types() :: [String.t()]
  def supported_validation_evidence_types, do: ["none", "logs", "screenshot", "video"]

  @doc false
  @spec supported_validation_unavailable_behaviors() :: [String.t()]
  def supported_validation_unavailable_behaviors, do: ["manual_handoff", "blocked_with_reason"]

  @doc false
  @spec normalize_validation_name(term()) :: term()
  def normalize_validation_name(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
  end

  def normalize_validation_name(value), do: value

  @doc false
  @spec normalize_state_limits(nil | map()) :: map()
  def normalize_state_limits(nil), do: %{}

  def normalize_state_limits(limits) when is_map(limits) do
    Enum.reduce(limits, %{}, fn {state_name, limit}, acc ->
      Map.put(acc, normalize_issue_state(to_string(state_name)), limit)
    end)
  end

  @doc false
  @spec validate_state_limits(Ecto.Changeset.t(), atom()) :: Ecto.Changeset.t()
  def validate_state_limits(changeset, field) do
    validate_change(changeset, field, fn ^field, limits ->
      Enum.flat_map(limits, fn {state_name, limit} ->
        cond do
          to_string(state_name) == "" ->
            [{field, "state names must not be blank"}]

          not is_integer(limit) or limit <= 0 ->
            [{field, "limits must be positive integers"}]

          true ->
            []
        end
      end)
    end)
  end

  defp changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [])
    |> cast_embed(:tracker, with: &Tracker.changeset/2)
    |> cast_embed(:polling, with: &Polling.changeset/2)
    |> cast_embed(:workspace, with: &Workspace.changeset/2)
    |> cast_embed(:worker, with: &Worker.changeset/2)
    |> cast_embed(:agent, with: &Agent.changeset/2)
    |> cast_embed(:codex, with: &Codex.changeset/2)
    |> cast_embed(:validation, with: &Validation.changeset/2)
    |> cast_embed(:hooks, with: &Hooks.changeset/2)
    |> cast_embed(:observability, with: &Observability.changeset/2)
    |> cast_embed(:server, with: &Server.changeset/2)
  end

  defp finalize_settings(settings) do
    with {:ok, validation} <- finalize_validation(settings.validation) do
      tracker = %{
        settings.tracker
        | api_key: resolve_secret_setting(settings.tracker.api_key, System.get_env("LINEAR_API_KEY")),
          assignee: resolve_secret_setting(settings.tracker.assignee, System.get_env("LINEAR_ASSIGNEE"))
      }

      workspace = %{
        settings.workspace
        | root: resolve_path_value(settings.workspace.root, Path.join(System.tmp_dir!(), "symphony_workspaces"))
      }

      codex = %{
        settings.codex
        | approval_policy: normalize_keys(settings.codex.approval_policy),
          turn_sandbox_policy: normalize_optional_map(settings.codex.turn_sandbox_policy)
      }

      {:ok, %{settings | tracker: tracker, workspace: workspace, codex: codex, validation: validation}}
    end
  end

  defp finalize_validation(nil), do: {:ok, default_validation()}

  defp finalize_validation(%Validation{} = validation) do
    validation = %{
      validation
      | levels: validation.levels || [],
        evidence_types: validation.evidence_types || [],
        rules: validation.rules || []
    }

    with :ok <- require_non_empty_validation_list(validation.levels, "validation.levels"),
         :ok <- require_non_empty_validation_list(validation.evidence_types, "validation.evidence_types"),
         :ok <- require_validation_default_rule(validation.default_rule),
         :ok <- validate_unique_validation_names(validation.levels, "validation.levels"),
         :ok <- validate_unique_validation_names(validation.evidence_types, "validation.evidence_types"),
         level_names <- validation_names(validation.levels),
         evidence_names <- validation_names(validation.evidence_types),
         :ok <- validate_validation_rule("validation.default_rule", validation.default_rule, level_names, evidence_names, false),
         :ok <- validate_validation_rules(validation.rules, level_names, evidence_names) do
      {:ok, validation}
    else
      {:error, message} ->
        {:error, {:invalid_workflow_config, message}}
    end
  end

  defp default_validation do
    %Validation{
      levels: [
        %ValidationLevel{
          name: "compile",
          description: "Run the minimum project-safe static or compile validation.",
          unavailable_behavior: "blocked_with_reason"
        }
      ],
      evidence_types: [
        %ValidationEvidenceType{
          name: "none",
          description: "No external artifact required; record the result in the workpad."
        }
      ],
      default_rule: %ValidationRule{
        id: "loosest",
        description: "Loosest default validation guidance for unlabeled or unmatched tickets.",
        labels: [],
        levels: [%ValidationRuleLevel{name: "compile", evidence_type: "none"}]
      },
      rules: []
    }
  end

  defp require_non_empty_validation_list([], path), do: {:error, "#{path} must include at least one entry"}
  defp require_non_empty_validation_list(_items, _path), do: :ok

  defp require_validation_default_rule(nil), do: {:error, "validation.default_rule can't be blank"}
  defp require_validation_default_rule(%ValidationRule{}), do: :ok

  defp validate_unique_validation_names(items, path) do
    duplicate =
      items
      |> Enum.map(& &1.name)
      |> Enum.frequencies()
      |> Enum.find(fn {_name, count} -> count > 1 end)

    case duplicate do
      {name, _count} -> {:error, "#{path} contains duplicate name #{inspect(name)}"}
      nil -> :ok
    end
  end

  defp validation_names(items) do
    items
    |> Enum.map(& &1.name)
    |> MapSet.new()
  end

  defp validate_validation_rules(rules, level_names, evidence_names) do
    rules
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {rule, index}, :ok ->
      case validate_validation_rule("validation.rules[#{index}]", rule, level_names, evidence_names, true) do
        :ok -> {:cont, :ok}
        {:error, message} -> {:halt, {:error, message}}
      end
    end)
  end

  defp validate_validation_rule(path, %ValidationRule{} = rule, level_names, evidence_names, labels_required) do
    if labels_required and rule.labels == [] do
      {:error, "#{path}.labels must include at least one Linear label"}
    else
      validate_validation_rule_levels(path, rule.levels, level_names, evidence_names)
    end
  end

  defp validate_validation_rule_levels(path, levels, level_names, evidence_names) do
    levels
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {level, index}, :ok ->
      cond do
        not MapSet.member?(level_names, level.name) ->
          {:halt, {:error, "#{path}.levels[#{index}].name references unknown validation level #{inspect(level.name)}"}}

        not MapSet.member?(evidence_names, level.evidence_type) ->
          {:halt, {:error, "#{path}.levels[#{index}].evidence_type references unknown evidence type #{inspect(level.evidence_type)}"}}

        true ->
          {:cont, :ok}
      end
    end)
  end

  defp normalize_keys(value) when is_map(value) do
    Enum.reduce(value, %{}, fn {key, raw_value}, normalized ->
      Map.put(normalized, normalize_key(key), normalize_keys(raw_value))
    end)
  end

  defp normalize_keys(value) when is_list(value), do: Enum.map(value, &normalize_keys/1)
  defp normalize_keys(value), do: value

  defp normalize_optional_map(nil), do: nil
  defp normalize_optional_map(value) when is_map(value), do: normalize_keys(value)

  defp normalize_key(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_key(value), do: to_string(value)

  defp drop_nil_values(value) when is_map(value) do
    Enum.reduce(value, %{}, fn {key, nested}, acc ->
      case drop_nil_values(nested) do
        nil -> acc
        normalized -> Map.put(acc, key, normalized)
      end
    end)
  end

  defp drop_nil_values(value) when is_list(value), do: Enum.map(value, &drop_nil_values/1)
  defp drop_nil_values(value), do: value

  defp resolve_secret_setting(nil, fallback), do: normalize_secret_value(fallback)

  defp resolve_secret_setting(value, fallback) when is_binary(value) do
    case resolve_env_value(value, fallback) do
      resolved when is_binary(resolved) -> normalize_secret_value(resolved)
      resolved -> resolved
    end
  end

  defp resolve_path_value(value, default) when is_binary(value) do
    case normalize_path_token(value) do
      :missing ->
        default

      "" ->
        default

      path ->
        path
    end
  end

  defp resolve_env_value(value, fallback) when is_binary(value) do
    case env_reference_name(value) do
      {:ok, env_name} ->
        case System.get_env(env_name) do
          nil -> fallback
          "" -> nil
          env_value -> env_value
        end

      :error ->
        value
    end
  end

  defp normalize_path_token(value) when is_binary(value) do
    case env_reference_name(value) do
      {:ok, env_name} -> resolve_env_token(env_name)
      :error -> value
    end
  end

  defp env_reference_name("$" <> env_name) do
    if String.match?(env_name, ~r/^[A-Za-z_][A-Za-z0-9_]*$/) do
      {:ok, env_name}
    else
      :error
    end
  end

  defp env_reference_name(_value), do: :error

  defp resolve_env_token(env_name) do
    case System.get_env(env_name) do
      nil -> :missing
      env_value -> env_value
    end
  end

  defp normalize_secret_value(value) when is_binary(value) do
    if value == "", do: nil, else: value
  end

  defp normalize_secret_value(_value), do: nil

  defp default_turn_sandbox_policy(workspace) do
    %{
      "type" => "workspaceWrite",
      "writableRoots" => [workspace],
      "readOnlyAccess" => %{"type" => "fullAccess"},
      "networkAccess" => false,
      "excludeTmpdirEnvVar" => false,
      "excludeSlashTmp" => false
    }
  end

  defp default_runtime_turn_sandbox_policy(workspace_root, opts) when is_binary(workspace_root) do
    if Keyword.get(opts, :remote, false) do
      {:ok, default_turn_sandbox_policy(workspace_root)}
    else
      with expanded_workspace_root <- expand_local_workspace_root(workspace_root),
           {:ok, canonical_workspace_root} <- PathSafety.canonicalize(expanded_workspace_root) do
        {:ok, default_turn_sandbox_policy(canonical_workspace_root)}
      end
    end
  end

  defp default_runtime_turn_sandbox_policy(workspace_root, _opts) do
    {:error, {:unsafe_turn_sandbox_policy, {:invalid_workspace_root, workspace_root}}}
  end

  defp default_workspace_root(workspace, _fallback) when is_binary(workspace) and workspace != "",
    do: workspace

  defp default_workspace_root(nil, fallback), do: fallback
  defp default_workspace_root("", fallback), do: fallback
  defp default_workspace_root(workspace, _fallback), do: workspace

  defp expand_local_workspace_root(workspace_root)
       when is_binary(workspace_root) and workspace_root != "" do
    Path.expand(workspace_root)
  end

  defp expand_local_workspace_root(_workspace_root) do
    Path.expand(Path.join(System.tmp_dir!(), "symphony_workspaces"))
  end

  defp format_errors(changeset) do
    changeset
    |> traverse_errors(&translate_error/1)
    |> flatten_errors()
    |> Enum.join(", ")
  end

  defp flatten_errors(errors, prefix \\ nil)

  defp flatten_errors(errors, prefix) when is_map(errors) do
    Enum.flat_map(errors, fn {key, value} ->
      next_prefix =
        case prefix do
          nil -> to_string(key)
          current -> current <> "." <> to_string(key)
        end

      flatten_errors(value, next_prefix)
    end)
  end

  defp flatten_errors(errors, prefix) when is_list(errors) do
    Enum.flat_map(errors, fn
      message when is_binary(message) -> [prefix <> " " <> message]
      nested -> flatten_errors(nested, prefix)
    end)
  end

  defp translate_error({message, options}) do
    Enum.reduce(options, message, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", error_value_to_string(value))
    end)
  end

  defp error_value_to_string(value) when is_atom(value), do: Atom.to_string(value)
  defp error_value_to_string(value), do: inspect(value)
end
