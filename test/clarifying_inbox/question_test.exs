defmodule Yup.ClarifyingInbox.QuestionTest do
  use ExUnit.Case, async: true

  alias Yup.ClarifyingInbox.Question

  test "parses numbered questions with paren and dot numbering" do
    questions =
      Question.parse("""
      1. First question?
      2) Second question?
         - An option
      """)

    assert [
             %Question{number: 1, text: "First question?", options: []},
             %Question{number: 2, text: "Second question?", options: ["An option"]}
           ] = questions
  end

  test "strips checkbox markers from stored options and keeps their exact text" do
    questions =
      Question.parse("""
      1. Pick one
         - ( ) Option one
         - [ ] Option two
         - [x] Option three
         - (x) Option four
         - Plain bullet
      """)

    assert hd(questions).options == [
             "Option one",
             "Option two",
             "Option three",
             "Option four",
             "Plain bullet"
           ]
  end

  test "options before any question and blank lines are ignored" do
    questions =
      Question.parse("""
      Intro prose that is not a question.

      - ( ) Stray option

      1. Real question?
         - ( ) Real option
      """)

    assert [%Question{number: 1, options: ["Real option"]}] = questions
  end

  test "carriage returns and empty option text are tolerated" do
    questions = Question.parse("1. Q?\r\n   - ( )\r\n   - ( ) Kept\r\n")

    assert [%Question{number: 1, options: ["Kept"]}] = questions
  end
end
