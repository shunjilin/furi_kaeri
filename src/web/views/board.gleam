import domain/board
import domain/card
import domain/lane
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
import lustre
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import lustre/server_component
import web/api/board as board_api
import web/shared_message
import youid/uuid

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

pub type CardView {
  ShowCardView(
    id: card.CardId,
    lane_id: lane.LaneId,
    content: String,
    is_author: Bool,
  )
  EditCardView(id: card.CardId, lane_id: lane.LaneId, content: String)
  ReviewCardView(id: card.CardId, lane_id: lane.LaneId, content: String)
  VotingCardView(
    id: card.CardId,
    lane_id: lane.LaneId,
    content: String,
    voted: Bool,
  )
  TalliedCardView(
    id: card.CardId,
    lane_id: lane.LaneId,
    content: String,
    vote_count: Int,
  )
}

pub type LaneView {
  LaneView(
    id: lane.LaneId,
    title: String,
    cards: List(CardView),
    draft: String,
    allow_adding: Bool,
  )
}

pub type BoardView {
  BoardView(title: String, lanes: List(LaneView))
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
  UserRevealedBoardContents
  UserDraggedCard(CardUnderDrag)
  UserDroppedCard(CardDroppedOn)
  UserStartedVoting
  UserAddedCardVote(card_id: card.CardId)
  UserRemovedCardVote(card_id: card.CardId)
  UserRevealedVotes
  UserReceivedError(String)
}

pub fn component(
  manager: Subject(board_api.Message),
  user: user.User,
  board_id: String,
  connection_id: String,
) -> lustre.App(Nil, Model, Msg) {
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
    UserUpdatedDraftCard(lane_id, content) -> {
      let cards_under_draft =
        dict.insert(model.cards_under_draft, lane_id, content)
      #(Model(..model, cards_under_draft:), effect.none())
    }

    UserSetEditCard(lane_id, card_id, content) -> {
      let cards_under_edit =
        dict.insert(model.cards_under_edit, #(lane_id, card_id), content)
      #(Model(..model, cards_under_edit:), effect.none())
    }

    UserUnsetEditCard(lane_id, card_id) -> {
      let cards_under_edit =
        dict.delete(model.cards_under_edit, #(lane_id, card_id))
      #(Model(..model, cards_under_edit:), effect.none())
    }

    UserUpdatedEditCard(lane_id, card_id, content) -> {
      let cards_under_edit =
        dict.insert(model.cards_under_edit, #(lane_id, card_id), content)
      #(Model(..model, cards_under_edit:), effect.none())
    }

    UserAddedCard(lane_id, content) -> {
      let run_cmd =
        effect.from(fn(_) {
          process.send(
            model.manager,
            board_api.AddCard(user_id: user.id(model.user), lane_id:, content:),
          )
        })
      let cards_under_draft = dict.insert(model.cards_under_draft, lane_id, "")
      #(Model(..model, cards_under_draft:), run_cmd)
    }

    UserEditedCard(lane_id, card_id, content) -> {
      let run_cmd =
        effect.from(fn(_) {
          process.send(
            model.manager,
            board_api.EditCard(user_id: user.id(model.user), card_id:, content:),
          )
        })
      let cards_under_edit =
        dict.delete(model.cards_under_edit, #(lane_id, card_id))
      #(Model(..model, cards_under_edit:), run_cmd)
    }

    UserDeletedCard(card_id) -> {
      let run_cmd =
        effect.from(fn(_) {
          process.send(
            model.manager,
            board_api.RemoveCard(user_id: user.id(model.user), card_id:),
          )
        })
      #(model, run_cmd)
    }

    UserRevealedBoardContents -> {
      let run_cmd =
        effect.from(fn(_) {
          process.send(model.manager, board_api.RevealCardContents)
        })
      #(model, run_cmd)
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
          let run_cmd =
            effect.from(fn(_) {
              process.send(
                model.manager,
                board_api.MergeCard(from_card_id, to_card_id),
              )
            })
          #(model, run_cmd)
        }
      }
    }

    UserStartedVoting -> {
      let run_cmd =
        effect.from(fn(_) { process.send(model.manager, board_api.StartVoting) })
      #(model, run_cmd)
    }

    UserAddedCardVote(card_id) -> {
      let run_cmd =
        effect.from(fn(_) {
          process.send(
            model.manager,
            board_api.Vote(user.id(model.user), card_id),
          )
        })
      #(model, run_cmd)
    }

    UserRemovedCardVote(card_id) -> {
      let run_cmd =
        effect.from(fn(_) {
          process.send(
            model.manager,
            board_api.RemoveVote(user.id(model.user), card_id),
          )
        })
      #(model, run_cmd)
    }

    UserRevealedVotes -> {
      let run_cmd =
        effect.from(fn(_) { process.send(model.manager, board_api.RevealVotes) })
      #(model, run_cmd)
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

fn build_view_projections(model: Model) -> BoardView {
  let user_id = user.id(model.user)
  let title = non_empty_string.to_string(board.title(model.board))

  let lanes =
    list.map(board.lanes(model.board), fn(lane) {
      let lane_id = lane.id(lane)
      let draft =
        dict.get(model.cards_under_draft, lane_id) |> result.unwrap("")

      let #(cards, allow_adding) = case board.phase(model.board) {
        board.DraftBoard(cards_dict) -> {
          let mapped =
            project_cards(cards_dict, lane_id, model, user_id, map_draft_card)
          #(mapped, True)
        }
        board.ReviewBoard(cards_dict) -> {
          let mapped =
            project_cards(cards_dict, lane_id, model, user_id, map_review_card)
          #(mapped, False)
        }
        board.VotingBoard(cards_dict) -> {
          let mapped =
            project_cards(cards_dict, lane_id, model, user_id, map_voting_card)
          #(mapped, False)
        }
        board.TallyBoard(cards_dict) -> {
          let mapped =
            project_cards(cards_dict, lane_id, model, user_id, map_tallied_card)
          #(mapped, False)
        }
      }

      LaneView(
        id: lane_id,
        title: lane |> lane.title() |> non_empty_string.to_string(),
        cards:,
        draft:,
        allow_adding:,
      )
    })

  BoardView(title:, lanes:)
}

fn project_cards(
  cards_dict: dict.Dict(card.CardId, #(lane.LaneId, card.Card(phase))),
  lane_id: lane.LaneId,
  model: Model,
  user_id: user.UserId,
  mapper: fn(card.Card(phase), lane.LaneId, Model, user.UserId) -> CardView,
) -> List(CardView) {
  dict.values(cards_dict)
  |> list.filter(fn(entry) { entry.0 == lane_id })
  |> list.map(fn(entry) { mapper(entry.1, lane_id, model, user_id) })
}

fn map_draft_card(
  card: card.Card(card.Draft),
  lane_id: lane.LaneId,
  model: Model,
  user_id: user.UserId,
) -> CardView {
  let content = non_empty_string.to_string(card.content(card))

  case dict.get(model.cards_under_edit, #(lane_id, card.id(card))) {
    Ok(edit_content) ->
      EditCardView(id: card.id(card), lane_id:, content: edit_content)
    Error(_) -> {
      let masked = maybe_mask(user_id, content, card.author_id(card))
      let is_author = card.author_id(card) == user_id
      ShowCardView(id: card.id(card), lane_id:, content: masked, is_author:)
    }
  }
}

fn map_review_card(
  card: card.Card(card.Review),
  lane_id: lane.LaneId,
  _model: Model,
  _user_id: user.UserId,
) -> CardView {
  ReviewCardView(
    id: card.id(card),
    lane_id:,
    content: card |> card.content() |> non_empty_string.to_string(),
  )
}

fn map_voting_card(
  card: card.Card(card.Voting),
  lane_id: lane.LaneId,
  _model: Model,
  user_id: user.UserId,
) -> CardView {
  VotingCardView(
    id: card.id(card),
    lane_id:,
    content: card |> card.content() |> non_empty_string.to_string(),
    voted: card.voted(card, user_id),
  )
}

fn map_tallied_card(
  card: card.Card(card.Tallied),
  lane_id: lane.LaneId,
  _model: Model,
  _user_id: user.UserId,
) -> CardView {
  TalliedCardView(
    id: card.id(card),
    lane_id:,
    content: card |> card.content() |> non_empty_string.to_string(),
    vote_count: card.vote_count(card),
  )
}

fn maybe_mask(
  user_id: user.UserId,
  content: String,
  author_id: user.UserId,
) -> String {
  use <- bool.guard(when: user_id == author_id, return: content)
  content |> string.length() |> string.repeat("*", _)
}

fn view(model: Model) -> Element(Msg) {
  let board_view = build_view_projections(model)

  html.div([attribute.class("horizontal-center")], [
    html.div([attribute.class("heading")], [
      html.h1([], [html.text(board_view.title)]),
      case board.phase(model.board) {
        board.DraftBoard(_) ->
          html.button(
            [
              attribute.class("button"),
              attribute.data(
                "confirm",
                "Are you ready to reveal the board's contents?",
              ),
              event.on_click(UserRevealedBoardContents),
            ],
            [html.text("Reveal Card Contents")],
          )
        board.ReviewBoard(_) ->
          html.button(
            [
              attribute.class("button"),
              attribute.data("confirm", "Are you ready to start voting?"),
              event.on_click(UserStartedVoting),
            ],
            [html.text("Start Voting")],
          )
        board.VotingBoard(_) ->
          html.button(
            [
              attribute.class("button"),
              attribute.data("confirm", "Are you ready to reveal all votes?"),
              event.on_click(UserRevealedVotes),
            ],
            [html.text("Reveal Votes")],
          )

        _ -> element.none()
      },
    ]),
    html.div(
      [attribute.style("display", "flex"), attribute.style("gap", "1rem")],
      list.map(board_view.lanes, render_lane),
    ),
  ])
}

fn render_lane(lane: LaneView) -> Element(Msg) {
  html.div([attribute.class("lane")], [
    html.div([attribute.class("stack")], [
      html.h2([], [html.text(lane.title)]),
      case lane.allow_adding {
        True -> render_add_card(lane.id, lane.draft)
        False -> element.none()
      },
      case lane.cards {
        [] -> element.none()
        cards ->
          html.div([attribute.class("stack")], list.map(cards, render_card))
      },
    ]),
  ])
}

fn render_add_card(lane_id: lane.LaneId, draft: String) -> Element(Msg) {
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
          attribute.placeholder("Add a card..."),
          attribute.rows(3),
          event.debounce(
            event.on_input(fn(content) {
              UserUpdatedDraftCard(lane_id:, content:)
            }),
            200,
          ),
        ],
        draft,
      ),
      html.div([attribute.class("card__actions")], [
        html.button([attribute.class("button"), attribute.type_("submit")], [
          html.text("Submit"),
        ]),
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
    ReviewCardView(id, _, content) ->
      html.div(
        [
          attribute.id("card-" <> card_id_as_string),
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
              dispatch: UserDraggedCard(CardUnderDrag(id)),
              prevent_default: False,
              stop_propagation: False,
            )),
          ),
          event.advanced(
            "drop",
            decode.success(event.handler(
              dispatch: UserDroppedCard(CardDroppedOn(id)),
              prevent_default: True,
              stop_propagation: False,
            )),
          ),
        ],
        [html.div([], [html.text(content)])],
      )

    VotingCardView(id, _, content, voted) ->
      html.div([attribute.class("card")], [
        html.div([], [html.text(content)]),
        html.div([attribute.class("card__actions")], [
          html.div([], [
            html.text(case voted {
              True -> "1"
              False -> "0"
            }),
          ]),
          case voted {
            False ->
              html.button(
                [
                  attribute.class("button"),
                  attribute.class("vote"),
                  event.on_click(UserAddedCardVote(id)),
                ],
                [html.text("Vote")],
              )
            True ->
              html.button(
                [
                  attribute.class("button"),
                  attribute.class("vote"),
                  event.on_click(UserRemovedCardVote(id)),
                ],
                [html.text("Remove Vote")],
              )
          },
        ]),
      ])

    TalliedCardView(_, _, content, vote_count) -> {
      html.div([attribute.class("card")], [
        html.div([], [html.text(content)]),
        html.div([attribute.class("card__actions")], [
          html.div([], [html.text(int.to_string(vote_count) <> " votes")]),
        ]),
      ])
    }

    ShowCardView(id, lane_id, content, is_author) -> {
      let edit_button = case is_author {
        True ->
          html.button(
            [
              attribute.class("button"),
              attribute.class("card__edit"),
              event.on_click(UserSetEditCard(lane_id, id, content)),
            ],
            [html.text("Edit")],
          )
        False -> element.none()
      }

      let delete_button = case is_author {
        True ->
          html.button(
            [
              attribute.class("button"),
              attribute.data("type", "delete"),
              attribute.data(
                "confirm",
                "Are you sure you want to delete this card?",
              ),
              event.on_click(UserDeletedCard(id)),
            ],
            [html.text("Delete")],
          )
        False -> element.none()
      }

      html.div([attribute.class("card")], [
        html.div([], [html.text(content)]),
        html.div([attribute.class("card__actions")], [
          edit_button,
          delete_button,
        ]),
      ])
    }

    EditCardView(id, lane_id, content) ->
      html.form(
        [
          attribute.class("card"),
          event.on_submit(fn(_) {
            UserEditedCard(lane_id:, card_id: id, content:)
          }),
        ],
        [
          html.textarea(
            [
              attribute.id(lane_id_as_string <> "edit"),
              attribute.aria_label("Edit Card"),
              attribute.required(True),
              attribute.placeholder("Edit card.."),
              attribute.rows(3),
              event.debounce(
                event.on_input(fn(c) {
                  UserUpdatedEditCard(lane_id:, card_id: id, content: c)
                }),
                200,
              ),
            ],
            content,
          ),
          html.div([attribute.class("card__actions")], [
            html.button([attribute.class("button"), attribute.type_("submit")], [
              html.text("Edit"),
            ]),
          ]),
        ],
      )
  }
}
