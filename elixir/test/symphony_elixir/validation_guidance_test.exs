defmodule SymphonyElixir.ValidationGuidanceTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.Config.Schema
  alias SymphonyElixir.ValidationGuidance

  test "schema parse provides loosest validation defaults when validation block is omitted" do
    assert {:ok, settings} = Schema.parse(%{})

    validation = settings.validation
    assert Enum.map(validation.levels, & &1.name) == ["compile"]
    assert Enum.map(validation.evidence_types, & &1.name) == ["none"]
    assert validation.default_rule.id == "loosest"
    assert [%{name: "compile", evidence_type: "none"}] = validation.default_rule.levels

    guidance = ValidationGuidance.resolve(validation, %Issue{labels: []})

    assert guidance["fallback"]
    assert guidance["fallback_reason"] == "missing_labels"
    assert guidance["matched_rule"]["source"] == "default_rule"

    assert guidance["required_levels"] == [
             %{
               "name" => "compile",
               "description" => "Run the minimum project-safe static or compile validation.",
               "command" => nil,
               "unavailable_behavior" => "blocked_with_reason",
               "evidence_type" => "none",
               "evidence" => %{
                 "name" => "none",
                 "description" => "No external artifact required; record the result in the workpad."
               }
             }
           ]
  end

  test "schema parse normalizes configured validation levels evidence types and rules" do
    assert {:ok, settings} = Schema.parse(%{validation: validation_config()})

    validation = settings.validation
    assert Enum.map(validation.levels, & &1.name) == ["compile", "reproduce"]
    assert Enum.map(validation.evidence_types, & &1.name) == ["none", "logs", "screenshot"]
    assert validation.default_rule.id == "loosest"
    assert validation.default_rule.levels |> Enum.map(&{&1.name, &1.evidence_type}) == [{"compile", "none"}]

    [bug_rule, visual_rule] = validation.rules
    assert bug_rule.id == "bug"
    assert bug_rule.labels == ["bug", "defect"]
    assert Enum.map(bug_rule.levels, &{&1.name, &1.evidence_type}) == [{"reproduce", "logs"}, {"compile", "logs"}]
    assert visual_rule.id == "visual"
    assert visual_rule.labels == ["visual"]
  end

  test "schema parse rejects invalid validation configuration with clear errors" do
    invalid_unavailable =
      put_in(validation_config(), [:levels, Access.at!(0), :unavailable_behavior], "ask_a_human")

    assert {:error, {:invalid_workflow_config, message}} = Schema.parse(%{validation: invalid_unavailable})
    assert message =~ "validation.levels.unavailable_behavior"
    assert message =~ "unsupported"

    unknown_evidence =
      validation_config()
      |> put_in([:evidence_types], [%{name: "none", description: "No artifact."}])

    assert {:error, {:invalid_workflow_config, message}} = Schema.parse(%{validation: unknown_evidence})
    assert message =~ "validation.rules[0].levels[0].evidence_type"
    assert message =~ "unknown evidence type"

    unknown_level =
      validation_config()
      |> put_in([:rules, Access.at!(0), :levels, Access.at!(0), :name], "acceptance")

    assert {:error, {:invalid_workflow_config, message}} = Schema.parse(%{validation: unknown_level})
    assert message =~ "validation.rules[0].levels[0].name"
    assert message =~ "unknown validation level"
  end

  test "schema parse rejects incomplete validation configuration with clear errors" do
    empty_levels =
      validation_config()
      |> put_in([:levels], [])

    assert {:error, {:invalid_workflow_config, message}} = Schema.parse(%{validation: empty_levels})
    assert message =~ "validation.levels must include at least one entry"

    missing_default =
      validation_config()
      |> Map.delete(:default_rule)

    assert {:error, {:invalid_workflow_config, message}} = Schema.parse(%{validation: missing_default})
    assert message =~ "validation.default_rule can't be blank"

    duplicate_level =
      validation_config()
      |> put_in([:levels, Access.at!(1), :name], "compile")

    assert {:error, {:invalid_workflow_config, message}} = Schema.parse(%{validation: duplicate_level})
    assert message =~ "validation.levels contains duplicate name \"compile\""

    unlabeled_rule =
      validation_config()
      |> put_in([:rules, Access.at!(0), :labels], [])

    assert {:error, {:invalid_workflow_config, message}} = Schema.parse(%{validation: unlabeled_rule})
    assert message =~ "validation.rules[0].labels must include at least one Linear label"

    empty_default_rule_levels =
      validation_config()
      |> put_in([:default_rule, :levels], [])

    assert {:error, {:invalid_workflow_config, message}} = Schema.parse(%{validation: empty_default_rule_levels})
    assert message =~ "validation.default_rule.levels can't be blank"
  end

  test "guidance resolution matches labels case-insensitively and expands level metadata" do
    assert {:ok, settings} = Schema.parse(%{validation: validation_config()})

    guidance = ValidationGuidance.resolve(settings.validation, %Issue{labels: ["  BUG  "]})

    refute guidance["fallback"]
    assert guidance["fallback_reason"] == nil
    assert guidance["issue_labels"] == ["bug"]
    assert guidance["matched_rule"]["id"] == "bug"
    assert guidance["matched_rule"]["matched_labels"] == ["bug"]

    assert Enum.map(guidance["required_levels"], &{&1["name"], &1["evidence_type"], &1["command"]}) == [
             {"reproduce", "logs", nil},
             {"compile", "logs", "mix compile"}
           ]

    assert guidance["required_evidence_types"] == [
             %{
               "name" => "logs",
               "description" => "Command output or log excerpt.",
               "levels" => ["reproduce", "compile"]
             }
           ]
  end

  test "guidance resolution falls back for missing non-standard and non-list labels" do
    assert {:ok, settings} = Schema.parse(%{validation: validation_config()})

    missing = ValidationGuidance.resolve(settings.validation, %{"labels" => []})
    assert missing["fallback"]
    assert missing["fallback_reason"] == "missing_labels"

    non_standard = ValidationGuidance.resolve(settings.validation, %{labels: ["backend"]})
    assert non_standard["fallback"]
    assert non_standard["fallback_reason"] == "no_matching_rule"

    invalid_labels = ValidationGuidance.resolve(settings.validation, %{labels: "bug"})
    assert invalid_labels["fallback"]
    assert invalid_labels["fallback_reason"] == "missing_labels"

    nil_issue = ValidationGuidance.resolve(settings.validation, nil)
    assert nil_issue["fallback"]
    assert nil_issue["fallback_reason"] == "missing_labels"
  end

  test "guidance resolution preserves workflow rule order and uses the first match" do
    config =
      validation_config()
      |> put_in(
        [:rules],
        [
          %{id: "first", labels: ["bug"], levels: [%{name: "compile", evidence_type: "none"}]},
          %{id: "second", labels: ["bug"], levels: [%{name: "compile", evidence_type: "logs"}]}
        ]
      )

    assert {:ok, settings} = Schema.parse(%{validation: config})

    guidance = ValidationGuidance.resolve(settings.validation, %Issue{labels: ["bug"]})

    assert guidance["matched_rule"]["id"] == "first"
    assert Enum.map(guidance["required_levels"], & &1["evidence_type"]) == ["none"]
  end

  test "prompt builder renders validation guidance in Solid templates" do
    workflow = """
    ---
    validation:
      levels:
        - name: compile
          description: Compile changed code.
          command: "mix compile"
          unavailable_behavior: blocked_with_reason
      evidence_types:
        - name: logs
          description: Command output or log excerpt.
      default_rule:
        id: loosest
        levels:
          - name: compile
            evidence_type: logs
      rules:
        - id: bug
          labels: [bug]
          levels:
            - name: compile
              evidence_type: logs
    ---
    Rule {{ validation.matched_rule.id }}
    {% for level in validation.required_levels %}
    Level {{ level.name }} command={{ level.command }} evidence={{ level.evidence_type }}
    {% endfor %}
    """

    File.write!(Workflow.workflow_file_path(), workflow)
    WorkflowStore.force_reload()

    issue = %Issue{
      identifier: "MT-900",
      title: "Render validation context",
      description: "Testing: run the configured command",
      state: "Todo",
      url: "https://example.org/issues/MT-900",
      labels: ["bug"]
    }

    prompt = PromptBuilder.build_prompt(issue)

    assert prompt =~ "Rule bug"
    assert prompt =~ "Level compile command=mix compile evidence=logs"
  end

  defp validation_config do
    %{
      levels: [
        %{
          name: " Compile ",
          description: "Compile changed code.",
          command: "mix compile",
          unavailable_behavior: "blocked_with_reason"
        },
        %{
          name: "Reproduce",
          description: "Reproduce the issue signal.",
          unavailable_behavior: "manual_handoff"
        }
      ],
      evidence_types: [
        %{name: "none", description: "No artifact."},
        %{name: "Logs", description: "Command output or log excerpt."},
        %{name: "screenshot", description: "Screenshot proof."}
      ],
      default_rule: %{
        id: "Loosest",
        description: "Loose fallback.",
        levels: [%{name: "compile", evidence_type: "none"}]
      },
      rules: [
        %{
          id: "Bug",
          description: "Bug validation.",
          labels: [" BUG ", "Defect"],
          levels: [
            %{name: "Reproduce", evidence_type: "LOGS"},
            %{name: "compile", evidence_type: "logs"}
          ]
        },
        %{
          id: "Visual",
          description: "Visual validation.",
          labels: ["visual"],
          levels: [%{name: "compile", evidence_type: "screenshot"}]
        }
      ]
    }
  end
end
