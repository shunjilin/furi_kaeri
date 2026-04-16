import domain/board.{type Board}
import domain/card
import domain/lane
import domain/user
import domain/values/non_empty_string
import gleam/erlang/process.{type Subject}
import gleam/list
import group_registry.{type GroupRegistry}
import lustre.{type App}
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import lustre/server_component
import web/api/board as board_api

pub type Model {
  Model(
    board: Board,
    user: user.User,
    registry: GroupRegistry(SharedMsg),
    manager: Subject(board_api.Message),
  )
}

pub opaque type Msg {
  AppReceivedSharedMsg(SharedMsg)
  UserAddedCard(lane_id: lane.LaneId, content: String)
  UserUpdatedBoard(board: board.Board)
  UserReceivedError(String)
}

pub opaque type SharedMsg {
  ApiReturnedBoard(board: board.Board)
}

pub fn component(
  manager: Subject(board_api.Message),
  user: user.User,
) -> App(GroupRegistry(SharedMsg), Model, Msg) {
  lustre.application(init(_, manager, user), update, view)
}

fn init(
  registry: GroupRegistry(SharedMsg),
  manager: Subject(board_api.Message),
  user: user.User,
) -> #(Model, Effect(Msg)) {
  let self = process.new_subject()

  process.send(manager, board_api.GetBoard(reply_to: self))

  let initial_board = case process.receive(self, 1000) {
    Ok(b) -> b
    Error(_) -> board_api.init_board()
  }

  let model =
    Model(
      board: initial_board,
      user: user,
      registry: registry,
      manager: manager,
    )

  #(model, subscribe(registry, AppReceivedSharedMsg))
}

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    UserAddedCard(lane_id, content) -> {
      let effect =
        effect.from(fn(dispatch) {
          let result =
            process.call(model.manager, 1000, fn(reply_to) {
              board_api.AddCard(
                user_id: user.id(model.user),
                lane_id: lane_id,
                content: content,
                reply_to: reply_to,
              )
            })
          case result {
            Ok(updated_board) -> dispatch(UserUpdatedBoard(updated_board))
            Error(error) -> dispatch(UserReceivedError(error))
          }
        })
      #(model, effect)
    }
    UserUpdatedBoard(updated_board) -> {
      #(model, broadcast(model.registry, ApiReturnedBoard(updated_board)))
    }
    UserReceivedError(_) -> {
      // todo: handle error
      #(model, effect.none())
    }
    AppReceivedSharedMsg(ApiReturnedBoard(updated_board)) -> {
      #(Model(..model, board: updated_board), effect.none())
    }
  }
}

fn view(model: Model) -> Element(Msg) {
  let title = board.title(model.board)
  let lanes = board.lanes(model.board)

  html.div([attribute.class("center")], [
    html.h1([], [html.text(non_empty_string.to_string(title))]),
    html.div(
      [attribute.style("display", "flex"), attribute.style("gap", "1rem")],
      list.map(lanes, render_lane),
    ),
  ])
}

fn render_lane(lane: lane.Lane) -> Element(Msg) {
  let title = lane.title(lane)
  let id = lane.id(lane)

  html.div(
    [
      attribute.class("box"),
      attribute.style("--background-color", "var(--color-bg-secondary)"),
    ],
    [
      html.div([attribute.class("stack")], [
        html.h2([], [html.text(non_empty_string.to_string(title))]),
        html.div(
          [attribute.class("stack")],
          list.map(lane.cards(lane), render_card),
        ),
        html.button(
          [
            event.on_click(UserAddedCard(lane_id: id, content: "Woo")),
          ],
          [html.text("+ Add Card")],
        ),
      ]),
    ],
  )
}

fn render_card(card: card.Card) -> Element(Msg) {
  html.div(
    [
      attribute.class("box"),
      attribute.style("--background-color", "var(--color-bg-tertiary)"),
    ],
    [
      html.text(non_empty_string.to_string(card.content(card))),
    ],
  )
}

fn subscribe(registry, msg_wrapper) -> Effect(msg) {
  use _, _ <- server_component.select
  let subject = group_registry.join(registry, "board", process.self())
  process.new_selector() |> process.select_map(subject, msg_wrapper)
}

fn broadcast(registry: GroupRegistry(msg), msg: msg) -> Effect(any) {
  use _ <- effect.from
  list.each(group_registry.members(registry, "board"), process.send(_, msg))
}
