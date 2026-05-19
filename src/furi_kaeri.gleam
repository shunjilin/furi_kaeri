import gleam/erlang/process
import gleam/otp/factory_supervisor as factory
import gleam/otp/static_supervisor as supervisor
import gleam/otp/supervision
import mist
import radiate
import web/api/board as board_api
import web/board_registry
import web/router

pub fn main() -> Nil {
  let _ =
    radiate.new()
    |> radiate.add_dir(".")
    |> radiate.start()

  let board_factory_name = process.new_name("board_factory")
  let board_registry_name = process.new_name("board_registry")

  let assert Ok(_) =
    supervisor.new(supervisor.OneForOne)
    |> supervisor.add(
      factory.worker_child(fn(id) {
        board_api.start_link(id, board_registry_name)
      })
      |> factory.named(board_factory_name)
      |> factory.supervised,
    )
    |> supervisor.add(
      supervision.worker(fn() {
        board_registry.start(board_factory_name, board_registry_name)
      }),
    )
    |> supervisor.start()

  let ctx = router.Context(board_registry: board_registry_name)

  let assert Ok(_) =
    router.handle_request(_, ctx)
    |> mist.new
    |> mist.bind("localhost")
    |> mist.port(1234)
    |> mist.start

  process.sleep_forever()
}
