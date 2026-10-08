defmodule Yup.Export.TlaTest do
  use ExUnit.Case, async: true

  alias Yup.AST.Program
  alias Yup.Export.Tla
  alias Yup.SourceError

  defp export(source) do
    assert {:ok, %Program{models: [model]}} = Yup.Parser.parse(source, path: "model.yup")
    Tla.export_model(model, path: "model.yup")
  end

  defp export_error(source) do
    assert {:error, %SourceError{} = error} = export(source)
    error
  end

  describe "state and initial state" do
    # @spec TLA-1
    test "exports state fields as TLA+ variables and initializers as Init" do
      assert {:ok, tla} =
               export("""
               model Gate
                 state open = false
                 state knocks = 0

                 transition knock do
                   state.knocks = knocks + 1
                 end
               end
               """)

      assert tla =~ "MODULE Gate"
      assert tla =~ "EXTENDS Naturals"
      assert tla =~ "VARIABLES open, knocks"
      assert tla =~ "vars == << open, knocks >>"
      assert tla =~ "Init ==\n  /\\ open = FALSE\n  /\\ knocks = 0"
    end

    # @spec TLA-1
    test "numbers invariants in declaration order" do
      assert {:ok, tla} =
               export("""
               model Two
                 state n = 0

                 invariant "first" do
                   n >= 0
                 end

                 invariant "second" do
                   n < 100
                 end
               end
               """)

      assert tla =~ "\\* invariant \"first\"\nInvariant1 == (n >= 0)"
      assert tla =~ "\\* invariant \"second\"\nInvariant2 == (n < 100)"
      assert tla =~ "Next == FALSE"
      assert tla =~ "\\*   SPECIFICATION Spec\n\\*   INVARIANT Invariant1\n"
    end
  end

  describe "transitions" do
    # @spec TLA-2
    test "keeps fields the body does not assign UNCHANGED" do
      assert {:ok, tla} =
               export("""
               model Gate
                 state open = false
                 state knocks = 0

                 transition knock do
                   state.knocks = knocks + 1
                 end
               end
               """)

      assert tla =~ "\\* transition knock\nKnock =="
      assert tla =~ "  /\\ knocks' = (knocks + 1)"
      assert tla =~ "  /\\ UNCHANGED << open >>"
      assert tla =~ "Next == Knock"
    end

    # @spec TLA-2
    test "reads fields assigned earlier in the body at their primed values" do
      assert {:ok, tla} =
               export("""
               model Pair
                 state a = 0
                 state b = 0

                 transition bump do
                   state.a = a + 1
                   state.b = a * 2
                 end
               end
               """)

      assert tla =~ "  /\\ a' = (a + 1)"
      assert tla =~ "  /\\ b' = (a' * 2)"
      refute tla =~ "UNCHANGED"
    end
  end

  describe "expressions" do
    # @spec TLA-3
    test "translates operators, atoms, division, and truthiness" do
      assert {:ok, tla} =
               export("""
               model Mixer
                 state count = 7
                 state ok = true

                 invariant "bounded" do
                   count <= 10 and not ok or count != 3
                 end

                 transition halve do
                   state.count = count / 2
                 end
               end
               """)

      assert tla =~ "Init ==\n  /\\ count = 7\n  /\\ ok = TRUE"
      assert tla =~ "Invariant1 == (((count =< 10) /\\ (~ (ok # FALSE))) \\/ (count # 3))"

      assert tla =~
               "  /\\ count' = (IF (count < 0) # (2 < 0) /\\ (count % 2) # 0 " <>
                 "THEN (count div 2) + 1 ELSE (count div 2))"
    end

    # @spec TLA-3
    test "renders division so it matches Elixir's truncation for negative dividends" do
      assert {:ok, tla} =
               export("""
               model Signed
                 state n = 0 - 1

                 transition halve do
                   state.n = n / 2
                 end
               end
               """)

      assert tla =~
               "  /\\ n' = (IF (n < 0) # (2 < 0) /\\ (n % 2) # 0 " <>
                 "THEN (n div 2) + 1 ELSE (n div 2))"
    end

    # @spec TLA-3
    test "wraps non-boolean invariant conditions in a truthiness test" do
      assert {:ok, tla} =
               export("""
               model Vague
                 state count = 0

                 invariant "always something" do
                   count
                 end
               end
               """)

      assert tla =~ "Invariant1 == (count # FALSE)"
    end

    # @spec TLA-3
    test "renders ternaries as TLA+ IF expressions over YupYup truthiness" do
      assert {:ok, tla} =
               export("""
               model Light
                 state value = :off

                 transition toggle do
                   state.value = value == :off ? :on : :off
                 end
               end
               """)

      assert tla =~ "  /\\ value' = (IF (value = \"off\") THEN \"on\" ELSE \"off\")"
    end
  end

  describe "golden modules" do
    # @spec TLA-1
    # @spec TLA-5
    test "exports examples/auth_code.yup byte-for-byte deterministically" do
      {:ok, first} = Tla.export_file("examples/auth_code.yup")
      {:ok, second} = Tla.export_file("examples/auth_code.yup")

      assert first == second
      assert first == auth_code_module()
    end

    # @spec TLA-1
    # @spec TLA-5
    test "exports examples/pkce_exchange.yup byte-for-byte deterministically" do
      {:ok, first} = Tla.export_file("examples/pkce_exchange.yup")
      {:ok, second} = Tla.export_file("examples/pkce_exchange.yup")

      assert first == second
      assert first == pkce_exchange_module()
    end

    # @spec TLA-1
    # @spec TLA-5
    test "exports a model without invariants" do
      assert {:ok, tla} = Tla.export_file("examples/light.yup")

      assert tla == light_module()
    end
  end

  describe "unsupported syntax" do
    # @spec TLA-4
    test "rejects string literals with a source-located diagnostic" do
      error =
        export_error("""
        model Named
          state name = "ada"
        end
        """)

      assert error.message =~ "string literals are not supported in TLA+ export"
      assert error.line == 2
    end

    # @spec TLA-4
    test "rejects nil literals" do
      error =
        export_error("""
        model Nothing
          state value = nil
        end
        """)

      assert error.message =~ "nil literals are not supported in TLA+ export"
    end

    # @spec TLA-4
    test "rejects assigning the same field twice in one transition" do
      error =
        export_error("""
        model Bump
          state a = 0

          transition bump do
            state.a = a + 1
            state.a = a + 2
          end
        end
        """)

      assert error.message =~ "state field a is assigned more than once in transition bump"
      assert error.line == 6
    end

    # @spec TLA-4
    test "rejects names with characters TLA+ identifiers cannot hold" do
      error =
        export_error("""
        model Punct
          state valid? = true
        end
        """)

      assert error.message =~ "state field valid? cannot be exported to TLA+"
    end

    # @spec TLA-4
    test "rejects the reserved field name vars" do
      error =
        export_error("""
        model Hold
          state vars = 0
        end
        """)

      assert error.message =~ "state field vars collides with the generated vars definition"
    end

    # @spec TLA-4
    test "rejects transitions whose action names collide with generated definitions" do
      error =
        export_error("""
        model Confusing
          state a = 0

          transition init do
            state.a = 1
          end
        end
        """)

      assert error.message =~
               "transition init would export as Init, which collides with the generated Init definition"
    end

    # @spec TLA-4
    test "rejects assignment to an undeclared state field" do
      error =
        export_error("""
        model Odd
          state a = 0

          transition oops do
            state.missing = 1
          end
        end
        """)

      assert error.message =~ "assignment to undeclared state field missing"
    end

    # @spec TLA-4
    test "rejects reads of unknown state fields" do
      error =
        export_error("""
        model Odd
          state a = 0

          transition weird do
            state.a = missing
          end
        end
        """)

      assert error.message =~ "unknown state field missing"
    end

    # @spec TLA-4
    test "rejects state reads in initializers" do
      error =
        export_error("""
        model Pair
          state a = 1
          state b = a
        end
        """)

      assert error.message =~ "state initializers cannot read state fields (a)"
    end

    # @spec TLA-4
    test "rejects ordering comparisons against an atom literal" do
      error =
        export_error("""
        model Named
          state verifier = :known

          invariant "never wrong" do
            verifier < :wrong
          end
        end
        """)

      assert error.message =~ "ordering comparisons over non-integer operands"
    end

    # @spec TLA-4
    test "rejects ordering comparisons against a boolean literal" do
      error =
        export_error("""
        model Flag
          state token_issued = false

          invariant "never flagged" do
            token_issued <= false
          end
        end
        """)

      assert error.message =~ "ordering comparisons over non-integer operands"
    end

    # @spec TLA-4
    test "allows equality comparisons against atoms and booleans" do
      assert {:ok, tla} =
               export("""
               model Named
                 state verifier = :known

                 invariant "known or wrong" do
                   verifier == :known or verifier != :wrong
                 end
               end
               """)

      assert tla =~ "Invariant1 =="
    end

    # @spec TLA-4
    test "rejects bare expression statements (no assignment) in transition bodies" do
      error =
        export_error("""
        model Weird
          state a = 0

          transition noop do
            state.a
          end
        end
        """)

      assert error.message =~ "only state updates are supported in exported transition bodies"
    end

    # @spec TLA-4
    test "rejects models with no state fields" do
      error =
        export_error("""
        model Empty
        end
        """)

      assert error.message =~ "model Empty has no state fields to export"
    end
  end

  describe "export_program" do
    # @spec TLA-6
    test "rejects a program with no models" do
      {:ok, program} = Yup.Parser.parse("puts 1\n", path: "none.yup")

      assert {:error, %SourceError{message: message}} =
               Tla.export_program(program, path: "none.yup")

      assert message =~ "expected exactly one model to export, found 0"
    end

    # @spec TLA-6
    test "rejects a program with multiple models" do
      source = """
      model A
        state x = 1
      end

      model B
        state y = 2
      end
      """

      {:ok, program} = Yup.Parser.parse(source, path: "two.yup")

      assert {:error, %SourceError{message: message}} =
               Tla.export_program(program, path: "two.yup")

      assert message =~ "expected exactly one model to export, found 2"
    end
  end

  defp auth_code_module do
    ~S"""
    ---------------------------- MODULE AuthCode ----------------------------
    \* Generated by `yup export tla`.
    EXTENDS Naturals

    VARIABLES issued, redemptions

    vars == << issued, redemptions >>

    Init ==
      /\ issued = FALSE
      /\ redemptions = 0

    \* transition issue
    Issue ==
      /\ issued' = TRUE
      /\ UNCHANGED << redemptions >>

    \* transition redeem
    Redeem ==
      /\ redemptions' = (IF ((issued # FALSE) /\ (redemptions = 0)) THEN (redemptions + 1) ELSE redemptions)
      /\ UNCHANGED << issued >>

    Next == Issue \/ Redeem

    Spec == Init /\ [][Next]_vars

    \* invariant "authorization code is single-use"
    Invariant1 == (redemptions =< 1)

    \* Check with TLC: save this module as AuthCode.tla with a companion
    \* AuthCode.cfg containing:
    \*   SPECIFICATION Spec
    \*   INVARIANT Invariant1
    \* Then run: java tlc2.TLC AuthCode
    =============================================================================
    """
  end

  defp pkce_exchange_module do
    ~S"""
    ---------------------------- MODULE PkceExchange ----------------------------
    \* Generated by `yup export tla`.
    EXTENDS Naturals

    VARIABLES challenge, verifier, token_issued

    vars == << challenge, verifier, token_issued >>

    Init ==
      /\ challenge = "known"
      /\ verifier = "unknown"
      /\ token_issued = FALSE

    \* transition submit_valid_verifier
    SubmitValidVerifier ==
      /\ verifier' = "matching"
      /\ token_issued' = TRUE
      /\ UNCHANGED << challenge >>

    \* transition submit_invalid_verifier
    SubmitInvalidVerifier ==
      /\ verifier' = "wrong"
      /\ token_issued' = FALSE
      /\ UNCHANGED << challenge >>

    Next == SubmitValidVerifier \/ SubmitInvalidVerifier

    Spec == Init /\ [][Next]_vars

    \* invariant "token requires matching verifier"
    Invariant1 == ((~ (token_issued # FALSE)) \/ (verifier = "matching"))

    \* Check with TLC: save this module as PkceExchange.tla with a companion
    \* PkceExchange.cfg containing:
    \*   SPECIFICATION Spec
    \*   INVARIANT Invariant1
    \* Then run: java tlc2.TLC PkceExchange
    =============================================================================
    """
  end

  defp light_module do
    ~S"""
    ---------------------------- MODULE Light ----------------------------
    \* Generated by `yup export tla`.
    EXTENDS Naturals

    VARIABLES value

    vars == << value >>

    Init ==
      /\ value = "off"

    \* transition toggle
    Toggle ==
      /\ value' = (IF (value = "off") THEN "on" ELSE "off")

    Next == Toggle

    Spec == Init /\ [][Next]_vars

    \* Check with TLC: save this module as Light.tla with a companion
    \* Light.cfg containing:
    \*   SPECIFICATION Spec
    \* Then run: java tlc2.TLC Light
    =============================================================================
    """
  end
end
