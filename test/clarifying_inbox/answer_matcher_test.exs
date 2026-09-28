defmodule Yup.ClarifyingInbox.AnswerMatcherTest do
  use ExUnit.Case, async: true

  alias Yup.ClarifyingInbox.AnswerMatcher

  @options [
    "Built-in sanity checks) e.g. every transition must change state.",
    "Explicit assertions) users write `assert` expressions inside transitions.",
    "Skip checks) verification stays parsing-only for now."
  ]

  test "matches the exact stored string" do
    assert {:ok, [{1, _}]} = AnswerMatcher.match(@options, hd(@options))
  end

  test "matches the leading label, optionally with trailing commentary" do
    assert {:ok, [{1, _}]} = AnswerMatcher.match(@options, "Built-in sanity checks")
    assert {:ok, [{1, _}]} = AnswerMatcher.match(@options, "built-in sanity checks, mostly")
    assert {:ok, [{1, _}]} = AnswerMatcher.match(@options, "\"Built-in sanity checks\"")
  end

  test "matches letter and number indices in chat decorations" do
    assert {:ok, [{2, _}]} = AnswerMatcher.match(@options, "B")
    assert {:ok, [{2, _}]} = AnswerMatcher.match(@options, "b.")
    assert {:ok, [{2, _}]} = AnswerMatcher.match(@options, "Option B)")
    assert {:ok, [{3, _}]} = AnswerMatcher.match(@options, "3")
    assert {:ok, [{3, _}]} = AnswerMatcher.match(@options, "#3)")
  end

  test "out-of-range indices do not match" do
    assert {:error, _closest} = AnswerMatcher.match(@options, "Z")
    assert {:error, _closest} = AnswerMatcher.match(@options, "9")
  end

  test "label mentions honor word boundaries" do
    assert {:ok, [{1, _}]} =
             AnswerMatcher.match(@options, "I'd go with built-in sanity checks here")

    assert {:error, _closest} =
             AnswerMatcher.match(["Yes", "No", "Maybe"], "yesterday")
  end

  test "combined answers match every referenced option" do
    assert {:ok, [{1, _}, {2, _}]} =
             AnswerMatcher.match(@options, "Built-in sanity checks and Explicit assertions")

    assert {:ok, [{1, _}, {3, _}]} = AnswerMatcher.match(@options, "A or C")

    assert {:ok, [{2, _}, {3, _}]} = AnswerMatcher.match(@options, "both b and c")
  end

  test "combined quoted indices match every referenced option" do
    assert {:ok, [{1, _}, {2, _}]} = AnswerMatcher.match(@options, "\"A\" and \"B\"")
    assert {:ok, [{1, _}, {2, _}]} = AnswerMatcher.match(@options, "'A', 'B'")
    assert {:ok, [{1, _}, {2, _}]} = AnswerMatcher.match(@options, "\"1\" and \"2\"")
    assert {:ok, [{1, _}, {2, _}]} = AnswerMatcher.match(@options, "both \"A\" and \"B\"")
  end

  test "a refined answer that only prefixes the label matches" do
    refined = "Built-in sanity checks, but only evaluation-level checks"

    assert {:ok, [{1, _}]} = AnswerMatcher.match(@options, refined)
  end

  test "unmatched answers report the closest stored option exactly" do
    assert {:error, closest} = AnswerMatcher.match(@options, "Explicit assertion")

    assert closest == "Explicit assertions) users write `assert` expressions inside transitions."
  end

  test "free-form questions accept any non-empty answer and reject empty ones" do
    assert {:ok, []} = AnswerMatcher.match([], "whatever the user decided")
    assert {:error, nil} = AnswerMatcher.match([], "   ")
    assert {:error, nil} = AnswerMatcher.match(@options, "  ")
  end
end
