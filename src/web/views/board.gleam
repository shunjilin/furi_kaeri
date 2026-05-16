import domain/board
import domain/card
import domain/lane
import domain/phase
import domain/user
import domain/values/non_empty_string
import gleam/bool
import gleam/dict
import gleam/dynamic/decode
import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/io
import gleam/list
import gleam/option
import gleam/result
import gleam/string
import lustre.{type App}
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import lustre/server_component
import web/api/board as board_api
import web/shared_message
import youid/uuid

pub type CardView {
  ShowCardView(id: card.CardId, lane_id: lane.LaneId, content: String)
  EditCardView(id: card.CardId, lane_id: lane.LaneId, content: String)
  PreviewCardView(id: card.CardId, lane_id: lane.LaneId, content: String)
  VotingCardView(
    id: card.CardId,
    lane_id: lane.LaneId,
    content: String,
    vote_count: Int,
    voted: Bool,
  )
}

pub type LaneView {
  LaneView(id: lane.LaneId, title: String, cards: List(CardView), draft: String)
}

pub type BoardView {
  BoardView(title: String, lanes: List(LaneView))
}

fn board_view_from_board(
  user_id: user.UserId,
  board: board.Board,
  cards_under_draft: CardsUnderDraft,
  cards_under_edit: CardsUnderEdit,
  phase: phase.Phase,
) -> BoardView {
  BoardView(
    title: non_empty_string.to_string(board.title(board)),
    lanes: list.map(board.lanes(board), lane_view_from_lane(
      user_id,
      _,
      cards_under_draft,
      cards_under_edit,
      phase,
    )),
  )
}

fn lane_view_from_lane(
  user_id: user.UserId,
  lane: lane.Lane,
  cards_under_draft: CardsUnderDraft,
  cards_under_edit: CardsUnderEdit,
  phase: phase.Phase,
) -> LaneView {
  let draft =
    cards_under_draft
    |> dict.get(lane.id(lane))
    |> result.unwrap("")
  LaneView(
    id: lane.id(lane),
    title: lane |> lane.title() |> non_empty_string.to_string(),
    cards: list.map(lane.cards(lane), card_view_from_card(
      user_id,
      lane.id(lane),
      _,
      cards_under_edit,
      phase,
    )),
    draft:,
  )
}

fn card_view_from_card(
  user_id: user.UserId,
  lane_id: lane.LaneId,
  card: card.Card,
  cards_under_edit: CardsUnderEdit,
  phase: phase.Phase,
) -> CardView {
  use <- bool.guard(
    when: phase == phase.Voting,
    return: VotingCardView(
      id: card.id(card),
      lane_id: lane_id,
      content: card |> card.content() |> non_empty_string.to_string(),
      vote_count: card.vote_count(card),
      voted: card.voted(card, user_id),
    ),
  )

  use <- bool.guard(
    when: phase == phase.Preview,
    return: PreviewCardView(
      id: card.id(card),
      lane_id: lane_id,
      content: card |> card.content() |> non_empty_string.to_string(),
    ),
  )

  cards_under_edit
  |> dict.get(#(lane_id, card.id(card)))
  |> result.map(fn(content) {
    EditCardView(id: card.id(card), lane_id: lane_id, content:)
  })
  |> result.unwrap(ShowCardView(
    id: card.id(card),
    lane_id: lane_id,
    content: card
      |> card.content()
      |> non_empty_string.to_string()
      |> maybe_mask(user_id, _, card.author_id(card)),
  ))
}

/// mask the card if unrevealed and not belonging to user
/// TODO: maybe make this a function to render the ShowCardView and add a
/// masked property so we can render the necessary screen reader attributes
fn maybe_mask(
  user_id: user.UserId,
  content: String,
  author_id: user.UserId,
) -> String {
  use <- bool.guard(when: user_id == author_id, return: content)
  content |> string.length |> string.repeat("*", _)
}

fn update_draft(
  cards_under_draft: CardsUnderDraft,
  lane_id: lane.LaneId,
  content: String,
) -> CardsUnderDraft {
  dict.insert(cards_under_draft, lane_id, content)
}

fn unset_edit_card(
  cards_under_edit: CardsUnderEdit,
  lane_id: lane.LaneId,
  card_id: card.CardId,
) -> CardsUnderEdit {
  dict.delete(cards_under_edit, #(lane_id, card_id))
}

fn update_edit_card(
  cards_under_edit: CardsUnderEdit,
  lane_id: lane.LaneId,
  card_id: card.CardId,
  content: String,
) -> CardsUnderEdit {
  dict.insert(cards_under_edit, #(lane_id, card_id), content)
}

type CardsUnderDraft =
  dict.Dict(lane.LaneId, String)

type CardsUnderEdit =
  dict.Dict(#(lane.LaneId, card.CardId), String)

pub type CardUnderDrag {
  CardUnderDrag(card_id: card.CardId)
}

pub type CardDroppedOn {
  CardDroppedOn(card_id: card.CardId)
}

pub type Model {
  Model(
    board: board.Board,
    cards_under_draft: CardsUnderDraft,
    cards_under_edit: CardsUnderEdit,
    card_under_drag: option.Option(CardUnderDrag),
    user: user.User,
    manager: Subject(board_api.Message),
  )
}

pub opaque type Msg {
  AppReceivedSharedMsg(shared_message.SharedMsg)
  UserUpdatedDraftCard(lane_id: lane.LaneId, content: String)
  UserSetEditCard(lane_id: lane.LaneId, card_id: card.CardId, content: String)
  UserUnsetEditCard(lane_id: lane.LaneId, card_id: card.CardId)
  UserUpdatedEditCard(
    lane_id: lane.LaneId,
    card_id: card.CardId,
    content: String,
  )
  UserEditedCard(lane_id: lane.LaneId, card_id: card.CardId, content: String)
  UserAddedCard(lane_id: lane.LaneId, content: String)
  UserDeletedCard(card_id: card.CardId)
  UserRevealedBoard
  UserDraggedCard(CardUnderDrag)
  UserDroppedCard(CardDroppedOn)
  UserStartedVoting
  UserAddedCardVote(card_id: card.CardId)
  UserRemovedCardVote(card_id: card.CardId)
  UserReceivedError(String)
  UserCrashedApp
}

pub fn component(
  manager: Subject(board_api.Message),
  user: user.User,
  board_id: String,
  connection_id: String,
) -> App(Nil, Model, Msg) {
  lustre.application(
    fn(_) { init(manager, user, board_id, connection_id) },
    update,
    view,
  )
}

fn init(
  manager: Subject(board_api.Message),
  user: user.User,
  board_id: String,
  connection_id: String,
) -> #(Model, Effect(Msg)) {
  let self = process.new_subject()

  process.send(manager, board_api.GetBoard(reply_to: self))

  let initial_board = case process.receive(self, 1000) {
    Ok(board) -> board
    Error(_) -> board_api.init_board(board_id)
  }

  let model =
    Model(
      board: initial_board,
      cards_under_draft: dict.new(),
      cards_under_edit: dict.new(),
      user: user,
      manager: manager,
      card_under_drag: option.None,
    )

  let pubsub_effect = {
    use _, subject <- server_component.select
    process.send(manager, board_api.Subscribe(connection_id, subject))

    process.new_selector()
    |> process.select_map(subject, AppReceivedSharedMsg)
  }

  #(model, pubsub_effect)
}

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    UserCrashedApp -> {
      let assert Ok(pid) = process.subject_owner(model.manager)
      process.kill(pid)
      #(model, effect.none())
    }

    UserUpdatedDraftCard(lane_id, content) -> {
      let cards_under_draft =
        update_draft(model.cards_under_draft, lane_id, content)
      #(Model(..model, cards_under_draft:), effect.none())
    }
    UserSetEditCard(lane_id, card_id, content) -> {
      let cards_under_edit =
        update_edit_card(model.cards_under_edit, lane_id, card_id, content)
      #(Model(..model, cards_under_edit:), effect.none())
    }
    UserUnsetEditCard(lane_id, card_id) -> {
      let cards_under_edit =
        unset_edit_card(model.cards_under_edit, lane_id, card_id)
      #(Model(..model, cards_under_edit:), effect.none())
    }
    UserUpdatedEditCard(lane_id, card_id, content) -> {
      let cards_under_edit =
        update_edit_card(model.cards_under_edit, lane_id, card_id, content)
      #(Model(..model, cards_under_edit:), effect.none())
    }
    UserAddedCard(lane_id, content) -> {
      let effect =
        effect.from(fn(_) {
          process.send(
            model.manager,
            board_api.AddCard(
              user_id: user.id(model.user),
              lane_id: lane_id,
              content: content,
            ),
          )
        })
      let cards_under_draft = update_draft(model.cards_under_draft, lane_id, "")
      #(Model(..model, cards_under_draft:), effect)
    }
    UserEditedCard(lane_id, card_id, content) -> {
      let effect =
        effect.from(fn(_) {
          process.send(
            model.manager,
            board_api.EditCard(
              user_id: user.id(model.user),
              card_id: card_id,
              content: content,
            ),
          )
        })
      let cards_under_edit =
        unset_edit_card(model.cards_under_edit, lane_id, card_id)
      #(Model(..model, cards_under_edit:), effect)
    }
    UserDeletedCard(card_id) -> {
      let effect =
        effect.from(fn(_) {
          process.send(
            model.manager,
            board_api.RemoveCard(user_id: user.id(model.user), card_id: card_id),
          )
        })

      #(model, effect)
    }
    UserRevealedBoard -> {
      let effect =
        effect.from(fn(_) { process.send(model.manager, board_api.RevealBoard) })

      #(model, effect)
    }
    UserDraggedCard(card_under_drag) -> {
      #(
        Model(..model, card_under_drag: option.Some(card_under_drag)),
        effect.none(),
      )
    }
    UserDroppedCard(CardDroppedOn(to_card_id)) -> {
      case model.card_under_drag {
        option.None -> #(model, effect.none())
        option.Some(CardUnderDrag(from_card_id)) -> {
          let effect =
            effect.from(fn(_) {
              process.send(
                model.manager,
                board_api.MergeCard(from_card_id, to_card_id),
              )
            })

          #(model, effect)
        }
      }
    }
    UserStartedVoting -> {
      let effect =
        effect.from(fn(_) { process.send(model.manager, board_api.StartVoting) })

      #(model, effect)
    }
    UserAddedCardVote(card_id) -> {
      let effect =
        effect.from(fn(_) {
          process.send(
            model.manager,
            board_api.Vote(user.id(model.user), card_id),
          )
        })
      #(model, effect)
    }
    UserRemovedCardVote(card_id) -> {
      let effect =
        effect.from(fn(_) {
          process.send(
            model.manager,
            board_api.RemoveVote(user.id(model.user), card_id),
          )
        })

      #(model, effect)
    }
    UserReceivedError(err) -> {
      io.println(err)
      #(model, effect.none())
    }
    AppReceivedSharedMsg(shared_message.ApiReturnedBoard(updated_board)) -> {
      #(Model(..model, board: updated_board), effect.none())
    }
    AppReceivedSharedMsg(shared_message.ApiReturnedError(_error)) -> {
      #(model, effect.none())
    }
  }
}

fn view(model: Model) -> Element(Msg) {
  let phase = board.phase(model.board)
  let board_view =
    board_view_from_board(
      user.id(model.user),
      model.board,
      model.cards_under_draft,
      model.cards_under_edit,
      phase,
    )

  html.div([attribute.class("horizontal-center")], [
    html.div([attribute.class("heading")], [
      html.h1([], [html.text(board_view.title)]),
      html.button(
        [
          attribute.class("button"),
          attribute.data("type", "delete"),
          event.on_click(UserCrashedApp),
        ],
        [html.text("Crash Actor (For Testing)")],
      ),
      maybe_render(
        html.button(
          [
            attribute.class("button"),
            attribute.data("confirm", "Are you ready to start voting?"),
            event.on_click(UserStartedVoting),
          ],
          [html.text("Start Voting")],
        ),
        phase == phase.Preview,
      ),
      maybe_render(
        html.button(
          [
            attribute.class("button"),
            attribute.data("confirm", "Are you ready to reveal the board?"),
            event.on_click(UserRevealedBoard),
          ],
          [html.text("Reveal Board")],
        ),
        phase == phase.Draft,
      ),
    ]),
    html.div(
      [attribute.style("display", "flex"), attribute.style("gap", "1rem")],
      list.map(board_view.lanes, render_lane(_, phase)),
    ),
  ])
}

fn render_lane(lane: LaneView, phase: phase.Phase) -> Element(Msg) {
  html.div([attribute.class("lane")], [
    html.div([attribute.class("stack")], [
      html.h2([], [html.text(lane.title)]),
      maybe_render(render_add_card(lane.id, lane.draft), phase == phase.Draft),
      maybe_render(
        html.div([attribute.class("stack")], list.map(lane.cards, render_card)),
        lane.cards != [],
      ),
    ]),
  ])
}

fn maybe_render(element: Element(a), bool: Bool) -> Element(a) {
  case bool {
    True -> element
    False -> element.none()
  }
}

fn render_add_card(lane_id: lane.LaneId, draft: String) {
  let lane.LaneId(lane_id_as_uuid) = lane_id
  let lane_id_as_string = uuid.to_string(lane_id_as_uuid)

  html.form(
    [
      attribute.class("card"),
      event.on_submit(fn(_) { UserAddedCard(lane_id, content: draft) }),
    ],
    [
      html.textarea(
        [
          attribute.id(lane_id_as_string <> "draft"),
          attribute.aria_label("Draft Card"),
          attribute.required(True),
          event.debounce(
            event.on_input(fn(content) {
              UserUpdatedDraftCard(lane_id:, content:)
            }),
            200,
          ),
          attribute.placeholder("Add a card..."),
          attribute.rows(3),
        ],
        draft,
      ),
      html.div([attribute.class("card__actions")], [
        html.button(
          [
            attribute.class("button"),
            attribute.type_("submit"),
          ],
          [html.text("Submit")],
        ),
      ]),
    ],
  )
}

fn render_card(card: CardView) -> Element(Msg) {
  let lane.LaneId(lane_id_as_uuid) = card.lane_id
  let lane_id_as_string = uuid.to_string(lane_id_as_uuid)
  let card.CardId(card_id_as_uuid) = card.id
  let card_id_as_string = uuid.to_string(card_id_as_uuid)
  case card {
    PreviewCardView(..) ->
      html.div(
        [
          attribute.id(string.append(to: "card-", suffix: card_id_as_string)),
          attribute.class("card"),
          attribute.data("dropzone", "true"),
          attribute.draggable(True),
          attribute.data(
            "confirm",
            "Are you sure you want to merge these cards?",
          ),
          event.advanced(
            "dragstart",
            decode.success(event.handler(
              dispatch: UserDraggedCard(CardUnderDrag(card.id)),
              prevent_default: False,
              stop_propagation: False,
            )),
          ),
          event.advanced(
            "drop",
            decode.success(event.handler(
              dispatch: UserDroppedCard(CardDroppedOn(card.id)),
              prevent_default: True,
              stop_propagation: False,
            )),
          ),
        ],
        [
          html.div([], [html.text(card.content)]),
        ],
      )
    VotingCardView(..) ->
      html.div([attribute.class("card")], [
        html.div([], [html.text(card.content)]),
        html.div([attribute.class("card__actions")], [
          html.div([], [html.text(int.to_string(card.vote_count))]),
          maybe_render(
            html.button(
              [
                attribute.class("button"),
                attribute.class("vote"),
                event.on_click(UserAddedCardVote(card.id)),
              ],
              [
                html.text("Vote"),
              ],
            ),
            !card.voted,
          ),
          maybe_render(
            html.button(
              [
                attribute.class("button"),
                attribute.class("vote"),
                event.on_click(UserRemovedCardVote(card.id)),
              ],
              [
                html.text("Remove Vote"),
              ],
            ),
            card.voted,
          ),
        ]),
      ])
    ShowCardView(..) ->
      html.div([attribute.class("card")], [
        html.div([], [html.text(card.content)]),
        html.div([attribute.class("card__actions")], [
          html.button(
            [
              attribute.class("button"),
              attribute.class("card__edit"),
              event.on_click(UserSetEditCard(
                card.lane_id,
                card.id,
                card.content,
              )),
            ],
            [
              html.text("Edit"),
            ],
          ),
          html.button(
            [
              attribute.class("button"),
              attribute.data("type", "delete"),
              attribute.data(
                "confirm",
                "Are you sure you want to delete this card?",
              ),
              event.on_click(UserDeletedCard(card.id)),
            ],
            [
              html.text("Delete"),
            ],
          ),
        ]),
      ])
    EditCardView(..) -> {
      html.form(
        [
          attribute.class("card"),
          event.on_submit(fn(_) {
            UserEditedCard(
              lane_id: card.lane_id,
              card_id: card.id,
              content: card.content,
            )
          }),
        ],
        [
          html.textarea(
            [
              attribute.id(lane_id_as_string <> "edit"),
              attribute.aria_label("Edit Card"),
              attribute.required(True),
              event.debounce(
                event.on_input(fn(content) {
                  UserUpdatedEditCard(
                    lane_id: card.lane_id,
                    card_id: card.id,
                    content:,
                  )
                }),
                200,
              ),
              attribute.placeholder("Edit card.."),
              attribute.rows(3),
            ],
            card.content,
          ),
          html.div([attribute.class("card__actions")], [
            html.button(
              [
                attribute.class("button"),
                attribute.type_("submit"),
              ],
              [html.text("Edit")],
            ),
          ]),
        ],
      )
    }
  }
}
