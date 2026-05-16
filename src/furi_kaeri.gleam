import gleam/erlang/process
import gleam/otp/actor
import mist
import radiate
import web/group_manager
import web/router

pub fn main() -> Nil {
  let _ =
    radiate.new()
    |> radiate.add_dir(".")
    |> radiate.start()

  let assert Ok(actor.Started(data: group_manager, ..)) = group_manager.start()

  let ctx = router.Context(group_manager:)

  let assert Ok(_) =
    fn(req) { router.handle_request(req, ctx) }
    |> mist.new
    |> mist.bind("localhost")
    |> mist.port(1234)
    |> mist.start

  process.sleep_forever()
}
