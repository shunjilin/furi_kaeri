import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/otp/actor
import gleam/otp/factory_supervisor as factory
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

pub fn start(
  board_factory_name: process.Name(
    factory.Message(String, process.Subject(board_api.Message)),
  ),
  self_name: process.Name(Message),
) {
  dict.new()
  |> actor.new
  |> actor.on_message(fn(state, msg) {
    handle_message(state, msg, board_factory_name)
  })
  |> actor.named(self_name)
  |> actor.start
}

fn handle_message(
  state: Dict(String, Subject(board_api.Message)),
  msg: Message,
  board_factory_name: process.Name(
    factory.Message(String, process.Subject(board_api.Message)),
  ),
) {
  case msg {
    CreateBoard(id, reply_to) -> {
      case dict.get(state, id) {
        Ok(_) -> {
          process.send(reply_to, Error(BoardAlreadyExist))
          actor.continue(state)
        }
        Error(_) -> {
          let board_factory_subject = factory.get_by_name(board_factory_name)
          case factory.start_child(board_factory_subject, id) {
            Ok(actor.Started(data: board_subject, ..)) -> {
              process.send(reply_to, Ok(board_subject))
              actor.continue(dict.insert(state, id, board_subject))
            }
            Error(_) -> {
              process.send(reply_to, Error(BoardAlreadyExist))
              actor.continue(state)
            }
          }
        }
      }
    }
    GetBoard(id, reply_to) -> {
      case dict.get(state, id) {
        Ok(subject) -> {
          case check_subject_alive(subject) {
            True -> {
              process.send(reply_to, Ok(subject))
              actor.continue(state)
            }
            False -> {
              process.send(reply_to, Error(BoardDoesNotExist))
              actor.continue(dict.delete(state, id))
            }
          }
        }
        Error(_) -> {
          process.send(reply_to, Error(BoardDoesNotExist))
          actor.continue(state)
        }
      }
    }
  }
}

fn check_subject_alive(subject: Subject(a)) -> Bool {
  case process.subject_owner(subject) {
    Ok(pid) -> process.is_alive(pid)
    Error(Nil) -> False
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
