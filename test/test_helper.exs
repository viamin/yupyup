# The TLC cross-check tests are opt-in: they only run against a real TLC
# installation (YUP_TLC override, or java on PATH with tla2tools on
# CLASSPATH). Everywhere else they are excluded so CI and local runs skip
# cleanly without a TLA+ install (TLA-XC-1).
tlc_exclude = if Yup.Crosscheck.Tlc.find_tlc() == :error, do: [:tlc], else: []

ExUnit.start(exclude: tlc_exclude)
