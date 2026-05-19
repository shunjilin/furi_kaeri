import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/otp/actor
import gleam/otp/factory_supervisor as factory
import web/shared.{type BoardApiMessage, type BoardRegistryMessage}

type Registry =
  Dict(String, Subject(BoardApiMessage))

type State {
  State(self: Subject(BoardRegistryMessage), registry: Registry)
}

pub fn start(
  board_factory_name: process.Name(
    factory.Message(String, process.Subject(BoardApiMessage)),
  ),
  self_name: process.Name(BoardRegistryMessage),
) -> Result(actor.Started(Subject(BoardRegistryMessage)), actor.StartError) {
  actor.new_with_initialiser(1000, fn(subject) {
    actor.initialised(State(self: subject, registry: dict.new()))
    |> actor.returning(subject)
    |> Ok
  })
  |> actor.on_message(fn(state, msg) {
    handle_message(state, msg, board_factory_name)
  })
  |> actor.named(self_name)
  |> actor.start
}

fn handle_message(
  state: State,
  msg: BoardRegistryMessage,
  board_factory_name: process.Name(
    factory.Message(String, process.Subject(BoardApiMessage)),
  ),
) {
  case msg {
    shared.BoardRegistryCreateBoard(id, reply_to) -> {
      case dict.get(state.registry, id) {
        Ok(_) -> {
          process.send(reply_to, Error(shared.BoardAlreadyExist))
          actor.continue(state)
        }
        Error(_) -> {
          let board_factory_subject = factory.get_by_name(board_factory_name)
          case factory.start_child(board_factory_subject, id) {
            Ok(actor.Started(data: board_subject, ..)) -> {
              process.send(reply_to, Ok(board_subject))
              actor.continue(
                State(
                  ..state,
                  registry: dict.insert(state.registry, id, board_subject),
                ),
              )
            }
            Error(_) -> {
              process.send(reply_to, Error(shared.BoardAlreadyExist))
              actor.continue(state)
            }
          }
        }
      }
    }
    shared.BoardRegistryGetBoard(id, reply_to) -> {
      case dict.get(state.registry, id) {
        Ok(subject) -> {
          case check_subject_alive(subject) {
            True -> {
              process.send(reply_to, Ok(subject))
              actor.continue(state)
            }
            False -> {
              process.send(reply_to, Error(shared.BoardDoesNotExist))
              actor.continue(
                State(..state, registry: dict.delete(state.registry, id)),
              )
            }
          }
        }
        Error(_) -> {
          process.send(reply_to, Error(shared.BoardDoesNotExist))
          actor.continue(state)
        }
      }
    }
    shared.BoardRegistryRegisterBoard(id, subject) -> {
      actor.continue(
        State(..state, registry: dict.insert(state.registry, id, subject)),
      )
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
  manager: Subject(BoardRegistryMessage),
  id: String,
) -> Result(Subject(BoardApiMessage), shared.BoardRegistryCreateError) {
  process.call(manager, 1000, shared.BoardRegistryCreateBoard(id, _))
}

pub fn get_board(
  manager: Subject(BoardRegistryMessage),
  id: String,
) -> Result(Subject(BoardApiMessage), shared.BoardRegistryGetError) {
  process.call(manager, 1000, shared.BoardRegistryGetBoard(id, _))
}
