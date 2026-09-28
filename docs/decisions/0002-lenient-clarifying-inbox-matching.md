# 0002. Lenient Clarifying-Inbox Answer Matching

## Status

Accepted.

## Decision

`Yup.ClarifyingInbox` accepts a chat-submitted answer for a clarifying
question whenever the answer references at least one offered option:

- by its exact stored string,
- by the option's leading label (the text before the first `)` in the
  stored option, or the whole option when there is no `)`),
- by a word-boundary mention of that label anywhere in the answer, or
- by a one-based letter or number index (`B`, `b.`, `option B`, `2`, `#3`).

Marker prefixes and wrapping quotes in the submitted answer (`- `, `( ) `,
`[ ]`, `(x)`, numbered prefixes, `both `/`either ` fillers) are stripped
before comparison, and comparison is case-insensitive with collapsed
whitespace, so answers copied straight out of the inbox rendering are
accepted. An answer whose separator-delimited segments each reference an
offered option (`A and B`, or two labels joined by "and") is accepted as a
combined choice. When nothing matches, the submission fails with
`invalid_arguments`: the message echoes the closest stored option by its
exact string, enumerates every stored option exactly, and invites a
verbatim resubmit.

Validated answers are posted as an issue comment that carries the answer
verbatim, plus the exact stored strings of the matched options, so
refinements and combinations the user expressed ("Built-in sanity checks,
but only evaluation-level checks") are recorded rather than rejected.
Posting is injected as a function so the tool works against any comment
backend.

## Context

Issue #28: the previous exact-match validator rejected every chat-submitted
answer format, including full option text, so agreements reached in chat had
to be edited into the issue body by hand. Users and assistants routinely
agree on answers that scope or combine offered options, which an exact-match
validator cannot represent at all.

## Consequences

Matching is intentionally lenient: any answer that merely mentions a label
at a word boundary is accepted, which can admit loose prose. That is the
preferred failure direction here, because validation exists to route answers
back into the inbox, not to police phrasing; nuance belongs in the posted
comment body. Matching stays deterministic and string-structural (labels,
indices, word boundaries) rather than semantic, so no model call is needed
and behavior is fully testable. The inbox parser is line-oriented, like the
bootstrap parser (0001), and assumes one-line questions and checkbox-style
bullets.
