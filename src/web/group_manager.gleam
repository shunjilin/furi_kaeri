import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/otp/actor
import web/api/board as board_api

pub type CreateError {
  BoardAlreadyExist
}

pub type GetError {
  BoardDoesNotExist
}

pub type Message {
  CreateBoard(
    id: String,
    reply_to: Subject(Result(Subject(board_api.Message), CreateError)),
  )
  GetBoard(
    id: String,
    reply_to: Subject(Result(Subject(board_api.Message), GetError)),
  )
}

pub fn start() {
  dict.new()
  |> actor.new
  |> actor.on_message(handle_message)
  |> actor.start
}

fn handle_message(state: Dict(String, Subject(board_api.Message)), msg: Message) {
  case msg {
    CreateBoard(id, reply_to) -> {
      case dict.get(state, id) {
        Ok(_) -> {
          process.send(reply_to, Error(BoardAlreadyExist))
          actor.continue(state)
        }
        Error(_) -> {
          let assert Ok(actor.Started(data: manager, ..)) =
            board_api.start_link(id)
          process.send(reply_to, Ok(manager))
          actor.continue(dict.insert(state, id, manager))
        }
      }
    }
    GetBoard(id, reply_to) -> {
      case dict.get(state, id) {
        Ok(manager) -> {
          process.send(reply_to, Ok(manager))
          actor.continue(state)
        }
        Error(_) -> {
          process.send(reply_to, Error(BoardDoesNotExist))
          actor.continue(state)
        }
      }
    }
  }
}

pub fn create_board(
  manager: Subject(Message),
  id: String,
) -> Result(Subject(board_api.Message), CreateError) {
  process.call(manager, 1000, CreateBoard(id, _))
}

pub fn get_board(
  manager: Subject(Message),
  id: String,
) -> Result(Subject(board_api.Message), GetError) {
  process.call(manager, 1000, GetBoard(id, _))
}
