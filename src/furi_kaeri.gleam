import gleam/erlang/process
import gleam/otp/actor
import group_registry
import mist
import web/router
import web/server

pub fn main() -> Nil {
  let name = process.new_name("board-registry")
  let assert Ok(actor.Started(data: registry, ..)) = group_registry.start(name)
  let assert Ok(actor.Started(data: manager, ..)) = server.start()

  let ctx = router.Context(registry:, manager:)

  let assert Ok(_) =
    fn(req) { router.handle_request(req, ctx) }
    |> mist.new
    |> mist.bind("localhost")
    |> mist.port(1234)
    |> mist.start

  process.sleep_forever()
}
