import domain/board
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
    board: board.Board,
    reply_to: Subject(Result(Subject(board_api.Message), CreateError)),
  )
  GetBoard(
    id: board.BoardId,
    reply_to: Subject(Result(Subject(board_api.Message), GetError)),
  )
  GetNumberOfActiveBoards(reply_to: Subject(Int))
}

pub fn start(
  board_factory_name: process.Name(
    factory.Message(board.Board, process.Subject(board_api.Message)),
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
  state: Dict(board.BoardId, Subject(board_api.Message)),
  msg: Message,
  board_factory_name: process.Name(
    factory.Message(board.Board, process.Subject(board_api.Message)),
  ),
) {
  case msg {
    CreateBoard(board, reply_to) -> {
      case dict.get(state, board.id(board)) {
        Ok(_) -> {
          process.send(reply_to, Error(BoardAlreadyExist))
          actor.continue(state)
        }
        Error(_) -> {
          let board_factory_subject = factory.get_by_name(board_factory_name)
          case factory.start_child(board_factory_subject, board) {
            Ok(actor.Started(data: board_subject, ..)) -> {
              process.send(reply_to, Ok(board_subject))
              actor.continue(dict.insert(state, board.id(board), board_subject))
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
    GetNumberOfActiveBoards(reply_to) -> {
      process.send(reply_to, dict.size(state))
      actor.continue(state)
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
  board: board.Board,
) -> Result(Subject(board_api.Message), CreateError) {
  process.call(manager, 1000, CreateBoard(board, _))
}

pub fn get_board(
  manager: Subject(Message),
  id: board.BoardId,
) -> Result(Subject(board_api.Message), GetError) {
  process.call(manager, 1000, GetBoard(id, _))
}

pub fn get_number_of_active_boards(manager: Subject(Message)) -> Int {
  process.call(manager, 1000, GetNumberOfActiveBoards)
}
