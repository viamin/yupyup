defmodule Yup.ClarifyingInbox.Question do
  @moduledoc false

  @enforce_keys [:number, :text, :options]
  defstruct [:number, :text, :options]

  @type t :: %__MODULE__{
          number: pos_integer(),
          text: String.t(),
          options: [String.t()]
        }

  @question_line ~r/^\s*(\d+)[.)]\s+(.+)$/
  @option_line ~r/^\s*[-*+]\s+(.+)$/
  @checkbox ~r/\A(?:\[\s*[xX ]?\s*\]|\(\s*[xX ]?\s*\))\s*/

  @spec parse(String.t()) :: [t()]
  def parse(markdown) when is_binary(markdown) do
    markdown
    |> String.replace("\r\n", "\n")
    |> String.split("\n")
    |> Enum.reduce([], &reduce_line/2)
    |> Enum.reverse()
    |> Enum.map(&%{&1 | options: Enum.reverse(&1.options)})
  end

  defp reduce_line(line, questions) do
    case classify(line) do
      {:question, [_, number, text]} ->
        [
          %__MODULE__{number: String.to_integer(number), text: String.trim(text), options: []}
          | questions
        ]

      {:option, [_, option_text]} ->
        add_option(option_text, questions)

      :ignore ->
        questions
    end
  end

  defp classify(line) do
    cond do
      captures = Regex.run(@question_line, line) -> {:question, captures}
      captures = Regex.run(@option_line, line) -> {:option, captures}
      true -> :ignore
    end
  end

  defp add_option(option_text, [question | rest] = questions) do
    case strip_checkbox(option_text) do
      "" ->
        questions

      option ->
        [%{question | options: [option | question.options]} | rest]
    end
  end

  defp add_option(_option_text, [] = questions), do: questions

  defp strip_checkbox(option_text) do
    option_text
    |> String.replace(@checkbox, "")
    |> String.trim()
  end
end
