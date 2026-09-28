defmodule Yup.ClarifyingInbox do
  @moduledoc false

  # Tooling for the clarifying-questions inbox on `needs_input` issues. The
  # assistant collects the user's chat answers and submits them through
  # `submit_clarifying_answers/4`; answers that reference an offered option
  # are validated leniently (see `Yup.ClarifyingInbox.AnswerMatcher`) and
  # recorded as an issue comment that carries the answer verbatim, including
  # any nuance or combination the user expressed. Posting is injected so the
  # tool works against any comment backend.

  alias Yup.ClarifyingInbox.AnswerMatcher
  alias Yup.ClarifyingInbox.Question

  @type answers :: %{optional(pos_integer()) => String.t()} | [String.t()]
  @type commenter :: (pos_integer(), String.t() -> {:ok, term()} | {:error, term()})
  @type error :: %{code: String.t(), message: String.t()}

  @spec parse_questions(String.t()) :: [Question.t()]
  def parse_questions(markdown), do: Question.parse(markdown)

  @spec submit_clarifying_answers(pos_integer(), [Question.t()], answers(), commenter()) ::
          {:ok, %{comment_body: String.t(), posted: term()}} | {:error, error()}
  def submit_clarifying_answers(issue_number, questions, answers, commenter) do
    with {:ok, normalized} <- normalize_answers(questions, answers),
         {:ok, entries} <- validate_answers(questions, normalized) do
      post(issue_number, entries, commenter)
    end
  end

  defp normalize_answers(questions, answers) when is_list(answers) do
    if length(answers) > length(questions) do
      {:error,
       invalid(
         "got #{length(answers)} answers for only #{length(questions)} clarifying questions"
       )}
    else
      {:ok,
       questions
       |> Enum.zip(answers)
       |> Map.new(fn {question, answer} -> {question.number, answer} end)}
    end
  end

  defp normalize_answers(_questions, answers) when is_map(answers) do
    Enum.reduce_while(answers, {:ok, %{}}, fn {key, value}, {:ok, acc} ->
      normalize_answer(key, value, acc)
    end)
  end

  defp normalize_answers(_questions, answers) do
    {:error,
     invalid("answers must be a map of question numbers to strings, got: #{inspect(answers)}")}
  end

  defp normalize_answer(key, value, acc) when is_binary(value) do
    case answer_number(key) do
      {:ok, number} -> {:cont, {:ok, Map.put(acc, number, value)}}
      :error -> {:halt, {:error, invalid("answer key #{inspect(key)} is not a question number")}}
    end
  end

  defp normalize_answer(key, value, _acc) do
    {:halt,
     {:error, invalid("answer for #{inspect(key)} must be a string, got: #{inspect(value)}")}}
  end

  defp answer_number(number) when is_integer(number) and number >= 1, do: {:ok, number}

  defp answer_number(key) when is_binary(key) do
    case Integer.parse(key) do
      {number, ""} when number >= 1 -> {:ok, number}
      _ -> :error
    end
  end

  defp answer_number(_key), do: :error

  defp validate_answers(_questions, answers) when map_size(answers) == 0 do
    {:error, invalid("no answers provided")}
  end

  defp validate_answers(questions, answers) do
    by_number = Map.new(questions, fn question -> {question.number, question} end)

    case reduce_answers(Enum.sort(answers), by_number, []) do
      {:ok, entries} -> {:ok, Enum.reverse(entries)}
      error -> error
    end
  end

  defp reduce_answers(answers, by_number, entries) do
    Enum.reduce_while(answers, {:ok, entries}, fn {number, answer}, {:ok, acc} ->
      validate_answer(Map.get(by_number, number), number, answer, acc)
    end)
  end

  defp validate_answer(nil, number, _answer, _entries) do
    {:halt, {:error, invalid("there is no clarifying question numbered #{number}")}}
  end

  defp validate_answer(question, number, answer, entries) do
    case AnswerMatcher.match(question.options, answer) do
      {:ok, matches} ->
        {:cont, {:ok, [%{question: question, answer: answer, matches: matches} | entries]}}

      {:error, nil} ->
        {:halt, {:error, invalid("answer #{number} is empty")}}

      {:error, closest} ->
        {:halt, {:error, invalid(mismatch_message(number, answer, question, closest))}}
    end
  end

  defp mismatch_message(number, answer, question, closest) do
    offered =
      question.options
      |> Enum.with_index(1)
      |> Enum.map_join(", ", fn {option, index} ->
        "(#{display_index(index)}) #{inspect(option)}"
      end)

    "Answer #{number}: #{inspect(answer)} isn't one of the offered options. " <>
      "Closest stored option: #{inspect(closest)}. " <>
      "Offered options: #{offered}. " <>
      "Resubmit an exact stored string, its leading label, or its letter."
  end

  defp display_index(index) when index <= 26, do: <<?A - 1 + index>>
  defp display_index(index), do: Integer.to_string(index)

  defp post(issue_number, entries, commenter) do
    body = build_comment_body(entries)

    case commenter.(issue_number, body) do
      {:ok, posted} ->
        {:ok, %{comment_body: body, posted: posted}}

      {:error, reason} ->
        {:error,
         %{code: "comment_failed", message: "posting the comment failed: #{inspect(reason)}"}}
    end
  end

  defp build_comment_body(entries) do
    sections = Enum.map_join(entries, "\n\n", &build_section/1)
    "## Clarifying answers\n\n" <> sections <> "\n"
  end

  defp build_section(entry) do
    lines =
      ["### #{entry.question.number}. #{entry.question.text}", "", "- Answer: #{entry.answer}"] ++
        matched_option_lines(entry)

    Enum.join(lines, "\n")
  end

  defp matched_option_lines(%{matches: []}), do: []

  defp matched_option_lines(entry) do
    Enum.map(entry.matches, fn {_index, option} -> "- Matched option: #{option}" end)
  end

  defp invalid(message), do: %{code: "invalid_arguments", message: message}
end
