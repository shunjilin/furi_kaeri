import gleam/erlang/process
import gleam/otp/actor
import group_registry
import mist
import web/api/board
import web/router

pub fn main() -> Nil {
  let name = process.new_name("board-registry")
  let assert Ok(actor.Started(data: registry, ..)) = group_registry.start(name)
  let assert Ok(actor.Started(data: manager, ..)) = board.start_link()

  let ctx = router.Context(registry:, manager:)

  let assert Ok(_) =
    fn(req) { router.handle_request(req, ctx) }
    |> mist.new
    |> mist.bind("localhost")
    |> mist.port(1234)
    |> mist.start

  process.sleep_forever()
}
