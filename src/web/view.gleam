import domain/board.{type Board}
import domain/card
import domain/lane
import domain/phase.{type Drafting}
import domain/user.{type User}
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
import web/server.{type StateMsg, GetBoard, UpdateBoard}

pub type Model {
  Model(
    board: Board(Drafting),
    user: User,
    registry: GroupRegistry(SharedMsg),
    manager: Subject(StateMsg),
  )
}

pub opaque type Msg {
  AppReceivedSharedMsg(msg: SharedMsg)
  UserAddedCard(card: card.Card(Drafting), lane_id: lane.LaneId)
}

pub opaque type SharedMsg {
  ClientAddedCard(card: card.Card(Drafting), lane_id: lane.LaneId)
}

pub fn component(
  manager: Subject(StateMsg),
) -> App(GroupRegistry(SharedMsg), Model, Msg) {
  lustre.application(init(_, manager), update, view)
}

fn init(
  registry: GroupRegistry(SharedMsg),
  manager: Subject(StateMsg),
) -> #(Model, Effect(Msg)) {
  let user = user.new()
  let self = process.new_subject()

  // Ask the server for the board
  process.send(manager, GetBoard(reply_to: self))

  let initial_board = case process.receive(self, 1000) {
    Ok(b) -> b
    Error(_) -> server.init_board()
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
    AppReceivedSharedMsg(ClientAddedCard(card, lane_id)) -> {
      let result =
        board.update_lane(model.board, lane_id, fn(l) {
          Ok(lane.add_card(l, card))
        })

      case result {
        Ok(updated_board) -> {
          let sync_effect =
            effect.from(fn(_) {
              process.send(model.manager, UpdateBoard(updated_board))
            })
          #(Model(..model, board: updated_board), sync_effect)
        }
        Error(_) -> #(model, effect.none())
      }
    }

    UserAddedCard(card, lane_id) -> {
      #(model, broadcast(model.registry, ClientAddedCard(card, lane_id)))
    }
  }
}

fn view(model: Model) -> Element(Msg) {
  let title = board.title(model.board)
  let lanes = board.lanes(model.board)

  html.div([attribute.style("padding", "2rem")], [
    html.h1([], [html.text(non_empty_string.to_string(title))]),
    html.div(
      [attribute.style("display", "flex"), attribute.style("gap", "1rem")],
      list.map(lanes, render_lane(_, model.user)),
    ),
  ])
}

fn render_lane(lane: lane.Lane(Drafting), user: User) -> Element(Msg) {
  let title = lane.title(lane)
  let id = lane.id(lane)

  html.div(
    [attribute.style("background", "#eee"), attribute.style("padding", "1rem")],
    [
      html.h2([], [html.text(non_empty_string.to_string(title))]),
      html.button(
        [
          event.on_click(UserAddedCard(
            card: card.new(user.id(user), new_string("New Card")),
            lane_id: id,
          )),
        ],
        [html.text("+ Add Card")],
      ),
      html.div([], list.map(lane.cards(lane), render_card)),
    ],
  )
}

fn render_card(card: card.Card(Drafting)) -> Element(Msg) {
  html.div([], [html.text(non_empty_string.to_string(card.content(card)))])
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

fn new_string(str: String) {
  let assert Ok(val) = non_empty_string.new(str)
  val
}
