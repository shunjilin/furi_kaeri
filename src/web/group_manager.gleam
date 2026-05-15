import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/otp/actor
import web/api/board as board_api

pub type Message {
  GetBoard(id: String, reply_to: Subject(Subject(board_api.Message)))
}

pub fn start() {
  dict.new()
  |> actor.new
  |> actor.on_message(handle_message)
  |> actor.start
}

fn handle_message(state: Dict(String, Subject(board_api.Message)), msg: Message) {
  case msg {
    GetBoard(id, reply_to) -> {
      case dict.get(state, id) {
        Ok(manager) -> {
          process.send(reply_to, manager)
          actor.continue(state)
        }
        Error(_) -> {
          let assert Ok(actor.Started(data: manager, ..)) =
            board_api.start_link(id)

          process.send(reply_to, manager)
          actor.continue(dict.insert(state, id, manager))
        }
      }
    }
  }
}

pub fn get_board(
  manager: Subject(Message),
  id: String,
) -> Subject(board_api.Message) {
  process.call(manager, 1000, GetBoard(id, _))
}
