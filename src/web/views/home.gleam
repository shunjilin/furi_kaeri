import gleam/list
import lustre
import lustre/attribute
import lustre/element
import lustre/element/html
import lustre/event

pub opaque type Model {
  Model(lanes: List(String))
}

pub opaque type Msg {
  UserRemovedLane
  UserAddedLane
}

pub fn component() -> lustre.App(Nil, Model, Msg) {
  lustre.simple(init, update, view)
}

fn init(_) -> Model {
  Model(lanes: ["Start", "Stop", "Continue"])
}

fn update(model: Model, msg: Msg) -> Model {
  case msg {
    UserRemovedLane -> {
      Model(lanes: list.take(model.lanes, list.length(model.lanes) - 1))
    }
    UserAddedLane -> {
      Model(lanes: list.append(model.lanes, [""]))
    }
  }
}

fn view(model: Model) -> element.Element(Msg) {
  html.form(
    [
      attribute.class("stack center create-lanes-form"),
      attribute.method("POST"),
      attribute.action("/board/create"),
    ],
    [
      render_lane_title_inputs(model.lanes),
      html.button(
        [
          attribute.class("button"),
          attribute.type_("submit"),
        ],
        [html.text("Create New Board")],
      ),
    ],
  )
}

fn render_lane_title_inputs(lanes: List(String)) -> element.Element(Msg) {
  let length = list.length(lanes)
  html.div(
    [
      attribute.class("stack"),
      attribute.role("group"),
      attribute.aria_labelledby("create-lanes-title"),
    ],
    [
      html.div(
        [
          attribute.class("create-lanes-form__title"),
          attribute.id("create-lanes-title"),
        ],
        [
          html.text("Lanes"),
        ],
      ),
      ..list.index_map(lanes, fn(lane, index) {
        html.div([attribute.class("cluster")], [
          html.input([
            attribute.value(lane),
            attribute.required(True),
            attribute.name("lanes[]"),
          ]),
          case index {
            index if index == 0 && length == 1 ->
              html.button(
                [
                  attribute.class("button"),
                  attribute.type_("button"),
                ],
                [
                  html.text("Add Lane"),
                ],
              )
            index if index != 0 && index == length - 1 ->
              html.div([attribute.class("cluster")], [
                html.button(
                  [
                    attribute.class("button"),
                    attribute.type_("button"),
                    event.on_click(UserRemovedLane),
                  ],
                  [html.text("Remove Lane")],
                ),
                html.button(
                  [
                    attribute.class("button"),
                    attribute.type_("button"),
                    event.on_click(UserAddedLane),
                  ],
                  [
                    html.text("Add Lane"),
                  ],
                ),
              ])

            _ -> element.none()
          },
        ])
      })
    ],
  )
}
