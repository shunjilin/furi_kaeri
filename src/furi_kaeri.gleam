import envoy
import gleam/erlang/process
import gleam/otp/factory_supervisor as factory
import gleam/otp/static_supervisor as supervisor
import gleam/otp/supervision
import gleam/result
import mist
import radiate
import web/api/board as board_api
import web/board_registry
import web/router

pub fn main() -> Nil {
  let env_string = envoy.get("GLEAM_ENV") |> result.unwrap("development")
  let asset_version =
    envoy.get("FLY_MACHINE_VERSION") |> result.unwrap("development")

  let is_production = env_string == "production"

  let _ = case is_production {
    False -> {
      let _ =
        radiate.new()
        |> radiate.add_dir(".")
        |> radiate.start()
      Nil
    }
    True -> Nil
  }

  let board_factory_name = process.new_name("board_factory")
  let board_registry_name = process.new_name("board_registry")

  let assert Ok(_) =
    supervisor.new(supervisor.OneForOne)
    |> supervisor.add(
      factory.worker_child(board_api.start_link)
      |> factory.named(board_factory_name)
      |> factory.supervised,
    )
    |> supervisor.add(
      supervision.worker(fn() {
        board_registry.start(board_factory_name, board_registry_name)
      }),
    )
    |> supervisor.start()

  let ctx =
    router.Context(
      board_registry: board_registry_name,
      cookie_secure: is_production,
      asset_version: asset_version,
    )

  let assert Ok(_) =
    router.handle_request(_, ctx)
    |> mist.new
    |> mist.bind("0.0.0.0")
    |> mist.port(8080)
    |> mist.start

  process.sleep_forever()
}
