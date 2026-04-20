defmodule SymphonyElixir.ValidationGuidance do
  @moduledoc """
  Resolves prompt-ready validation guidance from workflow config and issue labels.
  """

  alias SymphonyElixir.Config.Schema
  alias SymphonyElixir.Linear.Issue

  @type guidance :: %{
          String.t() => term()
        }

  @spec resolve(Schema.Validation.t(), Issue.t() | map() | nil) :: guidance()
  def resolve(%Schema.Validation{} = validation, issue) do
    issue_labels = normalized_issue_labels(issue)

    {rule, fallback?, reason, matched_labels} =
      case first_matching_rule(validation.rules, issue_labels) do
        nil ->
          {validation.default_rule, true, fallback_reason(issue_labels), []}

        {matched_rule, labels} ->
          {matched_rule, false, nil, labels}
      end

    build_guidance(validation, rule, fallback?, reason, issue_labels, matched_labels)
  end

  defp first_matching_rule(rules, issue_labels) do
    label_set = MapSet.new(issue_labels)

    Enum.find_value(rules || [], fn rule ->
      matched_labels = Enum.filter(rule.labels || [], &MapSet.member?(label_set, &1))

      if matched_labels == [] do
        nil
      else
        {rule, matched_labels}
      end
    end)
  end

  defp fallback_reason([]), do: "missing_labels"
  defp fallback_reason(_labels), do: "no_matching_rule"

  defp build_guidance(validation, rule, fallback?, reason, issue_labels, matched_labels) do
    level_definitions = Map.new(validation.levels, &{&1.name, &1})
    evidence_definitions = Map.new(validation.evidence_types, &{&1.name, &1})
    required_levels = expand_required_levels(rule.levels, level_definitions, evidence_definitions)

    %{
      "fallback" => fallback?,
      "fallback_reason" => reason,
      "issue_labels" => issue_labels,
      "matched_rule" => %{
        "id" => rule.id,
        "description" => rule.description,
        "labels" => rule.labels || [],
        "matched_labels" => matched_labels,
        "source" => if(fallback?, do: "default_rule", else: "rule")
      },
      "required_levels" => required_levels,
      "required_evidence_types" => required_evidence_types(required_levels)
    }
  end

  defp expand_required_levels(levels, level_definitions, evidence_definitions) do
    Enum.map(levels || [], fn level ->
      level_definition = Map.fetch!(level_definitions, level.name)
      evidence_definition = Map.fetch!(evidence_definitions, level.evidence_type)

      %{
        "name" => level.name,
        "description" => level_definition.description,
        "command" => level_definition.command,
        "unavailable_behavior" => level_definition.unavailable_behavior,
        "evidence_type" => level.evidence_type,
        "evidence" => %{
          "name" => evidence_definition.name,
          "description" => evidence_definition.description
        }
      }
    end)
  end

  defp required_evidence_types(required_levels) do
    required_levels
    |> Enum.group_by(& &1["evidence_type"])
    |> Enum.map(fn {evidence_type, levels} ->
      evidence = levels |> List.first() |> Map.fetch!("evidence")

      %{
        "name" => evidence_type,
        "description" => evidence["description"],
        "levels" => Enum.map(levels, & &1["name"])
      }
    end)
    |> Enum.sort_by(& &1["name"])
  end

  defp normalized_issue_labels(%Issue{labels: labels}), do: normalize_labels(labels)
  defp normalized_issue_labels(%{labels: labels}), do: normalize_labels(labels)
  defp normalized_issue_labels(%{"labels" => labels}), do: normalize_labels(labels)
  defp normalized_issue_labels(_issue), do: []

  defp normalize_labels(labels) when is_list(labels) do
    labels
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&Schema.normalize_validation_name/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp normalize_labels(_labels), do: []
end
