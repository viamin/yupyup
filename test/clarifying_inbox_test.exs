defmodule Yup.ClarifyingInboxTest do
  use ExUnit.Case, async: true

  alias Yup.ClarifyingInbox
  alias Yup.ClarifyingInbox.Question

  @sanity_checks ~s{Built-in sanity checks) e.g. every transition must change state, or undefined state-field reads are a failure.}
  @explicit_assertions "Explicit assertions) users write `assert` expressions inside transitions."
  @skip_checks "Skip checks) verification stays parsing-only for now."

  @inbox """
  1. Which checks should `yup verify` run?
     - ( ) Built-in sanity checks) e.g. every transition must change state, or undefined state-field reads are a failure.
     - ( ) Explicit assertions) users write `assert` expressions inside transitions.
     - ( ) Skip checks) verification stays parsing-only for now.
  2. How should exploration depth be limited?
     - ( ) Bound the search to a fixed transition budget
     - ( ) Bound the search to a fixed state budget
     - ( ) Leave it unbounded
  """

  setup do
    %{questions: ClarifyingInbox.parse_questions(@inbox)}
  end

  defp submit(questions, answers) do
    commenter = fn issue_number, body ->
      send(self(), {:comment, issue_number, body})
      {:ok, %{url: "https://example.com/issues/9#comment-1"}}
    end

    ClarifyingInbox.submit_clarifying_answers(9, questions, answers, commenter)
  end

  test "parses questions with exact stored options from the inbox markdown", %{
    questions: questions
  } do
    assert [
             %Question{number: 1, text: "Which checks should `yup verify` run?", options: first},
             %Question{
               number: 2,
               text: "How should exploration depth be limited?",
               options: second
             }
           ] = questions

    assert first == [@sanity_checks, @explicit_assertions, @skip_checks]

    assert second == [
             "Bound the search to a fixed transition budget",
             "Bound the search to a fixed state budget",
             "Leave it unbounded"
           ]
  end

  test "submitting an offered option's leading label posts a comment containing the answer", %{
    questions: questions
  } do
    assert {:ok, %{posted: %{url: url}}} = submit(questions, %{1 => "Built-in sanity checks"})
    assert url == "https://example.com/issues/9#comment-1"

    assert_received {:comment, 9, body}
    assert body =~ "### 1. Which checks should `yup verify` run?"
    assert body =~ "- Answer: Built-in sanity checks"
    assert body =~ "- Matched option: #{@sanity_checks}"
  end

  test "submitting a letter index posts a comment containing the indexed option", %{
    questions: questions
  } do
    assert {:ok, _} = submit(questions, %{1 => "B"})

    assert_received {:comment, 9, body}
    assert body =~ "- Answer: B"
    assert body =~ "- Matched option: #{@explicit_assertions}"
  end

  test "submitting the full option text succeeds", %{questions: questions} do
    assert {:ok, _} = submit(questions, %{1 => @sanity_checks})
  end

  test "checkbox markers preserved in the answer are accepted", %{questions: questions} do
    assert {:ok, _} = submit(questions, %{1 => "( ) #{@sanity_checks}"})
    assert {:ok, _} = submit(questions, %{1 => "[ ] Built-in sanity checks) whatever follows"})
    assert {:ok, _} = submit(questions, %{1 => "- ( ) Built-in sanity checks"})
  end

  test "labels match case-insensitively with loose punctuation", %{questions: questions} do
    assert {:ok, _} = submit(questions, %{1 => "built-in sanity checks"})
    assert {:ok, _} = submit(questions, %{1 => "Option C."})
    assert {:ok, _} = submit(questions, %{1 => "#3"})
  end

  test "a refined answer that scopes an option tighter is recorded verbatim", %{
    questions: questions
  } do
    refined =
      "Built-in sanity checks, but only evaluation-level checks; structural checks like 'every transition must change state' stay out"

    assert {:ok, _} = submit(questions, %{1 => refined})

    assert_received {:comment, 9, body}
    assert body =~ "- Answer: #{refined}"
    assert body =~ "- Matched option: #{@sanity_checks}"
  end

  test "a combined answer that references two options records both matches", %{
    questions: questions
  } do
    combined = "Built-in sanity checks and Explicit assertions"

    assert {:ok, _} = submit(questions, %{1 => combined})

    assert_received {:comment, 9, body}
    assert body =~ "- Answer: #{combined}"
    assert body =~ "- Matched option: #{@sanity_checks}"
    assert body =~ "- Matched option: #{@explicit_assertions}"
  end

  test "combined letter indices are accepted", %{questions: questions} do
    assert {:ok, _} = submit(questions, %{2 => "A and B"})

    assert_received {:comment, 9, body}
    assert body =~ "- Matched option: Bound the search to a fixed transition budget"
    assert body =~ "- Matched option: Bound the search to a fixed state budget"
    refute body =~ "- Matched option: Leave it unbounded"
  end

  test "options without a label delimiter match by whole text", %{questions: questions} do
    assert {:ok, _} = submit(questions, %{2 => "Leave it unbounded"})
    assert {:ok, _} = submit(questions, %{2 => "leave it unbounded, please"})
  end

  test "an answer that references no offered option echoes the closest stored string exactly",
       %{questions: questions} do
    assert {:error, %{code: "invalid_arguments", message: message}} =
             submit(questions, %{1 => "run the model checker in reverse"})

    assert message =~
             ~s(Answer 1: "run the model checker in reverse" isn't one of the offered options.)

    assert message =~ "Closest stored option: "
    assert message =~ inspect(@sanity_checks)
    assert message =~ inspect(@explicit_assertions)
    assert message =~ inspect(@skip_checks)
    assert message =~ ~s((A)
  end

  test "the closest stored option is echoed for a near-miss label", %{questions: questions} do
    assert {:error, %{code: "invalid_arguments", message: message}} =
             submit(questions, %{1 => "Built-in sanity check"})

    assert message =~ "Closest stored option: #{inspect(@sanity_checks)}"
  end

  test "a question without options accepts any prose answer", %{questions: _questions} do
    free_form = """
    1. What should the explorer print on success?
    """

    questions = ClarifyingInbox.parse_questions(free_form)
    assert {:ok, _} = submit(questions, %{1 => "one summary line per reachable state"})

    assert_received {:comment, 9, body}
    assert body =~ "- Answer: one summary line per reachable state"
    refute body =~ "- Matched option:"
  end

  test "answers may arrive keyed by string, as a positional list, or partially", %{
    questions: questions
  } do
    assert {:ok, _} = submit(questions, %{"1" => "B"})
    assert {:ok, _} = submit(questions, ["Built-in sanity checks", "C"])
    assert {:ok, _} = submit(questions, %{2 => "B"})
  end

  test "more positional answers than questions is invalid", %{questions: questions} do
    assert {:error, %{code: "invalid_arguments", message: message}} =
             submit(questions, ["A", "B", "C"])

    assert message =~ "got 3 answers for only 2 clarifying questions"
  end

  test "an answer for an unknown question number is invalid", %{questions: questions} do
    assert {:error, %{code: "invalid_arguments", message: message}} =
             submit(questions, %{99 => "A"})

    assert message =~ "there is no clarifying question numbered 99"
  end

  test "empty and non-string answers are invalid", %{questions: questions} do
    assert {:error, %{code: "invalid_arguments", message: message}} =
             submit(questions, %{1 => "  "})

    assert message =~ "answer 1 is empty"

    assert {:error, %{code: "invalid_arguments", message: message}} =
             submit(questions, %{1 => :b})

    assert message =~ "must be a string, got: :b"

    assert {:error, %{code: "invalid_arguments", message: message}} =
             submit(questions, [:b])

    assert message =~ "answers must be strings, got: [:b]"

    assert {:error, %{code: "invalid_arguments", message: message}} =
             submit(questions, %{"one" => "A"})

    assert message =~ ~s(answer key "one" is not a question number)
  end

  test "no answers at all is invalid", %{questions: questions} do
    assert {:error, %{code: "invalid_arguments", message: message}} = submit(questions, %{})

    assert message =~ "no answers provided"
  end

  test "a commenter failure surfaces as a comment_failed error", %{questions: questions} do
    commenter = fn _issue_number, _body -> {:error, :network_down} end

    assert {:error, %{code: "comment_failed", message: message}} =
             ClarifyingInbox.submit_clarifying_answers(9, questions, %{1 => "A"}, commenter)

    assert message =~ ":network_down"
  end
end
