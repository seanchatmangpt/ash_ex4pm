# Real collaborators, no mocks: ex4pm's own Application already starts
# Ex4pm.Evidence.Store under its real registered name (application.ex:16).
# Ex4pm.Engine.OnlineMiner is not started by ex4pm's Application by
# default, but Ex4pm.Stream.Ingest.ingest_envelope/1's default :miner
# resolution falls back to that exact real name -- start it here, under
# its real name, so AshEx4pm.Notifier's real (no-opts) ingest_envelope/1
# call resolves a real running miner instead of `nil`.
{:ok, _} = Ex4pm.Engine.OnlineMiner.start_link(name: Ex4pm.Engine.OnlineMiner)

ExUnit.start()
