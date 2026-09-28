defmodule Yup.ClarifyingInbox.AnswerMatcher do
  @moduledoc false

  # Matching is intentionally lenient and purely structural (labels, indices,
  # word boundaries) so a chat-submitted answer never needs to reproduce an
  # offered option byte for byte. An answer is accepted when it references at
  # least one offered option by its exact stored string, its leading label,
  # a word-boundary mention of that label, or a one-based letter/number
  # index. Answers whose segments each reference an option ("A and B", two
  # labels joined by "and") are accepted as combined choices.

  @bullet ~r/\A(?:[-*+>]\s+)/
  @checkbox ~r/\A(?:\[\s*[xX ]?\s*\]|\(\s*[xX ]?\s*\))\s*/
  @leading_number ~r/\A\d+[.)]\s+/
  @filler ~r/\A(?:both|either|all|any|option|options|answer)\s+/
  @trailing_punctuation ~r/[\s.,;:!)\]]+\z/
  @letter_index ~r/\A(?:option\s+)?([a-z])[.):\]]?\z/
  @numeric_index ~r/\A#?(\d+)[.):\]]?\z/
  @segment_separator ~r/\s*(?:,|;|&|\+|\/|\band\b|\bor\b)\s*/
  @whitespace ~r/\s+/
  @double_quoted ~r/\A".*"\z/
  @single_quoted ~r/\A'.*'\z/

  @spec match([String.t()], String.t()) ::
          {:ok, [{pos_integer(), String.t()}]} | {:error, String.t() | nil}
  def match(options, answer) do
    normalized = normalize(answer)

    cond do
      normalized == "" -> {:error, nil}
      options == [] -> {:ok, []}
      true -> match_normalized(options, normalized)
    end
  end

  defp match_normalized(options, normalized) do
    matches =
      (direct_matches(options, normalized) ++ combined_matches(options, normalized))
      |> Enum.uniq_by(fn {index, _option} -> index end)

    case matches do
      [] -> {:error, closest_option(options, normalized)}
      matches -> {:ok, Enum.sort_by(matches, fn {index, _option} -> index end)}
    end
  end

  defp direct_matches(options, normalized) do
    options
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {option, index} ->
      if option_matches?(option, index, normalized), do: [{index, option}], else: []
    end)
  end

  defp combined_matches(options, normalized) do
    case String.split(normalized, @segment_separator) do
      [_single] ->
        []

      segments ->
        segments = Enum.map(segments, &String.trim(&1, ~s{"'}))

        if Enum.all?(segments, &segment_matches?(options, &1)) do
          Enum.flat_map(segments, &direct_matches(options, &1))
        else
          []
        end
    end
  end

  defp segment_matches?(options, segment) do
    options
    |> Enum.with_index(1)
    |> Enum.any?(fn {option, index} -> option_matches?(option, index, segment) end)
  end

  defp option_matches?(option, index, normalized) do
    normalized == normalize(option) or index_matches?(normalized, index) or
      contains_label?(normalized, option)
  end

  defp index_matches?(normalized, index) do
    letter_index_matches?(normalized, index) or numeric_index_matches?(normalized, index)
  end

  defp letter_index_matches?(normalized, index) do
    case Regex.run(@letter_index, normalized) do
      [_, letter] -> letter == letter_for(index)
      nil -> false
    end
  end

  defp numeric_index_matches?(normalized, index) do
    case Regex.run(@numeric_index, normalized) do
      [_, digits] -> String.to_integer(digits) == index
      nil -> false
    end
  end

  defp letter_for(index) when index in 1..26//1, do: <<?a - 1 + index>>
  defp letter_for(_index), do: nil

  defp contains_label?(normalized, option) do
    normalized_label = option |> label() |> normalize()

    normalized_label != "" and
      Regex.match?(~r/\b#{Regex.escape(normalized_label)}\b/, normalized)
  end

  defp label(option) do
    case :binary.split(option, ")") do
      [label, _prose] -> label
      [option] -> option
    end
  end

  defp closest_option([], _normalized), do: nil

  defp closest_option([option | rest], normalized) do
    Enum.reduce(rest, option, fn candidate, closest ->
      if similarity(normalized, candidate) > similarity(normalized, closest),
        do: candidate,
        else: closest
    end)
  end

  defp similarity(normalized, option) do
    normalized_label = option |> label() |> normalize()

    max(
      String.jaro_distance(normalized, normalize(option)),
      String.jaro_distance(normalized, normalized_label)
    )
  end

  defp normalize(text) do
    text
    |> strip_markers()
    |> String.replace(@whitespace, " ")
    |> String.trim()
    |> String.downcase()
  end

  defp strip_markers(text) do
    stripped = strip_quotes(String.trim(text))

    case strip_prefix(stripped) do
      nil -> String.replace(stripped, @trailing_punctuation, "")
      rest -> strip_markers(rest)
    end
  end

  defp strip_quotes(text) do
    cond do
      text =~ @double_quoted -> String.slice(text, 1..-2//1)
      text =~ @single_quoted -> String.slice(text, 1..-2//1)
      true -> text
    end
  end

  defp strip_prefix(text) do
    Enum.find_value([@bullet, @checkbox, @leading_number, @filler], fn pattern ->
      case Regex.split(pattern, text, parts: 2) do
        [_, rest] -> rest
        [_] -> nil
      end
    end)
  end
end
