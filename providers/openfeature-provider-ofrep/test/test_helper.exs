Application.ensure_all_started(:mimic)

Mimic.copy(Req)
Mimic.copy(Req.Request)

ExUnit.start()
